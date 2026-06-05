import Cocoa
import FlutterMacOS

public class SystemAudioMeterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let unsupportedMessage =
    "System output metering is not implemented on macOS in this plugin yet. Reliable loopback capture typically requires additional driver support."
  private var isOutputRunning = false
  private var isInputRunning = false
  private var selectedOutputDeviceId: String?
  private var selectedInputDeviceId: String?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SystemAudioMeterPlugin()
    let methodChannel = FlutterMethodChannel(
      name: "system_audio_meter",
      binaryMessenger: registrar.messenger
    )
    let eventChannel = FlutterEventChannel(
      name: "system_audio_meter/levels",
      binaryMessenger: registrar.messenger
    )
    let inputEventChannel = FlutterEventChannel(
      name: "system_audio_meter/input_levels",
      binaryMessenger: registrar.messenger
    )

    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
    inputEventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getOutputDevices":
      result([])
    case "getInputDevices":
      result([])
    case "setOutputDevice":
      if let args = call.arguments as? [String: Any] {
        selectedOutputDeviceId = args["deviceId"] as? String
      } else {
        selectedOutputDeviceId = nil
      }
      result(nil)
    case "setInputDevice":
      if let args = call.arguments as? [String: Any] {
        selectedInputDeviceId = args["deviceId"] as? String
      } else {
        selectedInputDeviceId = nil
      }
      result(nil)
    case "getCurrentOutputDevice":
      result(nil)
    case "getCurrentInputDevice":
      result(nil)
    case "start":
      result(
        FlutterError(
          code: "unsupported",
          message: unsupportedMessage,
          details: nil
        )
      )
    case "startInput":
      result(
        FlutterError(
          code: "unsupported",
          message: unsupportedMessage,
          details: nil
        )
      )
    case "stop":
      isOutputRunning = false
      result(nil)
    case "stopInput":
      isInputRunning = false
      result(nil)
    case "isRunning":
      result(isOutputRunning)
    case "isInputRunning":
      result(isInputRunning)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    return FlutterError(code: "unsupported", message: unsupportedMessage, details: nil)
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    isOutputRunning = false
    isInputRunning = false
    return nil
  }
}
