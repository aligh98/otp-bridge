#include "bluetooth_rfcomm_server.h"

#include <arpa/inet.h>
#include <bluetooth/bluetooth.h>
#include <bluetooth/hci.h>
#include <bluetooth/hci_lib.h>
#include <bluetooth/rfcomm.h>
#include <bluetooth/sdp.h>
#include <bluetooth/sdp_lib.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <future>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace {

// Custom SPP UUID in network byte order (big-endian):
// 8a7c4b2e-91f3-4d6a-b5e1-2c8f9a0d3e41
static const uint8_t kServiceUuidBytes[16] = {
    0x8a, 0x7c, 0x4b, 0x2e,
    0x91, 0xf3,
    0x4d, 0x6a,
    0xb5, 0xe1,
    0x2c, 0x8f, 0x9a, 0x0d, 0x3e, 0x41,
};

struct FrameDispatchContext {
  FlMethodChannel* channel;  // Holds owned g_object_ref
  std::vector<uint8_t> frame;
  std::shared_ptr<std::promise<std::vector<uint8_t>>> reply_promise;
};

static void on_dart_frame_reply(GObject* source_object,
                                GAsyncResult* res,
                                gpointer user_data) {
  auto* ctx = static_cast<FrameDispatchContext*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response =
      fl_method_channel_invoke_method_finish(
          FL_METHOD_CHANNEL(source_object), res, &error);

  std::vector<uint8_t> reply_bytes;
  if (response != nullptr && error == nullptr) {
    g_autoptr(GError) resp_err = nullptr;
    FlValue* val = fl_method_response_get_result(response, &resp_err);
    if (val != nullptr && fl_value_get_type(val) == FL_VALUE_TYPE_UINT8_LIST) {
      const uint8_t* ptr = fl_value_get_uint8_list(val);
      size_t len = fl_value_get_length(val);
      reply_bytes.assign(ptr, ptr + len);
    }
  }
  ctx->reply_promise->set_value(std::move(reply_bytes));
  g_object_unref(ctx->channel);
  delete ctx;
}

static gboolean dispatch_frame_on_main_thread(gpointer user_data) {
  auto* ctx = static_cast<FrameDispatchContext*>(user_data);
  g_autoptr(FlValue) arg =
      fl_value_new_uint8_list(ctx->frame.data(), ctx->frame.size());
  fl_method_channel_invoke_method(ctx->channel, "onFrame", arg, nullptr,
                                  on_dart_frame_reply, ctx);
  return G_SOURCE_REMOVE;
}

static bool read_exact(int fd, uint8_t* buf, size_t len) {
  size_t total = 0;
  while (total < len) {
    ssize_t n = read(fd, buf + total, len - total);
    if (n <= 0) return false;
    total += static_cast<size_t>(n);
  }
  return true;
}

class LinuxBluetoothServer {
 public:
  explicit LinuxBluetoothServer(FlMethodChannel* channel)
      : channel_(FL_METHOD_CHANNEL(g_object_ref(channel))) {}

  ~LinuxBluetoothServer() {
    Stop();
    if (channel_ != nullptr) {
      g_object_unref(channel_);
      channel_ = nullptr;
    }
  }

  bool Start(std::string& out_addr, std::string& out_msg) {
    if (running_.load()) {
      out_addr = local_addr_;
      out_msg = "Bluetooth RFCOMM server already running";
      return true;
    }

    int dev_id = hci_get_route(nullptr);
    if (dev_id < 0) {
      out_msg = "No Bluetooth adapter detected on this Linux system";
      return false;
    }

    bdaddr_t bdaddr;
    if (hci_devba(dev_id, &bdaddr) == 0) {
      char addr_str[18] = {0};
      ba2str(&bdaddr, addr_str);
      local_addr_ = addr_str;
      out_addr = local_addr_;
    }

    server_fd_ = socket(AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM);
    if (server_fd_ < 0) {
      out_msg = "Failed to create AF_BLUETOOTH RFCOMM socket";
      return false;
    }

    sockaddr_rc loc_addr = {};
    loc_addr.rc_family = AF_BLUETOOTH;
    bdaddr_t any_addr = {{0, 0, 0, 0, 0, 0}};
    loc_addr.rc_bdaddr = any_addr;
    loc_addr.rc_channel = 0;

    if (bind(server_fd_, reinterpret_cast<sockaddr*>(&loc_addr),
             sizeof(loc_addr)) < 0) {
      close(server_fd_);
      server_fd_ = -1;
      out_msg = "Failed to bind Bluetooth RFCOMM socket";
      return false;
    }

    socklen_t optlen = sizeof(loc_addr);
    getsockname(server_fd_, reinterpret_cast<sockaddr*>(&loc_addr), &optlen);
    uint8_t bound_channel = loc_addr.rc_channel;

    if (listen(server_fd_, 4) < 0) {
      close(server_fd_);
      server_fd_ = -1;
      out_msg = "Failed to listen on Bluetooth RFCOMM socket";
      return false;
    }

    RegisterSdp(bound_channel);
    running_.store(true);
    accept_thread_ = std::thread([this]() { AcceptLoop(); });
    out_msg = "Listening on BlueZ RFCOMM channel " +
              std::to_string(bound_channel);
    return true;
  }

  void Stop() {
    running_.store(false);
    if (server_fd_ >= 0) {
      shutdown(server_fd_, SHUT_RDWR);
      close(server_fd_);
      server_fd_ = -1;
    }
    if (accept_thread_.joinable()) {
      accept_thread_.join();
    }
    if (sdp_session_ != nullptr) {
      sdp_close(sdp_session_);
      sdp_session_ = nullptr;
    }
  }

 private:
  void RegisterSdp(uint8_t rfcomm_channel) {
    bdaddr_t any_addr = {{0, 0, 0, 0, 0, 0}};
    bdaddr_t local_addr = {{0, 0, 0, 0xff, 0xff, 0xff}};
    sdp_session_ = sdp_connect(&any_addr, &local_addr, SDP_RETRY_IF_BUSY);
    if (!sdp_session_) return;

    uuid_t root_uuid, l2cap_uuid, rfcomm_uuid, svc_uuid;
    sdp_record_t* record = sdp_record_alloc();
    if (!record) return;

    sdp_uuid128_create(&svc_uuid, kServiceUuidBytes);
    sdp_set_service_id(record, svc_uuid);
    sdp_list_t* svc_class_list = sdp_list_append(nullptr, &svc_uuid);
    sdp_set_service_classes(record, svc_class_list);

    sdp_uuid16_create(&root_uuid, PUBLIC_BROWSE_GROUP);
    sdp_list_t* root_list = sdp_list_append(nullptr, &root_uuid);
    sdp_set_browse_groups(record, root_list);

    sdp_uuid16_create(&l2cap_uuid, L2CAP_UUID);
    sdp_list_t* l2cap_list = sdp_list_append(nullptr, &l2cap_uuid);
    sdp_list_t* proto_list = sdp_list_append(nullptr, l2cap_list);

    sdp_uuid16_create(&rfcomm_uuid, RFCOMM_UUID);
    sdp_data_t* channel_data = sdp_data_alloc(SDP_UINT8, &rfcomm_channel);
    sdp_list_t* rfcomm_list = sdp_list_append(nullptr, &rfcomm_uuid);
    sdp_list_append(rfcomm_list, channel_data);
    sdp_list_append(proto_list, rfcomm_list);

    sdp_list_t* access_proto_list = sdp_list_append(nullptr, proto_list);
    sdp_set_access_protos(record, access_proto_list);
    sdp_set_info_attr(record, "OtpBridge Secure Link", "OtpBridge",
                      "Encrypted Offline OTP Bridge");

    sdp_record_register(sdp_session_, record, 0);

    sdp_data_free(channel_data);
    sdp_list_free(l2cap_list, nullptr);
    sdp_list_free(rfcomm_list, nullptr);
    sdp_list_free(proto_list, nullptr);
    sdp_list_free(access_proto_list, nullptr);
    sdp_list_free(root_list, nullptr);
    sdp_list_free(svc_class_list, nullptr);
    sdp_record_free(record);
  }

  void AcceptLoop() {
    while (running_.load()) {
      sockaddr_rc rem_addr = {};
      socklen_t opt = sizeof(rem_addr);
      int client_fd =
          accept(server_fd_, reinterpret_cast<sockaddr*>(&rem_addr), &opt);
      if (client_fd < 0) {
        if (!running_.load()) break;
        continue;
      }

      // Guard against stalled clients blocking AcceptLoop
      struct timeval tv;
      tv.tv_sec = 4;
      tv.tv_usec = 0;
      setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
      setsockopt(client_fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

      uint8_t len_buf[4];
      if (read_exact(client_fd, len_buf, 4)) {
        uint32_t frame_len = (static_cast<uint32_t>(len_buf[0]) << 24) |
                             (static_cast<uint32_t>(len_buf[1]) << 16) |
                             (static_cast<uint32_t>(len_buf[2]) << 8) |
                             static_cast<uint32_t>(len_buf[3]);
        if (frame_len > 0 && frame_len <= 65536) {
          std::vector<uint8_t> payload(frame_len);
          if (read_exact(client_fd, payload.data(), frame_len)) {
            auto promise =
                std::make_shared<std::promise<std::vector<uint8_t>>>();
            auto future = promise->get_future();

            auto* ctx = new FrameDispatchContext{
                FL_METHOD_CHANNEL(g_object_ref(channel_)),
                std::move(payload),
                promise,
            };
            g_idle_add(dispatch_frame_on_main_thread, ctx);

            if (future.wait_for(std::chrono::seconds(3)) ==
                std::future_status::ready) {
              auto reply = future.get();
              if (!reply.empty() && reply.size() <= 65536) {
                uint32_t net_len = htonl(static_cast<uint32_t>(reply.size()));
                ssize_t w1 = write(client_fd, &net_len, 4);
                ssize_t w2 = write(client_fd, reply.data(), reply.size());
                (void)w1;
                (void)w2;
              }
            }
          }
        }
      }
      close(client_fd);
    }
  }

  FlMethodChannel* channel_;
  int server_fd_ = -1;
  sdp_session_t* sdp_session_ = nullptr;
  std::atomic<bool> running_{false};
  std::thread accept_thread_;
  std::string local_addr_;
};

static std::unique_ptr<LinuxBluetoothServer> g_bt_server;

static void bt_method_call_cb(FlMethodChannel* channel,
                              FlMethodCall* method_call,
                              gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "startServer") == 0) {
    if (!g_bt_server) {
      g_bt_server = std::make_unique<LinuxBluetoothServer>(channel);
    }
    std::string addr;
    std::string msg;
    bool ok = g_bt_server->Start(addr, msg);
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "supported", fl_value_new_bool(ok));
    fl_value_set_string_take(map, "running", fl_value_new_bool(ok));
    if (!addr.empty()) {
      fl_value_set_string_take(map, "address",
                               fl_value_new_string(addr.c_str()));
    }
    fl_value_set_string_take(map, "message", fl_value_new_string(msg.c_str()));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  } else if (strcmp(method, "stopServer") == 0) {
    if (g_bt_server) {
      g_bt_server->Stop();
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

}  // namespace

void otpbridge_register_linux_bluetooth_channel(FlPluginRegistrar* registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "dev.otpbridge/bluetooth",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, bt_method_call_cb,
                                            nullptr, nullptr);
}

void otpbridge_shutdown_linux_bluetooth_channel() {
  if (g_bt_server) {
    g_bt_server->Stop();
    g_bt_server.reset();
  }
}
