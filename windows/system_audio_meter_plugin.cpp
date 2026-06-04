#include "system_audio_meter_plugin.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <audioclient.h>
#include <propkey.h>
#include <functiondiscoverykeys_devpkey.h>
#include <ksmedia.h>
#include <mmdeviceapi.h>
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

#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>
namespace system_audio_meter {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

constexpr char kMethodChannelName[] = "system_audio_meter";
constexpr char kEventChannelName[] = "system_audio_meter/levels";
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

std::string ReadFriendlyName(IMMDevice* device) {
  ComPtr<IPropertyStore> property_store;
  if (FAILED(device->OpenPropertyStore(STGM_READ, &property_store))) {
    return "Unknown output device";
  }

  PROPVARIANT variant;
  PropVariantInit(&variant);
  std::string name = "Unknown output device";
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

}  // namespace

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
  event_channel_ =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar_->messenger(), kEventChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  auto stream_handler =
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue* arguments,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            return OnListen(std::move(events));
          },
          [this](const EncodableValue* arguments)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            return OnCancel();
          });

  event_channel_->SetStreamHandler(std::move(stream_handler));
}

SystemAudioMeterPlugin::~SystemAudioMeterPlugin() {
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    requested_running_ = false;
    listener_active_ = false;
    event_sink_.reset();
  }
  SyncCaptureState();
}

flutter::EncodableValue SystemAudioMeterPlugin::EncodeDevice(
    const AudioOutputDeviceInfo& device_info) const {
  return EncodableMap{
      {EncodableValue("id"), EncodableValue(device_info.id)},
      {EncodableValue("name"), EncodableValue(device_info.name)},
      {EncodableValue("isDefault"), EncodableValue(device_info.is_default)},
  };
}

std::vector<AudioOutputDeviceInfo> SystemAudioMeterPlugin::EnumerateOutputDevices(
    std::string* default_device_id) const {
  std::vector<AudioOutputDeviceInfo> devices;
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
  if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole,
                                                    &default_device))) {
    resolved_default_id = ReadDeviceId(default_device.Get());
  }

  if (default_device_id != nullptr) {
    *default_device_id = resolved_default_id;
  }

  ComPtr<IMMDeviceCollection> collection;
  if (FAILED(
          enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &collection))) {
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

    AudioOutputDeviceInfo info;
    info.id = ReadDeviceId(device.Get());
    info.name = ReadFriendlyName(device.Get());
    info.is_default = info.id == resolved_default_id;
    devices.push_back(std::move(info));
  }

  return devices;
}

bool SystemAudioMeterPlugin::ResolveCurrentOutputDevice(
    AudioOutputDeviceInfo* device_info) const {
  if (device_info == nullptr) {
    return false;
  }

  const auto devices = EnumerateOutputDevices();
  std::string selected_id;
  std::string current_id;
  std::string current_name;
  bool current_is_default = false;
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    selected_id = selected_device_id_;
    current_id = current_device_id_;
    current_name = current_device_name_;
    current_is_default = current_device_is_default_;
  }

  if (!current_id.empty()) {
    *device_info = AudioOutputDeviceInfo{
        current_id,
        current_name.empty() ? "Unknown output device" : current_name,
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
SystemAudioMeterPlugin::OnListen(
    std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) {
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    event_sink_ = std::move(events);
    listener_active_ = true;
  }
  SyncCaptureState();
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
SystemAudioMeterPlugin::OnCancel() {
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    listener_active_ = false;
    event_sink_.reset();
  }
  SyncCaptureState();
  return nullptr;
}

void SystemAudioMeterPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "getOutputDevices") {
    const auto devices = EnumerateOutputDevices();
    EncodableList encoded_devices;
    encoded_devices.reserve(devices.size());
    for (const auto& device : devices) {
      encoded_devices.push_back(EncodeDevice(device));
    }
    result->Success(encoded_devices);
    return;
  }

  if (method == "setOutputDevice") {
    std::string device_id;
    if (const auto* arguments = std::get_if<EncodableMap>(method_call.arguments())) {
      const auto it = arguments->find(EncodableValue("deviceId"));
      if (it != arguments->end()) {
        if (const auto* value = std::get_if<std::string>(&it->second)) {
          device_id = *value;
        }
      }
    }

    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      selected_device_id_ = device_id;
      current_device_id_.clear();
      current_device_name_.clear();
      current_device_is_default_ = false;
    }
    SyncCaptureState(true);
    result->Success();
    return;
  }

  if (method == "getCurrentOutputDevice") {
    AudioOutputDeviceInfo device_info;
    if (!ResolveCurrentOutputDevice(&device_info)) {
      result->Success(EncodableValue());
      return;
    }
    result->Success(EncodeDevice(device_info));
    return;
  }

  if (method == "start") {
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      requested_running_ = true;
    }
    SyncCaptureState();
    result->Success();
    return;
  }

  if (method == "stop") {
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      requested_running_ = false;
    }
    SyncCaptureState();
    result->Success();
    return;
  }

  if (method == "isRunning") {
    result->Success(EncodableValue(capture_active_.load()));
    return;
  }

  result->NotImplemented();
}

void SystemAudioMeterPlugin::SyncCaptureState(bool force_restart) {
  bool should_run = false;
  std::string selected_device_id;
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    should_run = requested_running_ && listener_active_;
    selected_device_id = selected_device_id_;
    if (!should_run || force_restart) {
      stop_requested_.store(true);
    }
  }

  if (capture_thread_.joinable() && (!should_run || force_restart)) {
    capture_thread_.join();
    capture_active_.store(false);
  }

  if (!should_run) {
    return;
  }

  if (capture_thread_.joinable()) {
    if (!capture_active_.load()) {
      capture_thread_.join();
    } else {
      return;
    }
  }

  capture_active_.store(true);
  stop_requested_.store(false);
  capture_thread_ =
      std::thread([this, selected_device_id]() { CaptureLoop(selected_device_id); });
}

void SystemAudioMeterPlugin::CaptureLoop(std::string selected_device_id) {
  ScopedCoInitialize com(COINIT_MULTITHREADED);
  if (FAILED(com.result()) && com.result() != RPC_E_CHANGED_MODE) {
    capture_active_.store(false);
    EmitError("com_init_failed", "Failed to initialize COM for WASAPI capture.");
    return;
  }

  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                              IID_PPV_ARGS(&enumerator)))) {
    capture_active_.store(false);
    EmitError("device_enumerator_failed",
              "Failed to create the Windows audio device enumerator.");
    return;
  }

  ComPtr<IMMDevice> device;
  AudioOutputDeviceInfo device_info;
  if (!selected_device_id.empty()) {
    if (SUCCEEDED(enumerator->GetDevice(Utf8ToWide(selected_device_id).c_str(),
                                        &device))) {
      device_info.id = selected_device_id;
      device_info.name = ReadFriendlyName(device.Get());
      std::string default_device_id;
      EnumerateOutputDevices(&default_device_id);
      device_info.is_default = selected_device_id == default_device_id;
    }
  }

  if (!device) {
    if (FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device))) {
      capture_active_.store(false);
      EmitError("no_output_device",
                "No active Windows render device is available for loopback metering.");
      return;
    }
    device_info.id = ReadDeviceId(device.Get());
    device_info.name = ReadFriendlyName(device.Get());
    device_info.is_default = true;
  }

  ComPtr<IAudioClient> audio_client;
  if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                              reinterpret_cast<void**>(audio_client.GetAddressOf())))) {
    capture_active_.store(false);
    EmitError("audio_client_activate_failed",
              "Failed to activate the WASAPI audio client.");
    return;
  }

  WAVEFORMATEX* mix_format_raw = nullptr;
  if (FAILED(audio_client->GetMixFormat(&mix_format_raw)) || mix_format_raw == nullptr) {
    capture_active_.store(false);
    EmitError("mix_format_failed", "Failed to read the output device mix format.");
    return;
  }
  std::unique_ptr<WAVEFORMATEX, decltype(&CoTaskMemFree)> mix_format(
      mix_format_raw, &CoTaskMemFree);

  HRESULT initialize_result = audio_client->Initialize(
      AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK,
      kRequestedBufferDuration, 0, mix_format.get(), nullptr);
  if (FAILED(initialize_result)) {
    capture_active_.store(false);
    EmitError(
        "loopback_initialize_failed",
        "Failed to initialize WASAPI loopback capture for the selected output device.");
    return;
  }

  ComPtr<IAudioCaptureClient> capture_client;
  if (FAILED(audio_client->GetService(IID_PPV_ARGS(&capture_client)))) {
    capture_active_.store(false);
    EmitError("capture_service_failed",
              "Failed to acquire the WASAPI capture client.");
    return;
  }

  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    current_device_id_ = device_info.id;
    current_device_name_ = device_info.name;
    current_device_is_default_ = device_info.is_default;
  }

  if (FAILED(audio_client->Start())) {
    capture_active_.store(false);
    EmitError("audio_client_start_failed",
              "Failed to start WASAPI loopback capture.");
    ClearCurrentDevice();
    return;
  }

  auto last_emit_at = std::chrono::steady_clock::now() - kEmitInterval;
  double pending_left_peak = 0.0;
  double pending_right_peak = 0.0;

  while (!stop_requested_.load()) {
    UINT32 packet_length = 0;
    HRESULT packet_result = capture_client->GetNextPacketSize(&packet_length);
    if (FAILED(packet_result)) {
      EmitError("capture_packet_failed",
                "The output device became unavailable during loopback capture.");
      break;
    }

    bool processed_packet = false;
    while (packet_length > 0 && !stop_requested_.load()) {
      BYTE* data = nullptr;
      UINT32 num_frames = 0;
      DWORD flags = 0;
      HRESULT buffer_result =
          capture_client->GetBuffer(&data, &num_frames, &flags, nullptr, nullptr);
      if (FAILED(buffer_result)) {
        EmitError("capture_buffer_failed",
                  "Failed to read the current WASAPI loopback buffer.");
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
        EmitError("capture_packet_failed",
                  "Failed while polling the next WASAPI loopback packet.");
        packet_length = 0;
        break;
      }
    }

    const auto now = std::chrono::steady_clock::now();
    if ((processed_packet || now - last_emit_at >= kEmitInterval) &&
        now - last_emit_at >= kEmitInterval) {
      EmitLevels(pending_left_peak, pending_right_peak, device_info.id, device_info.name);
      pending_left_peak = 0.0;
      pending_right_peak = 0.0;
      last_emit_at = now;
    }

    if (!processed_packet) {
      ::Sleep(10);
    }
  }

  audio_client->Stop();
  capture_active_.store(false);
  ClearCurrentDevice();
}

void SystemAudioMeterPlugin::EmitLevels(double left_peak, double right_peak,
                                        const std::string& output_device_id,
                                        const std::string& output_device_name) {
  std::lock_guard<std::mutex> lock(state_mutex_);
  if (!event_sink_) {
    return;
  }

  const auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::system_clock::now().time_since_epoch())
                             .count();

  EncodableMap event{
      {EncodableValue("leftPeak"), EncodableValue(ClampPeak(left_peak))},
      {EncodableValue("rightPeak"), EncodableValue(ClampPeak(right_peak))},
      {EncodableValue("timestamp"), EncodableValue(static_cast<int64_t>(timestamp))},
      {EncodableValue("outputDeviceId"), EncodableValue(output_device_id)},
      {EncodableValue("outputDeviceName"), EncodableValue(output_device_name)},
  };
  event_sink_->Success(EncodableValue(event));
}

void SystemAudioMeterPlugin::EmitError(const std::string& code,
                                       const std::string& message) {
  std::lock_guard<std::mutex> lock(state_mutex_);
  if (!event_sink_) {
    return;
  }
  event_sink_->Error(code, message, EncodableValue());
}

void SystemAudioMeterPlugin::ClearCurrentDevice() {
  std::lock_guard<std::mutex> lock(state_mutex_);
  current_device_id_.clear();
  current_device_name_.clear();
  current_device_is_default_ = false;
}

}  // namespace system_audio_meter
