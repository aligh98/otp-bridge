#include "clipboard_privacy.h"

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstring>
#include <memory>
#include <string>

namespace {

bool SetPrivateClipboardText(const std::string& utf8_text) {
  int wide_len =
      MultiByteToWideChar(CP_UTF8, 0, utf8_text.c_str(), -1, nullptr, 0);
  if (wide_len <= 0) return false;

  if (!OpenClipboard(nullptr)) return false;
  EmptyClipboard();

  HGLOBAL hMem =
      GlobalAlloc(GMEM_MOVEABLE, static_cast<size_t>(wide_len) * sizeof(wchar_t));
  if (!hMem) {
    CloseClipboard();
    return false;
  }

  wchar_t* dst = static_cast<wchar_t*>(GlobalLock(hMem));
  if (dst) {
    MultiByteToWideChar(CP_UTF8, 0, utf8_text.c_str(), -1, dst, wide_len);
    GlobalUnlock(hMem);
  }
  if (!SetClipboardData(CF_UNICODETEXT, hMem)) {
    GlobalFree(hMem);
    CloseClipboard();
    return false;
  }

  // Official Windows 10/11 Clipboard Privacy Formats:
  // Prevent OTP from appearing in Win+V Clipboard History and Cloud Sync.
  const wchar_t* privacy_formats[] = {
      L"ExcludeClipboardContentFromMonitorProcessing",
      L"CanIncludeInClipboardHistory",
      L"CanUploadToCloudClipboard",
  };
  for (const wchar_t* fmt_name : privacy_formats) {
    UINT fmt = RegisterClipboardFormatW(fmt_name);
    if (fmt != 0) {
      HGLOBAL hFlag = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
      if (hFlag) {
        DWORD* val = static_cast<DWORD*>(GlobalLock(hFlag));
        if (val) {
          *val = 0;
          GlobalUnlock(hFlag);
        }
        if (!SetClipboardData(fmt, hFlag)) {
          GlobalFree(hFlag);
        }
      }
    }
  }

  CloseClipboard();
  return true;
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_clip_channel;

}  // namespace

void RegisterWindowsPrivateClipboardChannel(
    flutter::BinaryMessenger* messenger) {
  g_clip_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "dev.otpbridge/clipboard",
          &flutter::StandardMethodCodec::GetInstance());

  g_clip_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "setPrivateClipboard") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            auto it = args->find(flutter::EncodableValue("text"));
            if (it != args->end()) {
              if (const auto* text = std::get_if<std::string>(&it->second)) {
                bool ok = SetPrivateClipboardText(*text);
                result->Success(flutter::EncodableValue(ok));
                return;
              }
            }
          }
          result->Success(flutter::EncodableValue(false));
          return;
        }
        result->NotImplemented();
      });
}
