import Cocoa
import FlutterMacOS

public class SystemAudioMeterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let unsupportedMessage =
    "System output metering is not implemented on macOS in this plugin yet. Reliable loopback capture typically requires additional driver support."
  private var isRunning = false
  private var selectedDeviceId: String?

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

    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getOutputDevices":
      result([])
    case "setOutputDevice":
      if let args = call.arguments as? [String: Any] {
        selectedDeviceId = args["deviceId"] as? String
      } else {
        selectedDeviceId = nil
      }
      result(nil)
    case "getCurrentOutputDevice":
      result(nil)
    case "start":
      result(
        FlutterError(
          code: "unsupported",
          message: unsupportedMessage,
          details: nil
        )
      )
    case "stop":
      isRunning = false
      result(nil)
    case "isRunning":
      result(isRunning)
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
    isRunning = false
    return nil
  }
}
