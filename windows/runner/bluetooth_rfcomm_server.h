#ifndef WINDOWS_RUNNER_BLUETOOTH_RFCOMM_SERVER_H_
#define WINDOWS_RUNNER_BLUETOOTH_RFCOMM_SERVER_H_

#include <windows.h>

#include <flutter/binary_messenger.h>

constexpr UINT kWmOtpBridgeBtFrame = WM_APP + 101;

void RegisterWindowsBluetoothChannel(flutter::BinaryMessenger* messenger,
                                     HWND host_window);
void HandleWindowsBluetoothFrameMessage(LPARAM lparam);
void ShutdownWindowsBluetoothServer();

#endif  // WINDOWS_RUNNER_BLUETOOTH_RFCOMM_SERVER_H_
