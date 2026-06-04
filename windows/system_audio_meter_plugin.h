#ifndef FLUTTER_PLUGIN_SYSTEM_AUDIO_METER_PLUGIN_H_
#define FLUTTER_PLUGIN_SYSTEM_AUDIO_METER_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace system_audio_meter {

struct AudioOutputDeviceInfo {
  std::string id;
  std::string name;
  bool is_default = false;
};

class SystemAudioMeterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit SystemAudioMeterPlugin(flutter::PluginRegistrarWindows* registrar);
  ~SystemAudioMeterPlugin() override;

  SystemAudioMeterPlugin(const SystemAudioMeterPlugin&) = delete;
  SystemAudioMeterPlugin& operator=(const SystemAudioMeterPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  std::vector<AudioOutputDeviceInfo> EnumerateOutputDevices(
      std::string* default_device_id = nullptr) const;
  bool ResolveCurrentOutputDevice(AudioOutputDeviceInfo* device_info) const;
  flutter::EncodableValue EncodeDevice(
      const AudioOutputDeviceInfo& device_info) const;

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListen(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events);
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancel();

  void SyncCaptureState(bool force_restart = false);
  void CaptureLoop(std::string selected_device_id);
  void EmitLevels(double left_peak, double right_peak,
                  const std::string& output_device_id,
                  const std::string& output_device_name);
  void EmitError(const std::string& code, const std::string& message);
  void ClearCurrentDevice();

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;

  mutable std::mutex state_mutex_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  std::thread capture_thread_;
  std::atomic<bool> stop_requested_{false};
  std::atomic<bool> capture_active_{false};

  bool listener_active_ = false;
  bool requested_running_ = false;
  std::string selected_device_id_;
  std::string current_device_id_;
  std::string current_device_name_;
  bool current_device_is_default_ = false;
};

}  // namespace system_audio_meter

#endif  // FLUTTER_PLUGIN_SYSTEM_AUDIO_METER_PLUGIN_H_
