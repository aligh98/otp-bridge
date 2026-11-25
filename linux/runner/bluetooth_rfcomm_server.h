#ifndef LINUX_RUNNER_BLUETOOTH_RFCOMM_SERVER_H_
#define LINUX_RUNNER_BLUETOOTH_RFCOMM_SERVER_H_

#include <flutter_linux/flutter_linux.h>

void otpbridge_register_linux_bluetooth_channel(FlPluginRegistrar* registrar);
void otpbridge_shutdown_linux_bluetooth_channel();

#endif  // LINUX_RUNNER_BLUETOOTH_RFCOMM_SERVER_H_
