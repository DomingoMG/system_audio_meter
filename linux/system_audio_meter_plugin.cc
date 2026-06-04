#include "include/system_audio_meter/system_audio_meter_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>

#include "system_audio_meter_plugin_private.h"

#define SYSTEM_AUDIO_METER_PLUGIN(obj)                            \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), system_audio_meter_plugin_get_type(), \
                              SystemAudioMeterPlugin))

struct _SystemAudioMeterPlugin {
  GObject parent_instance;
  gchar* selected_device_id;
  gboolean is_running;
};

G_DEFINE_TYPE(SystemAudioMeterPlugin, system_audio_meter_plugin, g_object_get_type())

namespace {

constexpr char kMethodChannelName[] = "system_audio_meter";
constexpr char kEventChannelName[] = "system_audio_meter/levels";
constexpr char kUnsupportedCode[] = "unsupported";
constexpr char kUnsupportedMessage[] =
    "System output metering is not implemented on Linux yet. A safe PulseAudio or PipeWire backend still needs to be added.";

FlValue* device_id_arg(FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  return fl_value_lookup_string(args, "deviceId");
}

FlMethodResponse* unsupported_response() {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(kUnsupportedCode, kUnsupportedMessage, nullptr));
}

}  // namespace

static FlMethodResponse* empty_devices_response() {
  g_autoptr(FlValue) result = fl_value_new_list();
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* current_device_response() {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* is_running_response(gboolean is_running) {
  g_autoptr(FlValue) result = fl_value_new_bool(is_running);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void system_audio_meter_plugin_handle_method_call(
    SystemAudioMeterPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "getOutputDevices") == 0) {
    response = empty_devices_response();
  } else if (strcmp(method, "setOutputDevice") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* device_id = device_id_arg(args);
    g_free(self->selected_device_id);
    self->selected_device_id = nullptr;
    if (device_id != nullptr && fl_value_get_type(device_id) == FL_VALUE_TYPE_STRING) {
      self->selected_device_id = g_strdup(fl_value_get_string(device_id));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "getCurrentOutputDevice") == 0) {
    response = current_device_response();
  } else if (strcmp(method, "start") == 0) {
    response = unsupported_response();
  } else if (strcmp(method, "stop") == 0) {
    self->is_running = FALSE;
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "isRunning") == 0) {
    response = is_running_response(self->is_running);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static FlMethodErrorResponse* system_audio_meter_plugin_on_listen(
    SystemAudioMeterPlugin* self,
    FlValue* args) {
  return fl_method_error_response_new(kUnsupportedCode, kUnsupportedMessage, nullptr);
}

static FlMethodErrorResponse* system_audio_meter_plugin_on_cancel(
    SystemAudioMeterPlugin* self,
    FlValue* args) {
  self->is_running = FALSE;
  return nullptr;
}

static void system_audio_meter_plugin_dispose(GObject* object) {
  SystemAudioMeterPlugin* self = SYSTEM_AUDIO_METER_PLUGIN(object);
  g_clear_pointer(&self->selected_device_id, g_free);
  G_OBJECT_CLASS(system_audio_meter_plugin_parent_class)->dispose(object);
}

static void system_audio_meter_plugin_class_init(SystemAudioMeterPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = system_audio_meter_plugin_dispose;
}

static void system_audio_meter_plugin_init(SystemAudioMeterPlugin* self) {
  self->selected_device_id = nullptr;
  self->is_running = FALSE;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  SystemAudioMeterPlugin* plugin = SYSTEM_AUDIO_METER_PLUGIN(user_data);
  system_audio_meter_plugin_handle_method_call(plugin, method_call);
}

static FlMethodErrorResponse* event_listen_cb(FlEventChannel* channel, FlValue* args,
                                              gpointer user_data) {
  return system_audio_meter_plugin_on_listen(
      SYSTEM_AUDIO_METER_PLUGIN(user_data), args);
}

static FlMethodErrorResponse* event_cancel_cb(FlEventChannel* channel, FlValue* args,
                                              gpointer user_data) {
  return system_audio_meter_plugin_on_cancel(
      SYSTEM_AUDIO_METER_PLUGIN(user_data), args);
}

void system_audio_meter_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  SystemAudioMeterPlugin* plugin = SYSTEM_AUDIO_METER_PLUGIN(
      g_object_new(system_audio_meter_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) method_codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) method_channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            kMethodChannelName, FL_METHOD_CODEC(method_codec));
  fl_method_channel_set_method_call_handler(method_channel, method_call_cb,
                                            g_object_ref(plugin), g_object_unref);

  g_autoptr(FlStandardMethodCodec) event_codec = fl_standard_method_codec_new();
  g_autoptr(FlEventChannel) event_channel =
      fl_event_channel_new(fl_plugin_registrar_get_messenger(registrar),
                           kEventChannelName, FL_METHOD_CODEC(event_codec));
  fl_event_channel_set_stream_handlers(event_channel, event_listen_cb,
                                       event_cancel_cb, g_object_ref(plugin),
                                       g_object_unref);
  g_object_unref(plugin);
}
