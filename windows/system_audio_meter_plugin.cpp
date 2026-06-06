#include "system_audio_meter_plugin.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <ksmedia.h>
#include <mmdeviceapi.h>
#include <propkey.h>
#include <propvarutil.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

namespace system_audio_meter {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

constexpr char kMethodChannelName[] = "system_audio_meter";
constexpr char kOutputEventChannelName[] = "system_audio_meter/levels";
constexpr char kInputEventChannelName[] = "system_audio_meter/input_levels";
constexpr char kDeviceEventChannelName[] = "system_audio_meter/device_events";
constexpr char kSilenceEventChannelName[] = "system_audio_meter/silence_events";
constexpr REFERENCE_TIME kRequestedBufferDuration = 200000;
constexpr auto kEmitInterval = std::chrono::milliseconds(33);

class ScopedCoInitialize {
 public:
  explicit ScopedCoInitialize(DWORD flags) : result_(CoInitializeEx(nullptr, flags)) {}
  ~ScopedCoInitialize() {
    if (SUCCEEDED(result_)) {
      CoUninitialize();
    }
  }

  HRESULT result() const { return result_; }

 private:
  HRESULT result_;
};

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int length = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr,
                                         0, nullptr, nullptr);
  if (length <= 1) {
    return std::string();
  }
  std::string result(length, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, result.data(), length,
                      nullptr, nullptr);
  result.pop_back();
  return result;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (length <= 1) {
    return std::wstring();
  }
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), length);
  result.pop_back();
  return result;
}

std::string ReadFriendlyName(IMMDevice* device, EDataFlow flow) {
  ComPtr<IPropertyStore> property_store;
  const char* unknown_name =
      flow == eCapture ? "Unknown input device" : "Unknown output device";
  if (FAILED(device->OpenPropertyStore(STGM_READ, &property_store))) {
    return unknown_name;
  }

  PROPVARIANT variant;
  PropVariantInit(&variant);
  std::string name = unknown_name;
  if (SUCCEEDED(property_store->GetValue(PKEY_Device_FriendlyName, &variant)) &&
      variant.vt == VT_LPWSTR && variant.pwszVal != nullptr) {
    name = WideToUtf8(variant.pwszVal);
  }
  PropVariantClear(&variant);
  return name;
}

std::string ReadDeviceId(IMMDevice* device) {
  LPWSTR wide_id = nullptr;
  if (FAILED(device->GetId(&wide_id)) || wide_id == nullptr) {
    return std::string();
  }
  std::wstring copy(wide_id);
  CoTaskMemFree(wide_id);
  return WideToUtf8(copy);
}

double ClampPeak(double value) {
  if (std::isnan(value) || !std::isfinite(value)) {
    return 0.0;
  }
  return std::clamp(value, 0.0, 1.0);
}

bool IsFloatFormat(const WAVEFORMATEX* format) {
  if (format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) {
    return true;
  }
  if (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
    const auto* extensible =
        reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format);
    return extensible->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
  }
  return false;
}

bool IsPcmFormat(const WAVEFORMATEX* format) {
  if (format->wFormatTag == WAVE_FORMAT_PCM) {
    return true;
  }
  if (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
    const auto* extensible =
        reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format);
    return extensible->SubFormat == KSDATAFORMAT_SUBTYPE_PCM;
  }
  return false;
}

double ReadFloatSample(const BYTE* sample, WORD bits_per_sample) {
  if (bits_per_sample == 32) {
    const float value = *reinterpret_cast<const float*>(sample);
    return std::fabs(static_cast<double>(value));
  }
  if (bits_per_sample == 64) {
    const double value = *reinterpret_cast<const double*>(sample);
    return std::fabs(value);
  }
  return 0.0;
}

double ReadPcmSample(const BYTE* sample, WORD bits_per_sample) {
  switch (bits_per_sample) {
    case 8: {
      const auto value = static_cast<int>(*sample) - 128;
      return std::fabs(static_cast<double>(value) / 128.0);
    }
    case 16: {
      const auto value = *reinterpret_cast<const int16_t*>(sample);
      return std::fabs(static_cast<double>(value) / 32768.0);
    }
    case 24: {
      int32_t value =
          sample[0] | (static_cast<int32_t>(sample[1]) << 8) |
          (static_cast<int32_t>(sample[2]) << 16);
      if ((value & 0x00800000) != 0) {
        value |= ~0x00FFFFFF;
      }
      return std::fabs(static_cast<double>(value) / 8388608.0);
    }
    case 32: {
      const auto value = *reinterpret_cast<const int32_t*>(sample);
      return std::fabs(static_cast<double>(value) / 2147483648.0);
    }
    default:
      return 0.0;
  }
}

void ProcessAudioPacket(const BYTE* data, UINT32 num_frames, DWORD flags,
                        const WAVEFORMATEX* format, double* left_peak,
                        double* right_peak) {
  *left_peak = 0.0;
  *right_peak = 0.0;

  const WORD channels = format->nChannels;
  const WORD bits_per_sample = format->wBitsPerSample;
  if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0 || data == nullptr ||
      channels == 0 || bits_per_sample == 0) {
    return;
  }

  const UINT32 bytes_per_frame = format->nBlockAlign;
  const UINT32 bytes_per_channel = bits_per_sample / 8;
  if (bytes_per_frame == 0 || bytes_per_channel == 0) {
    return;
  }

  const bool is_float = IsFloatFormat(format);
  const bool is_pcm = IsPcmFormat(format);
  if (!is_float && !is_pcm) {
    return;
  }

  for (UINT32 frame = 0; frame < num_frames; ++frame) {
    const BYTE* frame_data = data + frame * bytes_per_frame;
    const BYTE* left_ptr = frame_data;
    const double left_value =
        is_float ? ReadFloatSample(left_ptr, bits_per_sample)
                 : ReadPcmSample(left_ptr, bits_per_sample);
    *left_peak = (std::max)(*left_peak, left_value);

    double right_value = left_value;
    if (channels > 1) {
      const BYTE* right_ptr = frame_data + bytes_per_channel;
      right_value =
          is_float ? ReadFloatSample(right_ptr, bits_per_sample)
                   : ReadPcmSample(right_ptr, bits_per_sample);
    }
    *right_peak = (std::max)(*right_peak, right_value);
  }

  *left_peak = ClampPeak(*left_peak);
  *right_peak = ClampPeak(*right_peak);
}

const char* UnknownDeviceName(EDataFlow flow) {
  return flow == eCapture ? "Unknown input device" : "Unknown output device";
}

const char* StartFailureCode(EDataFlow flow) {
  return flow == eCapture ? "audio_input_client_start_failed"
                          : "audio_client_start_failed";
}

const char* StartFailureMessage(EDataFlow flow) {
  return flow == eCapture ? "Failed to start WASAPI input capture."
                          : "Failed to start WASAPI loopback capture.";
}

const char* InitializeFailureCode(EDataFlow flow) {
  return flow == eCapture ? "input_initialize_failed"
                          : "loopback_initialize_failed";
}

const char* InitializeFailureMessage(EDataFlow flow) {
  return flow == eCapture
             ? "Failed to initialize WASAPI input capture for the selected input device."
             : "Failed to initialize WASAPI loopback capture for the selected output device.";
}

const char* MixFormatFailureMessage(EDataFlow flow) {
  return flow == eCapture ? "Failed to read the input device mix format."
                          : "Failed to read the output device mix format.";
}

const char* NoDeviceCode(EDataFlow flow) {
  return flow == eCapture ? "no_input_device" : "no_output_device";
}

const char* NoDeviceMessage(EDataFlow flow) {
  return flow == eCapture
             ? "No active Windows input device is available for metering."
             : "No active Windows render device is available for loopback metering.";
}

const char* CapturePacketMessage(EDataFlow flow) {
  return flow == eCapture
             ? "The input device became unavailable during capture."
             : "The output device became unavailable during loopback capture.";
}

const char* CaptureBufferMessage(EDataFlow flow) {
  return flow == eCapture
             ? "Failed to read the current WASAPI input buffer."
             : "Failed to read the current WASAPI loopback buffer.";
}

const char* CapturePollMessage(EDataFlow flow) {
  return flow == eCapture
             ? "Failed while polling the next WASAPI input packet."
             : "Failed while polling the next WASAPI loopback packet.";
}

void ClearDeviceInfo(AudioDeviceInfo* device_info) {
  if (device_info == nullptr) {
    return;
  }
  device_info->id.clear();
  device_info->name.clear();
  device_info->is_default = false;
}

}  // namespace

class DeviceNotificationClient : public IMMNotificationClient {
 public:
  explicit DeviceNotificationClient(SystemAudioMeterPlugin* plugin)
      : plugin_(plugin) {}

  ULONG STDMETHODCALLTYPE AddRef() override {
    return ++reference_count_;
  }

  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG count = --reference_count_;
    if (count == 0) {
      delete this;
    }
    return count;
  }

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** object) override {
    if (object == nullptr) {
      return E_POINTER;
    }
    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(IMMNotificationClient)) {
      *object = static_cast<IMMNotificationClient*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }

  HRESULT STDMETHODCALLTYPE OnDeviceStateChanged(LPCWSTR pwstrDeviceId,
                                                 DWORD dwNewState) override {
    if (plugin_ == nullptr) {
      return S_OK;
    }

    std::string device_id;
    if (pwstrDeviceId != nullptr) {
      device_id = WideToUtf8(pwstrDeviceId);
    }

    if ((dwNewState & DEVICE_STATE_ACTIVE) != 0) {
      plugin_->HandleDeviceNotification(eRender, &device_id, false);
      plugin_->HandleDeviceNotification(eCapture, &device_id, false);
      return S_OK;
    }

    plugin_->HandleDeviceNotification(eRender, &device_id, false);
    plugin_->HandleDeviceNotification(eCapture, &device_id, false);
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE OnDeviceAdded(LPCWSTR pwstrDeviceId) override {
    if (plugin_ == nullptr) {
      return S_OK;
    }
    std::string device_id;
    if (pwstrDeviceId != nullptr) {
      device_id = WideToUtf8(pwstrDeviceId);
    }
    plugin_->HandleDeviceNotification(eRender, &device_id, false);
    plugin_->HandleDeviceNotification(eCapture, &device_id, false);
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE OnDeviceRemoved(LPCWSTR pwstrDeviceId) override {
    if (plugin_ == nullptr) {
      return S_OK;
    }
    std::string device_id;
    if (pwstrDeviceId != nullptr) {
      device_id = WideToUtf8(pwstrDeviceId);
    }
    plugin_->HandleDeviceNotification(eRender, &device_id, false);
    plugin_->HandleDeviceNotification(eCapture, &device_id, false);
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE OnDefaultDeviceChanged(EDataFlow flow, ERole role,
                                                   LPCWSTR pwstrDefaultDeviceId) override {
    if (plugin_ == nullptr || role != eConsole) {
      return S_OK;
    }

    std::string device_id;
    if (pwstrDefaultDeviceId != nullptr) {
      device_id = WideToUtf8(pwstrDefaultDeviceId);
    }
    plugin_->HandleDeviceNotification(flow, &device_id, true);
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE OnPropertyValueChanged(LPCWSTR pwstrDeviceId,
                                                   const PROPERTYKEY key) override {
    return S_OK;
  }

 private:
  std::atomic<ULONG> reference_count_{1};
  SystemAudioMeterPlugin* plugin_;
};

void SystemAudioMeterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<SystemAudioMeterPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

SystemAudioMeterPlugin::SystemAudioMeterPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  method_channel_ =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar_->messenger(), kMethodChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  output_event_channel_ =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar_->messenger(), kOutputEventChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  input_event_channel_ =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar_->messenger(), kInputEventChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  device_event_channel_ =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar_->messenger(), kDeviceEventChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  silence_event_channel_ =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar_->messenger(), kSilenceEventChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  auto output_stream_handler =
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue* arguments,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            return OnOutputListen(std::move(events));
          },
          [this](const EncodableValue* arguments)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            return OnOutputCancel();
          });
  output_event_channel_->SetStreamHandler(std::move(output_stream_handler));

  auto input_stream_handler =
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue* arguments,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            return OnInputListen(std::move(events));
          },
          [this](const EncodableValue* arguments)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            return OnInputCancel();
          });
  input_event_channel_->SetStreamHandler(std::move(input_stream_handler));

  auto device_stream_handler =
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue* arguments,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            std::lock_guard<std::mutex> lock(state_mutex_);
            device_event_sink_ = std::move(events);
            return nullptr;
          },
          [this](const EncodableValue* arguments)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            std::lock_guard<std::mutex> lock(state_mutex_);
            device_event_sink_.reset();
            return nullptr;
          });
  device_event_channel_->SetStreamHandler(std::move(device_stream_handler));

  auto silence_stream_handler =
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue* arguments,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            {
              std::lock_guard<std::mutex> lock(state_mutex_);
              silence_event_sink_ = std::move(events);
              silence_listener_active_ = true;
            }
            SyncCaptureState(eRender);
            return nullptr;
          },
          [this](const EncodableValue* arguments)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            {
              std::lock_guard<std::mutex> lock(state_mutex_);
              silence_event_sink_.reset();
              silence_listener_active_ = false;
            }
            SyncCaptureState(eRender);
            return nullptr;
          });
  silence_event_channel_->SetStreamHandler(std::move(silence_stream_handler));

  RegisterDeviceNotifications();
}

SystemAudioMeterPlugin::~SystemAudioMeterPlugin() {
  UnregisterDeviceNotifications();
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    output_requested_running_ = false;
    input_requested_running_ = false;
    output_listener_active_ = false;
    input_listener_active_ = false;
    silence_listener_active_ = false;
    output_event_sink_.reset();
    input_event_sink_.reset();
    device_event_sink_.reset();
    silence_event_sink_.reset();
  }
  SyncCaptureState(eRender);
  SyncCaptureState(eCapture);
}

flutter::EncodableValue SystemAudioMeterPlugin::EncodeDevice(
    const AudioDeviceInfo& device_info) const {
  return EncodableMap{
      {EncodableValue("id"), EncodableValue(device_info.id)},
      {EncodableValue("name"), EncodableValue(device_info.name)},
      {EncodableValue("isDefault"), EncodableValue(device_info.is_default)},
  };
}

std::vector<AudioDeviceInfo> SystemAudioMeterPlugin::EnumerateDevices(
    EDataFlow flow, std::string* default_device_id) const {
  std::vector<AudioDeviceInfo> devices;
  ScopedCoInitialize com(COINIT_MULTITHREADED);
  if (FAILED(com.result()) && com.result() != RPC_E_CHANGED_MODE) {
    return devices;
  }

  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))) {
    return devices;
  }

  std::string resolved_default_id;
  ComPtr<IMMDevice> default_device;
  if (SUCCEEDED(
          enumerator->GetDefaultAudioEndpoint(flow, eConsole, &default_device))) {
    resolved_default_id = ReadDeviceId(default_device.Get());
  }

  if (default_device_id != nullptr) {
    *default_device_id = resolved_default_id;
  }

  ComPtr<IMMDeviceCollection> collection;
  if (FAILED(
          enumerator->EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE, &collection))) {
    return devices;
  }

  UINT count = 0;
  if (FAILED(collection->GetCount(&count))) {
    return devices;
  }

  devices.reserve(count);
  for (UINT index = 0; index < count; ++index) {
    ComPtr<IMMDevice> device;
    if (FAILED(collection->Item(index, &device))) {
      continue;
    }

    AudioDeviceInfo info;
    info.id = ReadDeviceId(device.Get());
    info.name = ReadFriendlyName(device.Get(), flow);
    info.is_default = info.id == resolved_default_id;
    devices.push_back(std::move(info));
  }

  return devices;
}

bool SystemAudioMeterPlugin::ResolveRequestedDevice(
    EDataFlow flow, const std::string& selected_device_id,
    const std::string& selected_device_name, IMMDeviceEnumerator* enumerator,
    IMMDevice** device, AudioDeviceInfo* device_info) const {
  if (enumerator == nullptr || device == nullptr || device_info == nullptr ||
      selected_device_id.empty()) {
    return false;
  }

  if (SUCCEEDED(enumerator->GetDevice(Utf8ToWide(selected_device_id).c_str(),
                                      device)) &&
      *device != nullptr) {
    device_info->id = selected_device_id;
    device_info->name = ReadFriendlyName(*device, flow);
    std::string default_device_id;
    EnumerateDevices(flow, &default_device_id);
    device_info->is_default = selected_device_id == default_device_id;
    return true;
  }

  if (selected_device_name.empty()) {
    return false;
  }

  const auto devices = EnumerateDevices(flow);
  for (const auto& candidate : devices) {
    if (candidate.name != selected_device_name) {
      continue;
    }
    if (FAILED(enumerator->GetDevice(Utf8ToWide(candidate.id).c_str(),
                                     device)) ||
        *device == nullptr) {
      continue;
    }
    *device_info = candidate;
    return true;
  }

  return false;
}

bool SystemAudioMeterPlugin::ResolveCurrentDevice(EDataFlow flow,
                                                  AudioDeviceInfo* device_info) const {
  if (device_info == nullptr) {
    return false;
  }

  const auto devices = EnumerateDevices(flow);
  std::string selected_id;
  std::string selected_name;
  std::string current_id;
  std::string current_name;
  bool current_is_default = false;
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    if (flow == eCapture) {
      selected_id = selected_input_device_id_;
      selected_name = selected_input_device_name_;
      current_id = current_input_device_id_;
      current_name = current_input_device_name_;
      current_is_default = current_input_device_is_default_;
    } else {
      selected_id = selected_output_device_id_;
      selected_name = selected_output_device_name_;
      current_id = current_output_device_id_;
      current_name = current_output_device_name_;
      current_is_default = current_output_device_is_default_;
    }
  }

  if (!current_id.empty()) {
    *device_info = AudioDeviceInfo{
        current_id,
        current_name.empty() ? UnknownDeviceName(flow) : current_name,
        current_is_default,
    };
    return true;
  }

  if (!selected_id.empty()) {
    for (const auto& device : devices) {
      if (device.id == selected_id) {
        *device_info = device;
        return true;
      }
    }
    if (!selected_name.empty()) {
      for (const auto& device : devices) {
        if (device.name == selected_name) {
          *device_info = device;
          return true;
        }
      }
    }
  }

  for (const auto& device : devices) {
    if (device.is_default) {
      *device_info = device;
      return true;
    }
  }

  if (!devices.empty()) {
    *device_info = devices.front();
    return true;
  }
  return false;
}

std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
SystemAudioMeterPlugin::OnOutputListen(
    std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) {
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    output_event_sink_ = std::move(events);
    output_listener_active_ = true;
  }
  SyncCaptureState(eRender);
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
SystemAudioMeterPlugin::OnOutputCancel() {
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    output_listener_active_ = false;
    output_event_sink_.reset();
  }
  SyncCaptureState(eRender);
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
SystemAudioMeterPlugin::OnInputListen(
    std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) {
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    input_event_sink_ = std::move(events);
    input_listener_active_ = true;
  }
  SyncCaptureState(eCapture);
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
SystemAudioMeterPlugin::OnInputCancel() {
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    input_listener_active_ = false;
    input_event_sink_.reset();
  }
  SyncCaptureState(eCapture);
  return nullptr;
}

void SystemAudioMeterPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "getOutputDevices") {
    const auto devices = EnumerateDevices(eRender);
    EncodableList encoded_devices;
    encoded_devices.reserve(devices.size());
    for (const auto& device : devices) {
      encoded_devices.push_back(EncodeDevice(device));
    }
    result->Success(encoded_devices);
    return;
  }

  if (method == "getInputDevices") {
    const auto devices = EnumerateDevices(eCapture);
    EncodableList encoded_devices;
    encoded_devices.reserve(devices.size());
    for (const auto& device : devices) {
      encoded_devices.push_back(EncodeDevice(device));
    }
    result->Success(encoded_devices);
    return;
  }

  if (method == "setOutputDevice" || method == "setInputDevice") {
    std::string device_id;
    if (const auto* arguments = std::get_if<EncodableMap>(method_call.arguments())) {
      const auto it = arguments->find(EncodableValue("deviceId"));
      if (it != arguments->end()) {
        if (const auto* value = std::get_if<std::string>(&it->second)) {
          device_id = *value;
        }
      }
    }

    const bool is_input = method == "setInputDevice";
    std::string selected_device_name;
    if (!device_id.empty()) {
      const auto devices = EnumerateDevices(is_input ? eCapture : eRender);
      for (const auto& device : devices) {
        if (device.id == device_id) {
          selected_device_name = device.name;
          break;
        }
      }
    }
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      if (is_input) {
        selected_input_device_id_ = device_id;
        selected_input_device_name_ = selected_device_name;
        current_input_device_id_.clear();
        current_input_device_name_.clear();
        current_input_device_is_default_ = false;
      } else {
        selected_output_device_id_ = device_id;
        selected_output_device_name_ = selected_device_name;
        current_output_device_id_.clear();
        current_output_device_name_.clear();
        current_output_device_is_default_ = false;
      }
    }
    SyncCaptureState(is_input ? eCapture : eRender, true);
    result->Success();
    return;
  }

  if (method == "getCurrentOutputDevice" || method == "getCurrentInputDevice") {
    AudioDeviceInfo device_info;
    const EDataFlow flow =
        method == "getCurrentInputDevice" ? eCapture : eRender;
    if (!ResolveCurrentDevice(flow, &device_info)) {
      result->Success(EncodableValue());
      return;
    }
    result->Success(EncodeDevice(device_info));
    return;
  }

  if (method == "start" || method == "startInput") {
    const bool is_input = method == "startInput";
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      if (is_input) {
        input_requested_running_ = true;
      } else {
        output_requested_running_ = true;
      }
    }
    SyncCaptureState(is_input ? eCapture : eRender);
    result->Success();
    return;
  }

  if (method == "stop" || method == "stopInput") {
    const bool is_input = method == "stopInput";
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      if (is_input) {
        input_requested_running_ = false;
      } else {
        output_requested_running_ = false;
      }
    }
    SyncCaptureState(is_input ? eCapture : eRender);
    result->Success();
    return;
  }

  if (method == "enableSilenceDetection") {
    EDataFlow flow = eRender;
    double threshold = -1.0;
    int64_t duration_ms = 0;
    if (const auto* arguments = std::get_if<EncodableMap>(method_call.arguments())) {
      const auto flow_it = arguments->find(EncodableValue("flow"));
      if (flow_it != arguments->end()) {
        if (const auto* value = std::get_if<std::string>(&flow_it->second)) {
          flow = *value == "input" ? eCapture : eRender;
        }
      }

      const auto threshold_it = arguments->find(EncodableValue("threshold"));
      if (threshold_it != arguments->end()) {
        if (const auto* value = std::get_if<double>(&threshold_it->second)) {
          threshold = *value;
        } else if (const auto* value = std::get_if<int32_t>(&threshold_it->second)) {
          threshold = static_cast<double>(*value);
        } else if (const auto* value = std::get_if<int64_t>(&threshold_it->second)) {
          threshold = static_cast<double>(*value);
        }
      }

      const auto duration_it = arguments->find(EncodableValue("durationMs"));
      if (duration_it != arguments->end()) {
        if (const auto* value = std::get_if<int32_t>(&duration_it->second)) {
          duration_ms = *value;
        } else if (const auto* value = std::get_if<int64_t>(&duration_it->second)) {
          duration_ms = *value;
        } else if (const auto* value = std::get_if<double>(&duration_it->second)) {
          duration_ms = static_cast<int64_t>(*value);
        }
      }
    }

    if (!std::isfinite(threshold) || threshold < 0.0 || threshold > 1.0) {
      result->Error("invalid_silence_threshold",
                    "Silence detection threshold must be a finite value between 0.0 and 1.0.",
                    EncodableValue());
      return;
    }
    if (duration_ms <= 0) {
      result->Error("invalid_silence_duration",
                    "Silence detection duration must be greater than 0 milliseconds.",
                    EncodableValue());
      return;
    }

    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      auto& state =
          flow == eCapture ? input_silence_detection_state_
                           : output_silence_detection_state_;
      state.enabled = true;
      state.threshold = threshold;
      state.duration = std::chrono::milliseconds(duration_ms);
      state.is_silent = false;
      state.has_candidate = false;
      state.candidate_started_at = std::chrono::steady_clock::time_point{};
    }
    SyncCaptureState(flow);
    result->Success();
    return;
  }

  if (method == "disableSilenceDetection") {
    EDataFlow flow = eRender;
    if (const auto* arguments = std::get_if<EncodableMap>(method_call.arguments())) {
      const auto flow_it = arguments->find(EncodableValue("flow"));
      if (flow_it != arguments->end()) {
        if (const auto* value = std::get_if<std::string>(&flow_it->second)) {
          flow = *value == "input" ? eCapture : eRender;
        }
      }
    }
    ResetSilenceDetectionState(flow, false);
    SyncCaptureState(flow);
    result->Success();
    return;
  }

  if (method == "isRunning") {
    result->Success(EncodableValue(output_capture_active_.load()));
    return;
  }

  if (method == "isInputRunning") {
    result->Success(EncodableValue(input_capture_active_.load()));
    return;
  }

  result->NotImplemented();
}

void SystemAudioMeterPlugin::SyncCaptureState(EDataFlow flow, bool force_restart) {
  bool should_run = false;
  std::string selected_device_id;
  std::atomic<bool>* stop_requested = nullptr;
  std::atomic<bool>* capture_active = nullptr;
  std::thread* capture_thread = nullptr;

  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    if (flow == eCapture) {
      should_run = input_requested_running_ &&
                   (input_listener_active_ ||
                    (silence_listener_active_ &&
                     input_silence_detection_state_.enabled));
      selected_device_id = selected_input_device_id_;
      stop_requested = &input_stop_requested_;
      capture_active = &input_capture_active_;
      capture_thread = &input_capture_thread_;
    } else {
      should_run = output_requested_running_ &&
                   (output_listener_active_ ||
                    (silence_listener_active_ &&
                     output_silence_detection_state_.enabled));
      selected_device_id = selected_output_device_id_;
      stop_requested = &output_stop_requested_;
      capture_active = &output_capture_active_;
      capture_thread = &output_capture_thread_;
    }

    if (!should_run || force_restart) {
      stop_requested->store(true);
    }
  }

  if (capture_thread->joinable() && (!should_run || force_restart)) {
    capture_thread->join();
    capture_active->store(false);
  }

  if (!should_run) {
    ResetSilenceDetectionState(flow, true);
    return;
  }

  if (capture_thread->joinable()) {
    if (!capture_active->load()) {
      capture_thread->join();
    } else {
      return;
    }
  }

  capture_active->store(true);
  stop_requested->store(false);
  *capture_thread =
      std::thread([this, flow, selected_device_id]() { CaptureLoop(flow, selected_device_id); });
}

void SystemAudioMeterPlugin::CaptureLoop(EDataFlow flow,
                                         std::string selected_device_id) {
  std::atomic<bool>& stop_requested =
      flow == eCapture ? input_stop_requested_ : output_stop_requested_;
  std::atomic<bool>& capture_active =
      flow == eCapture ? input_capture_active_ : output_capture_active_;

  ScopedCoInitialize com(COINIT_MULTITHREADED);
  if (FAILED(com.result()) && com.result() != RPC_E_CHANGED_MODE) {
    capture_active.store(false);
    EmitError(flow, "com_init_failed",
              "Failed to initialize COM for WASAPI capture.");
    return;
  }

  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                              IID_PPV_ARGS(&enumerator)))) {
    capture_active.store(false);
    EmitError(flow, "device_enumerator_failed",
              "Failed to create the Windows audio device enumerator.");
    return;
  }

  ComPtr<IMMDevice> device;
  AudioDeviceInfo device_info;
  std::string selected_device_name;
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    selected_device_name =
        flow == eCapture ? selected_input_device_name_ : selected_output_device_name_;
  }

  if (!selected_device_id.empty()) {
    ResolveRequestedDevice(flow, selected_device_id, selected_device_name,
                           enumerator.Get(), device.GetAddressOf(), &device_info);
  }

  if (!device) {
    if (!selected_device_id.empty()) {
      capture_active.store(false);
      EmitDeviceEvent(flow, "disconnected", selected_device_id,
                      selected_device_name, false, true);
      return;
    }

    if (FAILED(enumerator->GetDefaultAudioEndpoint(flow, eConsole, &device))) {
      capture_active.store(false);
      EmitDeviceEvent(flow, "disconnected", std::string(), std::string(), true,
                      true);
      return;
    }
    device_info.id = ReadDeviceId(device.Get());
    device_info.name = ReadFriendlyName(device.Get(), flow);
    device_info.is_default = true;
  }

  ComPtr<IAudioClient> audio_client;
  if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                              reinterpret_cast<void**>(audio_client.GetAddressOf())))) {
    capture_active.store(false);
    EmitError(flow, "audio_client_activate_failed",
              "Failed to activate the WASAPI audio client.");
    return;
  }

  WAVEFORMATEX* mix_format_raw = nullptr;
  if (FAILED(audio_client->GetMixFormat(&mix_format_raw)) || mix_format_raw == nullptr) {
    capture_active.store(false);
    EmitError(flow, "mix_format_failed", MixFormatFailureMessage(flow));
    return;
  }
  std::unique_ptr<WAVEFORMATEX, decltype(&CoTaskMemFree)> mix_format(
      mix_format_raw, &CoTaskMemFree);

  const DWORD stream_flags =
      flow == eCapture ? 0 : AUDCLNT_STREAMFLAGS_LOOPBACK;
  const HRESULT initialize_result = audio_client->Initialize(
      AUDCLNT_SHAREMODE_SHARED, stream_flags, kRequestedBufferDuration, 0,
      mix_format.get(), nullptr);
  if (FAILED(initialize_result)) {
    capture_active.store(false);
    EmitError(flow, InitializeFailureCode(flow), InitializeFailureMessage(flow));
    return;
  }

  ComPtr<IAudioCaptureClient> capture_client;
  if (FAILED(audio_client->GetService(IID_PPV_ARGS(&capture_client)))) {
    capture_active.store(false);
    EmitError(flow, "capture_service_failed",
              "Failed to acquire the WASAPI capture client.");
    return;
  }

  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    if (flow == eCapture) {
      if (!selected_input_device_id_.empty()) {
        selected_input_device_id_ = device_info.id;
        selected_input_device_name_ = device_info.name;
      }
      current_input_device_id_ = device_info.id;
      current_input_device_name_ = device_info.name;
      current_input_device_is_default_ = device_info.is_default;
    } else {
      if (!selected_output_device_id_.empty()) {
        selected_output_device_id_ = device_info.id;
        selected_output_device_name_ = device_info.name;
      }
      current_output_device_id_ = device_info.id;
      current_output_device_name_ = device_info.name;
      current_output_device_is_default_ = device_info.is_default;
    }
  }
  EmitDeviceEvent(flow, "connected", device_info.id, device_info.name,
                  device_info.is_default, !selected_device_id.empty());

  if (FAILED(audio_client->Start())) {
    capture_active.store(false);
    EmitError(flow, StartFailureCode(flow), StartFailureMessage(flow));
    ClearCurrentDevice(flow);
    return;
  }

  auto last_emit_at = std::chrono::steady_clock::now() - kEmitInterval;
  double pending_left_peak = 0.0;
  double pending_right_peak = 0.0;
  bool device_lost = false;

  while (!stop_requested.load()) {
    UINT32 packet_length = 0;
    HRESULT packet_result = capture_client->GetNextPacketSize(&packet_length);
    if (FAILED(packet_result)) {
      EmitLevels(flow, 0.0, 0.0, device_info.id, device_info.name);
      ResetSilenceDetectionState(flow, true);
      ClearCurrentDevice(flow);
      EmitDeviceEvent(flow, "disconnected", device_info.id, device_info.name,
                      device_info.is_default, !selected_device_id.empty());
      ClearDeviceInfo(&device_info);
      device_lost = true;
      break;
    }

    bool processed_packet = false;
    while (packet_length > 0 && !stop_requested.load()) {
      BYTE* data = nullptr;
      UINT32 num_frames = 0;
      DWORD flags = 0;
      HRESULT buffer_result =
          capture_client->GetBuffer(&data, &num_frames, &flags, nullptr, nullptr);
      if (FAILED(buffer_result)) {
        EmitLevels(flow, 0.0, 0.0, device_info.id, device_info.name);
        ResetSilenceDetectionState(flow, true);
        ClearCurrentDevice(flow);
        EmitDeviceEvent(flow, "disconnected", device_info.id, device_info.name,
                        device_info.is_default, !selected_device_id.empty());
        ClearDeviceInfo(&device_info);
        device_lost = true;
        packet_length = 0;
        break;
      }

      double packet_left_peak = 0.0;
      double packet_right_peak = 0.0;
      ProcessAudioPacket(data, num_frames, flags, mix_format.get(), &packet_left_peak,
                         &packet_right_peak);

      pending_left_peak = (std::max)(pending_left_peak, packet_left_peak);
      pending_right_peak = (std::max)(pending_right_peak, packet_right_peak);
      processed_packet = true;

      capture_client->ReleaseBuffer(num_frames);

      if (FAILED(capture_client->GetNextPacketSize(&packet_length))) {
        EmitLevels(flow, 0.0, 0.0, device_info.id, device_info.name);
        ResetSilenceDetectionState(flow, true);
        ClearCurrentDevice(flow);
        EmitDeviceEvent(flow, "disconnected", device_info.id, device_info.name,
                        device_info.is_default, !selected_device_id.empty());
        ClearDeviceInfo(&device_info);
        device_lost = true;
        packet_length = 0;
        break;
      }
    }

    const auto now = std::chrono::steady_clock::now();
    if ((processed_packet || now - last_emit_at >= kEmitInterval) &&
        now - last_emit_at >= kEmitInterval) {
      EmitLevels(flow, pending_left_peak, pending_right_peak, device_info.id,
                 device_info.name);
      ProcessSilenceDetection(flow, (std::max)(pending_left_peak, pending_right_peak), now,
                              device_info.id, device_info.name);
      pending_left_peak = 0.0;
      pending_right_peak = 0.0;
      last_emit_at = now;
    }

    if (!processed_packet) {
      ::Sleep(10);
    }
  }

  audio_client->Stop();
  capture_active.store(false);
  if (!device_lost) {
    ResetSilenceDetectionState(flow, true);
    ClearCurrentDevice(flow);
  }
}

void SystemAudioMeterPlugin::EmitLevels(EDataFlow flow, double left_peak,
                                        double right_peak,
                                        const std::string& device_id,
                                        const std::string& device_name) {
  std::lock_guard<std::mutex> lock(state_mutex_);
  auto& event_sink = flow == eCapture ? input_event_sink_ : output_event_sink_;
  if (!event_sink) {
    return;
  }

  const auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::system_clock::now().time_since_epoch())
                             .count();

  EncodableMap event{
      {EncodableValue("leftPeak"), EncodableValue(ClampPeak(left_peak))},
      {EncodableValue("rightPeak"), EncodableValue(ClampPeak(right_peak))},
      {EncodableValue("timestamp"), EncodableValue(static_cast<int64_t>(timestamp))},
  };
  if (flow == eCapture) {
    event[EncodableValue("inputDeviceId")] = EncodableValue(device_id);
    event[EncodableValue("inputDeviceName")] = EncodableValue(device_name);
  } else {
    event[EncodableValue("outputDeviceId")] = EncodableValue(device_id);
    event[EncodableValue("outputDeviceName")] = EncodableValue(device_name);
  }
  event_sink->Success(EncodableValue(event));
}

void SystemAudioMeterPlugin::EmitDeviceEvent(
    EDataFlow flow, const std::string& kind, const std::string& device_id,
    const std::string& device_name, bool is_default, bool is_selected) {
  std::lock_guard<std::mutex> lock(state_mutex_);
  if (!device_event_sink_) {
    return;
  }

  const auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::system_clock::now().time_since_epoch())
                             .count();
  EncodableMap event{
      {EncodableValue("kind"), EncodableValue(kind)},
      {EncodableValue("flow"),
       EncodableValue(flow == eCapture ? "input" : "output")},
      {EncodableValue("timestamp"), EncodableValue(static_cast<int64_t>(timestamp))},
      {EncodableValue("deviceId"), EncodableValue(device_id)},
      {EncodableValue("deviceName"), EncodableValue(device_name)},
      {EncodableValue("isDefault"), EncodableValue(is_default)},
      {EncodableValue("isSelected"), EncodableValue(is_selected)},
  };
  device_event_sink_->Success(EncodableValue(event));
}

void SystemAudioMeterPlugin::ProcessSilenceDetection(
    EDataFlow flow, double peak_level, std::chrono::steady_clock::time_point now,
    const std::string& device_id, const std::string& device_name) {
  std::lock_guard<std::mutex> lock(state_mutex_);
  auto& state =
      flow == eCapture ? input_silence_detection_state_
                       : output_silence_detection_state_;
  if (!state.enabled) {
    return;
  }

  const double clamped_peak = ClampPeak(peak_level);
  std::string event_type;

  if (clamped_peak < state.threshold) {
    if (state.is_silent) {
      return;
    }
    if (!state.has_candidate) {
      state.candidate_started_at = now;
      state.has_candidate = true;
      return;
    }
    if (now - state.candidate_started_at < state.duration) {
      return;
    }

    state.is_silent = true;
    state.has_candidate = false;
    state.candidate_started_at = std::chrono::steady_clock::time_point{};
    event_type = "silenceStarted";
  } else {
    state.has_candidate = false;
    state.candidate_started_at = std::chrono::steady_clock::time_point{};
    if (!state.is_silent) {
      return;
    }
    state.is_silent = false;
    event_type = "silenceEnded";
  }

  if (!silence_event_sink_) {
    return;
  }

  const auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::system_clock::now().time_since_epoch())
                             .count();
  EncodableMap event{
      {EncodableValue("type"), EncodableValue(event_type)},
      {EncodableValue("flow"),
       EncodableValue(flow == eCapture ? "input" : "output")},
      {EncodableValue("peakLevel"), EncodableValue(clamped_peak)},
      {EncodableValue("timestamp"), EncodableValue(static_cast<int64_t>(timestamp))},
      {EncodableValue("deviceId"), EncodableValue(device_id)},
      {EncodableValue("deviceName"), EncodableValue(device_name)},
  };
  silence_event_sink_->Success(EncodableValue(event));
}

void SystemAudioMeterPlugin::ResetSilenceDetectionState(
    EDataFlow flow, bool preserve_configuration) {
  std::lock_guard<std::mutex> lock(state_mutex_);
  auto& state =
      flow == eCapture ? input_silence_detection_state_
                       : output_silence_detection_state_;
  state.is_silent = false;
  state.has_candidate = false;
  state.candidate_started_at = std::chrono::steady_clock::time_point{};
  if (!preserve_configuration) {
    state.enabled = false;
    state.threshold = 0.0;
    state.duration = std::chrono::milliseconds(0);
  }
}

void SystemAudioMeterPlugin::EmitError(EDataFlow flow, const std::string& code,
                                       const std::string& message) {
  std::lock_guard<std::mutex> lock(state_mutex_);
  auto& event_sink = flow == eCapture ? input_event_sink_ : output_event_sink_;
  if (!event_sink) {
    return;
  }
  event_sink->Error(code, message, EncodableValue());
}

void SystemAudioMeterPlugin::ClearCurrentDevice(EDataFlow flow) {
  std::lock_guard<std::mutex> lock(state_mutex_);
  if (flow == eCapture) {
    current_input_device_id_.clear();
    current_input_device_name_.clear();
    current_input_device_is_default_ = false;
  } else {
    current_output_device_id_.clear();
    current_output_device_name_.clear();
    current_output_device_is_default_ = false;
  }
}

void SystemAudioMeterPlugin::RegisterDeviceNotifications() {
  ScopedCoInitialize com(COINIT_MULTITHREADED);
  if (FAILED(com.result()) && com.result() != RPC_E_CHANGED_MODE) {
    return;
  }

  IMMDeviceEnumerator* enumerator = nullptr;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                              IID_PPV_ARGS(&enumerator))) ||
      enumerator == nullptr) {
    return;
  }

  auto* notification_client = new DeviceNotificationClient(this);
  const HRESULT register_result =
      enumerator->RegisterEndpointNotificationCallback(notification_client);
  if (FAILED(register_result)) {
    notification_client->Release();
    enumerator->Release();
    return;
  }

  notification_enumerator_ = enumerator;
  notification_client_ = notification_client;
}

void SystemAudioMeterPlugin::UnregisterDeviceNotifications() {
  if (notification_enumerator_ != nullptr && notification_client_ != nullptr) {
    notification_enumerator_->UnregisterEndpointNotificationCallback(
        notification_client_);
  }
  if (notification_client_ != nullptr) {
    notification_client_->Release();
    notification_client_ = nullptr;
  }
  if (notification_enumerator_ != nullptr) {
    notification_enumerator_->Release();
    notification_enumerator_ = nullptr;
  }
}

void SystemAudioMeterPlugin::HandleDeviceNotification(
    EDataFlow flow, const std::string* device_id, bool default_device_changed) {
  bool should_restart = false;
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    const bool requested_running =
        flow == eCapture ? input_requested_running_ : output_requested_running_;
    const bool listener_active =
        flow == eCapture ? input_listener_active_ : output_listener_active_;
    const std::string& selected_device_id =
        flow == eCapture ? selected_input_device_id_ : selected_output_device_id_;
    const std::string& current_device_id =
        flow == eCapture ? current_input_device_id_ : current_output_device_id_;

    if (!(requested_running && listener_active)) {
      return;
    }

    if (default_device_changed) {
      should_restart = selected_device_id.empty();
    } else if (current_device_id.empty()) {
      should_restart = true;
    } else if (device_id != nullptr && !selected_device_id.empty() &&
               selected_device_id == *device_id) {
      should_restart = true;
    } else if (device_id != nullptr && current_device_id == *device_id) {
      should_restart = true;
    }
  }

  if (should_restart) {
    SyncCaptureState(flow, true);
  }
}

}  // namespace system_audio_meter
