#ifndef FLUTTER_PLUGIN_SYSTEM_AUDIO_METER_PLUGIN_H_
#define FLUTTER_PLUGIN_SYSTEM_AUDIO_METER_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <mmdeviceapi.h>

#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace system_audio_meter {

class DeviceNotificationClient;

struct AudioDeviceInfo {
  std::string id;
  std::string name;
  bool is_default = false;
};

struct SilenceDetectionState {
  bool enabled = false;
  bool is_silent = false;
  double threshold = 0.0;
  std::chrono::milliseconds duration{0};
  std::chrono::steady_clock::time_point candidate_started_at{};
  bool has_candidate = false;
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
  friend class DeviceNotificationClient;

  std::vector<AudioDeviceInfo> EnumerateDevices(
      EDataFlow flow, std::string* default_device_id = nullptr) const;
  bool ResolveRequestedDevice(EDataFlow flow, const std::string& selected_device_id,
                              const std::string& selected_device_name,
                              IMMDeviceEnumerator* enumerator,
                              IMMDevice** device,
                              AudioDeviceInfo* device_info) const;
  bool ResolveCurrentDevice(EDataFlow flow, AudioDeviceInfo* device_info) const;
  flutter::EncodableValue EncodeDevice(
      const AudioDeviceInfo& device_info) const;

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnOutputListen(
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events);
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnOutputCancel();
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnInputListen(
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events);
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnInputCancel();

  void SyncCaptureState(EDataFlow flow, bool force_restart = false);
  void CaptureLoop(EDataFlow flow, std::string selected_device_id);
  void EmitLevels(EDataFlow flow, double left_peak, double right_peak,
                  const std::string& device_id, const std::string& device_name);
  void EmitDeviceEvent(EDataFlow flow, const std::string& kind,
                       const std::string& device_id,
                       const std::string& device_name, bool is_default,
                       bool is_selected);
  void ProcessSilenceDetection(EDataFlow flow, double peak_level,
                               std::chrono::steady_clock::time_point now,
                               const std::string& device_id,
                               const std::string& device_name);
  void ResetSilenceDetectionState(EDataFlow flow, bool preserve_configuration);
  void EmitError(EDataFlow flow, const std::string& code,
                 const std::string& message);
  void ClearCurrentDevice(EDataFlow flow);
  void RegisterDeviceNotifications();
  void UnregisterDeviceNotifications();
  void RefreshDevices(EDataFlow flow, bool default_device_changed);
  void HandleDeviceNotification(EDataFlow flow, const std::string* device_id,
                                bool default_device_changed);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      output_event_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      input_event_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      device_event_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      silence_event_channel_;

  mutable std::mutex state_mutex_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> output_event_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> input_event_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> device_event_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> silence_event_sink_;
  std::thread output_capture_thread_;
  std::thread input_capture_thread_;
  IMMDeviceEnumerator* notification_enumerator_ = nullptr;
  IMMNotificationClient* notification_client_ = nullptr;
  std::atomic<bool> output_stop_requested_{false};
  std::atomic<bool> input_stop_requested_{false};
  std::atomic<bool> output_capture_active_{false};
  std::atomic<bool> input_capture_active_{false};

  bool output_listener_active_ = false;
  bool input_listener_active_ = false;
  bool silence_listener_active_ = false;
  bool output_requested_running_ = false;
  bool input_requested_running_ = false;
  std::string selected_output_device_id_;
  std::string selected_input_device_id_;
  std::string selected_output_device_name_;
  std::string selected_input_device_name_;
  std::string current_output_device_id_;
  std::string current_input_device_id_;
  std::string current_output_device_name_;
  std::string current_input_device_name_;
  bool current_output_device_is_default_ = false;
  bool current_input_device_is_default_ = false;
  std::unordered_map<std::string, AudioDeviceInfo> known_output_devices_;
  std::unordered_map<std::string, AudioDeviceInfo> known_input_devices_;
  SilenceDetectionState output_silence_detection_state_;
  SilenceDetectionState input_silence_detection_state_;
};

}  // namespace system_audio_meter

#endif  // FLUTTER_PLUGIN_SYSTEM_AUDIO_METER_PLUGIN_H_
