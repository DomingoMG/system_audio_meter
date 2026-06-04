#include "include/system_audio_meter/system_audio_meter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "system_audio_meter_plugin.h"

void SystemAudioMeterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  system_audio_meter::SystemAudioMeterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
