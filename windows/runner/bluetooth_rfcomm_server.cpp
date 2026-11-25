#include "bluetooth_rfcomm_server.h"

#include <winsock2.h>
#include <windows.h>
#include <ws2bth.h>
#include <bluetoothapis.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <future>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace {

// Custom SPP UUID: {8a7c4b2e-91f3-4d6a-b5e1-2c8f9a0d3e41}
static const GUID kOtpBridgeServiceGuid = {
    0x8a7c4b2e,
    0x91f3,
    0x4d6a,
    {0xb5, 0xe1, 0x2c, 0x8f, 0x9a, 0x0d, 0x3e, 0x41},
};

struct WinBtFrameTask {
  std::vector<uint8_t> payload;
  std::shared_ptr<std::promise<std::vector<uint8_t>>> reply_promise;
};

bool RecvExact(SOCKET s, uint8_t* buf, size_t len) {
  size_t total = 0;
  while (total < len) {
    int n = recv(s, reinterpret_cast<char*>(buf + total),
                 static_cast<int>(len - total), 0);
    if (n <= 0) return false;
    total += static_cast<size_t>(n);
  }
  return true;
}

std::string FormatBthAddress(ULONGLONG addr) {
  char buf[32] = {0};
  std::snprintf(buf, sizeof(buf), "%02X:%02X:%02X:%02X:%02X:%02X",
                static_cast<unsigned>((addr >> 40) & 0xFF),
                static_cast<unsigned>((addr >> 32) & 0xFF),
                static_cast<unsigned>((addr >> 24) & 0xFF),
                static_cast<unsigned>((addr >> 16) & 0xFF),
                static_cast<unsigned>((addr >> 8) & 0xFF),
                static_cast<unsigned>(addr & 0xFF));
  return std::string(buf);
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_bt_channel;

class WindowsBluetoothServer {
 public:
  explicit WindowsBluetoothServer(HWND host_window)
      : host_window_(host_window) {}

  ~WindowsBluetoothServer() { Stop(); }

  bool Start(std::string& out_addr, std::string& out_msg) {
    if (running_.load()) {
      out_addr = local_addr_;
      out_msg = "Bluetooth RFCOMM server already running";
      return true;
    }

    WSADATA wsa_data = {};
    if (WSAStartup(MAKEWORD(2, 2), &wsa_data) != 0) {
      out_msg = "WSAStartup failed";
      return false;
    }
    wsa_started_ = true;

    BLUETOOTH_FIND_RADIO_PARAMS find_params = {sizeof(find_params)};
    HANDLE radio_handle = nullptr;
    HBLUETOOTH_RADIO_FIND hFind =
        BluetoothFindFirstRadio(&find_params, &radio_handle);
    if (hFind) {
      BLUETOOTH_RADIO_INFO info = {};
      info.dwSize = sizeof(info);
      if (BluetoothGetRadioInfo(radio_handle, &info) == ERROR_SUCCESS) {
        local_addr_ = FormatBthAddress(info.address.ullLong);
        out_addr = local_addr_;
      }
      CloseHandle(radio_handle);
      BluetoothFindRadioClose(hFind);
    }

    server_socket_ = socket(AF_BTH, SOCK_STREAM, BTHPROTO_RFCOMM);
    if (server_socket_ == INVALID_SOCKET) {
      out_msg = "No Bluetooth adapter available on Windows";
      return false;
    }

    SOCKADDR_BTH addr = {};
    addr.addressFamily = AF_BTH;
    addr.btAddr = 0;
    addr.port = BT_PORT_ANY;

    if (bind(server_socket_, reinterpret_cast<SOCKADDR*>(&addr),
             sizeof(addr)) == SOCKET_ERROR) {
      closesocket(server_socket_);
      server_socket_ = INVALID_SOCKET;
      out_msg = "Failed to bind Bluetooth RFCOMM socket";
      return false;
    }

    int addr_len = sizeof(addr);
    getsockname(server_socket_, reinterpret_cast<SOCKADDR*>(&addr), &addr_len);

    if (listen(server_socket_, 4) == SOCKET_ERROR) {
      closesocket(server_socket_);
      server_socket_ = INVALID_SOCKET;
      out_msg = "Failed to listen on Bluetooth RFCOMM socket";
      return false;
    }

    bound_addr_ = addr;
    RegisterSdp(true);

    running_.store(true);
    accept_thread_ = std::thread([this]() { AcceptLoop(); });
    out_msg = "Listening on Windows Bluetooth RFCOMM port " +
              std::to_string(addr.port);
    return true;
  }

  void Stop() {
    running_.store(false);
    if (sdp_registered_) {
      RegisterSdp(false);
    }
    if (server_socket_ != INVALID_SOCKET) {
      closesocket(server_socket_);
      server_socket_ = INVALID_SOCKET;
    }
    if (accept_thread_.joinable()) {
      accept_thread_.join();
    }
    if (wsa_started_) {
      WSACleanup();
      wsa_started_ = false;
    }
  }

 private:
  void RegisterSdp(bool register_service) {
    CSADDR_INFO cs_addr = {};
    cs_addr.LocalAddr.lpSockaddr = reinterpret_cast<SOCKADDR*>(&bound_addr_);
    cs_addr.LocalAddr.iSockaddrLength = sizeof(bound_addr_);
    cs_addr.iSocketType = SOCK_STREAM;
    cs_addr.iProtocol = BTHPROTO_RFCOMM;

    wchar_t svc_name[] = L"OtpBridge Secure Link";
    wchar_t svc_desc[] = L"Encrypted Offline OTP Bridge";
    GUID svc_guid = kOtpBridgeServiceGuid;

    WSAQUERYSETW qset = {};
    qset.dwSize = sizeof(qset);
    qset.lpszServiceInstanceName = svc_name;
    qset.lpServiceClassId = &svc_guid;
    qset.lpszComment = svc_desc;
    qset.dwNameSpace = NS_BTH;
    qset.dwNumberOfCsAddrs = 1;
    qset.lpcsaBuffer = &cs_addr;

    if (register_service) {
      sdp_registered_ = (WSASetServiceW(&qset, RNRSERVICE_REGISTER, 0) == 0);
    } else {
      WSASetServiceW(&qset, RNRSERVICE_DELETE, 0);
      sdp_registered_ = false;
    }
  }

  void AcceptLoop() {
    while (running_.load()) {
      SOCKADDR_BTH rem = {};
      int rem_len = sizeof(rem);
      SOCKET client = accept(server_socket_, reinterpret_cast<SOCKADDR*>(&rem),
                             &rem_len);
      if (client == INVALID_SOCKET) {
        if (!running_.load()) break;
        continue;
      }

      DWORD timeout_ms = 4000;
      setsockopt(client, SOL_SOCKET, SO_RCVTIMEO,
                 reinterpret_cast<const char*>(&timeout_ms),
                 sizeof(timeout_ms));
      setsockopt(client, SOL_SOCKET, SO_SNDTIMEO,
                 reinterpret_cast<const char*>(&timeout_ms),
                 sizeof(timeout_ms));

      uint8_t len_buf[4];
      if (RecvExact(client, len_buf, 4)) {
        uint32_t frame_len = (static_cast<uint32_t>(len_buf[0]) << 24) |
                             (static_cast<uint32_t>(len_buf[1]) << 16) |
                             (static_cast<uint32_t>(len_buf[2]) << 8) |
                             static_cast<uint32_t>(len_buf[3]);
        if (frame_len > 0 && frame_len <= 65536) {
          std::vector<uint8_t> payload(frame_len);
          if (RecvExact(client, payload.data(), frame_len)) {
            auto promise =
                std::make_shared<std::promise<std::vector<uint8_t>>>();
            auto future = promise->get_future();

            auto* task = new WinBtFrameTask{std::move(payload), promise};
            if (!PostMessageW(host_window_, kWmOtpBridgeBtFrame, 0,
                              reinterpret_cast<LPARAM>(task))) {
              delete task;
            } else if (future.wait_for(std::chrono::seconds(3)) ==
                       std::future_status::ready) {
              auto reply = future.get();
              if (!reply.empty() && reply.size() <= 65536) {
                uint32_t net_len = htonl(static_cast<uint32_t>(reply.size()));
                send(client, reinterpret_cast<const char*>(&net_len), 4, 0);
                send(client, reinterpret_cast<const char*>(reply.data()),
                     static_cast<int>(reply.size()), 0);
              }
            }
          }
        }
      }
      closesocket(client);
    }
  }

  HWND host_window_;
  SOCKET server_socket_ = INVALID_SOCKET;
  SOCKADDR_BTH bound_addr_ = {};
  bool sdp_registered_ = false;
  bool wsa_started_ = false;
  std::atomic<bool> running_{false};
  std::thread accept_thread_;
  std::string local_addr_;
};

std::unique_ptr<WindowsBluetoothServer> g_bt_server;

}  // namespace

void HandleWindowsBluetoothFrameMessage(LPARAM lparam) {
  std::unique_ptr<WinBtFrameTask> task(
      reinterpret_cast<WinBtFrameTask*>(lparam));
  if (!task) return;
  if (!g_bt_channel) {
    task->reply_promise->set_value({});
    return;
  }

  auto promise = task->reply_promise;
  auto result_handler = std::make_unique<
      flutter::MethodResultFunctions<flutter::EncodableValue>>(
      [promise](const flutter::EncodableValue* success_value) {
        std::vector<uint8_t> reply;
        if (success_value) {
          if (const auto* bytes =
                  std::get_if<std::vector<uint8_t>>(success_value)) {
            reply = *bytes;
          }
        }
        promise->set_value(std::move(reply));
      },
      [promise](const std::string&, const std::string&,
                const flutter::EncodableValue*) { promise->set_value({}); },
      [promise]() { promise->set_value({}); });

  g_bt_channel->InvokeMethod(
      "onFrame",
      std::make_unique<flutter::EncodableValue>(std::move(task->payload)),
      std::move(result_handler));
}

void RegisterWindowsBluetoothChannel(flutter::BinaryMessenger* messenger,
                                     HWND host_window) {
  g_bt_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "dev.otpbridge/bluetooth",
          &flutter::StandardMethodCodec::GetInstance());

  g_bt_server = std::make_unique<WindowsBluetoothServer>(host_window);

  g_bt_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "startServer") {
          std::string addr;
          std::string msg;
          bool ok = g_bt_server->Start(addr, msg);
          flutter::EncodableMap map;
          map[flutter::EncodableValue("supported")] =
              flutter::EncodableValue(ok);
          map[flutter::EncodableValue("running")] =
              flutter::EncodableValue(ok);
          if (!addr.empty()) {
            map[flutter::EncodableValue("address")] =
                flutter::EncodableValue(addr);
          }
          map[flutter::EncodableValue("message")] =
              flutter::EncodableValue(msg);
          result->Success(flutter::EncodableValue(map));
        } else if (call.method_name() == "stopServer") {
          g_bt_server->Stop();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

void ShutdownWindowsBluetoothServer() {
  if (g_bt_server) {
    g_bt_server->Stop();
    g_bt_server.reset();
  }
  g_bt_channel.reset();
}
