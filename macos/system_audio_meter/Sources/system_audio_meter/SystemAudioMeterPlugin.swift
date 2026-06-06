import Cocoa
import AVFoundation
import CoreAudio
import FlutterMacOS

private enum AudioFlow {
  case output
  case input
}

private struct AudioDeviceInfo {
  let audioDeviceId: AudioDeviceID
  let id: String
  let name: String
  let isDefault: Bool
}

private struct TapContext {
  let tapObjectId: AudioObjectID
  let tapUID: String
  let streamFormat: AudioStreamBasicDescription
}

private struct AggregateContext {
  let deviceId: AudioObjectID
}

private struct CaptureSetupError: Error {
  let code: String
  let message: String
}

private final class ClosureStreamHandler: NSObject, FlutterStreamHandler {
  let onListenBlock: (@escaping FlutterEventSink) -> Void
  let onCancelBlock: () -> Void

  init(
    onListen: @escaping (@escaping FlutterEventSink) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.onListenBlock = onListen
    self.onCancelBlock = onCancel
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    onListenBlock(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    onCancelBlock()
    return nil
  }
}

private let kMethodChannelName = "system_audio_meter"
private let kOutputEventChannelName = "system_audio_meter/levels"
private let kInputEventChannelName = "system_audio_meter/input_levels"
private let kDeviceEventChannelName = "system_audio_meter/device_events"
private let kSilenceEventChannelName = "system_audio_meter/silence_events"
private let kEmitIntervalNanos: UInt64 = 33_000_000
private let kAggregateDescriptionNameKey = "name"
private let kAggregateDescriptionUIDKey = "uid"
private let kAggregateDescriptionSubDeviceListKey = "subdevices"
private let kAggregateDescriptionMainSubDeviceKey = "master"
private let kAggregateDescriptionIsPrivateKey = "private"
private let kAggregateDescriptionIsStackedKey = "stacked"
private let kAggregateDescriptionTapListKey = "taps"
private let kAggregateDescriptionTapAutoStartKey = "tapautostart"
private let kAggregateSubDeviceUIDKey = "uid"
private let kAggregateSubTapUIDKey = "uid"
private let kAggregateSubTapDriftCompensationKey = "drift"
private let kAggregateDeviceUIDPrefix = "com.openai.system_audio_meter.aggregate."

private let outputTapIOProc: AudioDeviceIOProc = {
  (_, _, inInputData, _, _, _, inClientData) -> OSStatus in
  guard let inClientData else {
    return noErr
  }
  let plugin = Unmanaged<SystemAudioMeterPlugin>.fromOpaque(inClientData).takeUnretainedValue()
  return plugin.handleAudioCallback(flow: .output, inputData: inInputData)
}

private let inputDeviceIOProc: AudioDeviceIOProc = {
  (_, _, inInputData, _, _, _, inClientData) -> OSStatus in
  guard let inClientData else {
    return noErr
  }
  let plugin = Unmanaged<SystemAudioMeterPlugin>.fromOpaque(inClientData).takeUnretainedValue()
  return plugin.handleAudioCallback(flow: .input, inputData: inInputData)
}

private let devicePropertyListener: AudioObjectPropertyListenerProc = {
  (_, inNumberAddresses, inAddresses, inClientData) -> OSStatus in
  guard let inClientData else {
    return noErr
  }

  let plugin = Unmanaged<SystemAudioMeterPlugin>.fromOpaque(inClientData).takeUnretainedValue()
  let addresses = Array(UnsafeBufferPointer(start: inAddresses, count: Int(inNumberAddresses)))
  plugin.handleDevicePropertyChanges(addresses)
  return noErr
}

public class SystemAudioMeterPlugin: NSObject, FlutterPlugin {
  private let stateLock = NSLock()

  private var outputEventSink: FlutterEventSink?
  private var inputEventSink: FlutterEventSink?
  private var deviceEventSink: FlutterEventSink?
  private var silenceEventSink: FlutterEventSink?

  private var outputListenerActive = false
  private var inputListenerActive = false
  private var silenceListenerActive = false
  private var outputRequestedRunning = false
  private var inputRequestedRunning = false

  private var outputCaptureActive = false
  private var inputCaptureActive = false

  private var selectedOutputDeviceId = ""
  private var selectedInputDeviceId = ""
  private var selectedOutputDeviceName = ""
  private var selectedInputDeviceName = ""

  private var currentOutputDeviceId = ""
  private var currentInputDeviceId = ""
  private var currentOutputDeviceName = ""
  private var currentInputDeviceName = ""
  private var currentOutputDeviceIsDefault = false
  private var currentInputDeviceIsDefault = false

  private var knownOutputDevices: [String: AudioDeviceInfo] = [:]
  private var knownInputDevices: [String: AudioDeviceInfo] = [:]

  private var outputRunningAggregateDeviceId: AudioDeviceID = 0
  private var outputTapObjectId: AudioObjectID = 0
  private var outputIoProcId: AudioDeviceIOProcID?
  private var outputStreamFormat = AudioStreamBasicDescription()
  private var outputPendingLeftPeak = 0.0
  private var outputPendingRightPeak = 0.0
  private var outputLastEmitUptimeNanos: UInt64 = 0

  private var inputRunningDeviceId: AudioDeviceID = 0
  private var inputIoProcId: AudioDeviceIOProcID?
  private var inputStreamFormat = AudioStreamBasicDescription()
  private var inputPendingLeftPeak = 0.0
  private var inputPendingRightPeak = 0.0
  private var inputLastEmitUptimeNanos: UInt64 = 0

  private var outputSilenceDetectionEnabled = false
  private var outputSilenceThreshold = 0.0
  private var outputSilenceDurationNanos: UInt64 = 0
  private var outputSilenceCandidateStartUptimeNanos: UInt64 = 0
  private var outputSilenceIsActive = false
  private var outputSilenceBootstrapTimer: DispatchSourceTimer?

  private var inputSilenceDetectionEnabled = false
  private var inputSilenceThreshold = 0.0
  private var inputSilenceDurationNanos: UInt64 = 0
  private var inputSilenceCandidateStartUptimeNanos: UInt64 = 0
  private var inputSilenceIsActive = false
  private var inputSilenceBootstrapTimer: DispatchSourceTimer?

  private var outputStreamHandler: ClosureStreamHandler?
  private var inputStreamHandler: ClosureStreamHandler?
  private var deviceStreamHandler: ClosureStreamHandler?
  private var silenceStreamHandler: ClosureStreamHandler?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SystemAudioMeterPlugin()
    let methodChannel = FlutterMethodChannel(
      name: kMethodChannelName,
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let outputEventChannel = FlutterEventChannel(
      name: kOutputEventChannelName,
      binaryMessenger: registrar.messenger
    )
    let inputEventChannel = FlutterEventChannel(
      name: kInputEventChannelName,
      binaryMessenger: registrar.messenger
    )
    let deviceEventChannel = FlutterEventChannel(
      name: kDeviceEventChannelName,
      binaryMessenger: registrar.messenger
    )
    let silenceEventChannel = FlutterEventChannel(
      name: kSilenceEventChannelName,
      binaryMessenger: registrar.messenger
    )

    let outputHandler = ClosureStreamHandler(
      onListen: { sink in instance.setEventSink(flow: .output, sink: sink) },
      onCancel: { instance.clearEventSink(flow: .output) }
    )
    let inputHandler = ClosureStreamHandler(
      onListen: { sink in instance.setEventSink(flow: .input, sink: sink) },
      onCancel: { instance.clearEventSink(flow: .input) }
    )
    let deviceHandler = ClosureStreamHandler(
      onListen: { sink in instance.setDeviceEventSink(sink) },
      onCancel: { instance.clearDeviceEventSink() }
    )
    let silenceHandler = ClosureStreamHandler(
      onListen: { sink in instance.setSilenceEventSink(sink) },
      onCancel: { instance.clearSilenceEventSink() }
    )

    instance.outputStreamHandler = outputHandler
    instance.inputStreamHandler = inputHandler
    instance.deviceStreamHandler = deviceHandler
    instance.silenceStreamHandler = silenceHandler

    outputEventChannel.setStreamHandler(outputHandler)
    inputEventChannel.setStreamHandler(inputHandler)
    deviceEventChannel.setStreamHandler(deviceHandler)
    silenceEventChannel.setStreamHandler(silenceHandler)

    instance.initializeKnownDevices()
    instance.registerDeviceNotifications()
  }

  deinit {
    unregisterDeviceNotifications()
    stopCapture(flow: .output)
    stopCapture(flow: .input)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getOutputDevices":
      result(enumerateDevices(flow: .output).map(encodeDevice))
    case "getInputDevices":
      result(enumerateDevices(flow: .input).map(encodeDevice))
    case "setOutputDevice":
      setSelectedDevice(flow: .output, arguments: call.arguments)
      syncCaptureState(flow: .output, forceRestart: true)
      result(nil)
    case "setInputDevice":
      setSelectedDevice(flow: .input, arguments: call.arguments)
      syncCaptureState(flow: .input, forceRestart: true)
      result(nil)
    case "getCurrentOutputDevice":
      result(resolveCurrentDevice(flow: .output).map(encodeDevice))
    case "getCurrentInputDevice":
      result(resolveCurrentDevice(flow: .input).map(encodeDevice))
    case "start":
      setRequestedRunning(flow: .output, running: true)
      syncCaptureState(flow: .output)
      result(nil)
    case "startInput":
      requestMicrophonePermissionAndStart(result: result)
    case "stop":
      setRequestedRunning(flow: .output, running: false)
      syncCaptureState(flow: .output)
      result(nil)
    case "stopInput":
      setRequestedRunning(flow: .input, running: false)
      syncCaptureState(flow: .input)
      result(nil)
    case "enableSilenceDetection":
      enableSilenceDetection(arguments: call.arguments, result: result)
    case "disableSilenceDetection":
      let args = call.arguments as? [String: Any]
      let flow: AudioFlow = (args?["flow"] as? String) == "input" ? .input : .output
      resetSilenceDetectionState(flow: flow, preserveConfiguration: false)
      syncCaptureState(flow: flow)
      result(nil)
    case "isRunning":
      result(isCaptureActive(flow: .output))
    case "isInputRunning":
      result(isCaptureActive(flow: .input))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initializeKnownDevices() {
    stateLock.lock()
    knownOutputDevices = Dictionary(
      uniqueKeysWithValues: enumerateDevices(flow: .output).map { ($0.id, $0) }
    )
    knownInputDevices = Dictionary(
      uniqueKeysWithValues: enumerateDevices(flow: .input).map { ($0.id, $0) }
    )
    stateLock.unlock()
  }

  private func requestMicrophonePermissionAndStart(result: @escaping FlutterResult) {
    if #available(macOS 10.14, *) {
      switch AVCaptureDevice.authorizationStatus(for: .audio) {
      case .authorized:
        setRequestedRunning(flow: .input, running: true)
        syncCaptureState(flow: .input)
        result(nil)
      case .notDetermined:
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          DispatchQueue.main.async {
            if granted {
              self.setRequestedRunning(flow: .input, running: true)
              self.syncCaptureState(flow: .input)
              result(nil)
            } else {
              result(
                FlutterError(
                  code: "microphone_permission_denied",
                  message: "Microphone access was denied. Enable it in System Settings > Privacy & Security > Microphone.",
                  details: nil
                )
              )
            }
          }
        }
      case .denied, .restricted:
        result(
          FlutterError(
            code: "microphone_permission_denied",
            message: "Microphone access is not available. Enable it in System Settings > Privacy & Security > Microphone.",
            details: nil
          )
        )
      @unknown default:
        result(
          FlutterError(
            code: "microphone_permission_unknown",
            message: "Unable to determine microphone permission state on macOS.",
            details: nil
          )
        )
      }
      return
    }

    setRequestedRunning(flow: .input, running: true)
    syncCaptureState(flow: .input)
    result(nil)
  }

  private func setEventSink(flow: AudioFlow, sink: @escaping FlutterEventSink) {
    stateLock.lock()
    switch flow {
    case .output:
      outputEventSink = sink
      outputListenerActive = true
    case .input:
      inputEventSink = sink
      inputListenerActive = true
    }
    stateLock.unlock()
    syncCaptureState(flow: flow)
  }

  private func clearEventSink(flow: AudioFlow) {
    stateLock.lock()
    switch flow {
    case .output:
      outputEventSink = nil
      outputListenerActive = false
    case .input:
      inputEventSink = nil
      inputListenerActive = false
    }
    stateLock.unlock()
    syncCaptureState(flow: flow)
  }

  private func setDeviceEventSink(_ sink: @escaping FlutterEventSink) {
    stateLock.lock()
    deviceEventSink = sink
    stateLock.unlock()
  }

  private func clearDeviceEventSink() {
    stateLock.lock()
    deviceEventSink = nil
    stateLock.unlock()
  }

  private func setSilenceEventSink(_ sink: @escaping FlutterEventSink) {
    stateLock.lock()
    silenceEventSink = sink
    silenceListenerActive = true
    stateLock.unlock()
    syncCaptureState(flow: .output)
    syncCaptureState(flow: .input)
  }

  private func clearSilenceEventSink() {
    stateLock.lock()
    silenceEventSink = nil
    silenceListenerActive = false
    stateLock.unlock()
    syncCaptureState(flow: .output)
    syncCaptureState(flow: .input)
  }

  private func enableSilenceDetection(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any]
    let flow: AudioFlow = (args?["flow"] as? String) == "input" ? .input : .output
    let threshold = (args?["threshold"] as? NSNumber)?.doubleValue ?? -1.0
    let durationMs = (args?["durationMs"] as? NSNumber)?.int64Value ?? 0

    guard threshold.isFinite, threshold >= 0.0, threshold <= 1.0 else {
      result(
        FlutterError(
          code: "invalid_silence_threshold",
          message: "Silence detection threshold must be a finite value between 0.0 and 1.0.",
          details: nil
        )
      )
      return
    }

    guard durationMs > 0 else {
      result(
        FlutterError(
          code: "invalid_silence_duration",
          message: "Silence detection duration must be greater than 0 milliseconds.",
          details: nil
        )
      )
      return
    }

    stateLock.lock()
    switch flow {
    case .output:
      outputSilenceDetectionEnabled = true
      outputSilenceThreshold = threshold
      outputSilenceDurationNanos = UInt64(durationMs) * 1_000_000
      outputSilenceCandidateStartUptimeNanos = 0
      outputSilenceIsActive = false
    case .input:
      inputSilenceDetectionEnabled = true
      inputSilenceThreshold = threshold
      inputSilenceDurationNanos = UInt64(durationMs) * 1_000_000
      inputSilenceCandidateStartUptimeNanos = 0
      inputSilenceIsActive = false
    }
    stateLock.unlock()
    syncCaptureState(flow: flow)
    result(nil)
  }

  private func setRequestedRunning(flow: AudioFlow, running: Bool) {
    stateLock.lock()
    switch flow {
    case .output:
      outputRequestedRunning = running
    case .input:
      inputRequestedRunning = running
    }
    stateLock.unlock()
  }

  private func isCaptureActive(flow: AudioFlow) -> Bool {
    stateLock.lock()
    let active = flow == .output ? outputCaptureActive : inputCaptureActive
    stateLock.unlock()
    return active
  }

  private func setSelectedDevice(flow: AudioFlow, arguments: Any?) {
    let args = arguments as? [String: Any]
    let deviceId = (args?["deviceId"] as? String) ?? ""
    var selectedDeviceName = ""
    if !deviceId.isEmpty {
      if let device = enumerateDevices(flow: flow).first(where: { $0.id == deviceId }) {
        selectedDeviceName = device.name
      }
    }

    stateLock.lock()
    switch flow {
    case .output:
      selectedOutputDeviceId = deviceId
      selectedOutputDeviceName = selectedDeviceName
      clearCurrentDevice(flow: .output)
    case .input:
      selectedInputDeviceId = deviceId
      selectedInputDeviceName = selectedDeviceName
      clearCurrentDevice(flow: .input)
    }
    stateLock.unlock()
  }

  private func syncCaptureState(flow: AudioFlow, forceRestart: Bool = false) {
    stateLock.lock()
    let shouldRun = requestedRunning(flow: flow) && listenerActive(flow: flow)
    let active = captureActive(flow: flow)
    stateLock.unlock()

    if !shouldRun {
      stopCapture(flow: flow)
      return
    }

    if forceRestart && active {
      stopCapture(flow: flow)
    }

    stateLock.lock()
    let stillActive = captureActive(flow: flow)
    stateLock.unlock()
    if stillActive {
      return
    }

    startCapture(flow: flow)
  }

  private func requestedRunning(flow: AudioFlow) -> Bool {
    flow == .output ? outputRequestedRunning : inputRequestedRunning
  }

  private func listenerActive(flow: AudioFlow) -> Bool {
    if flow == .output {
      return outputListenerActive || (silenceListenerActive && outputSilenceDetectionEnabled)
    }
    return inputListenerActive || (silenceListenerActive && inputSilenceDetectionEnabled)
  }

  private func captureActive(flow: AudioFlow) -> Bool {
    flow == .output ? outputCaptureActive : inputCaptureActive
  }

  private func startCapture(flow: AudioFlow) {
    switch flow {
    case .output:
      startOutputCapture()
    case .input:
      startInputCapture()
    }
  }

  private func stopCapture(flow: AudioFlow) {
    switch flow {
    case .output:
      stopOutputCapture()
    case .input:
      stopInputCapture()
    }
  }

  private func startOutputCapture() {
    guard #available(macOS 14.2, *) else {
      emitError(
        flow: .output,
        code: "unsupported_macos_version",
        message: "System audio metering on macOS requires Core Audio taps and macOS 14.2 or newer."
      )
      return
    }

    guard let device = resolveRequestedDevice(flow: .output) else {
      emitError(flow: .output, code: "no_output_device", message: "No active macOS output device is available for metering.")
      return
    }

    do {
      let tapContext = try createTap(for: device)
      let aggregateContext = try createAggregateDevice(for: device, tapUID: tapContext.tapUID)

      var ioProcId: AudioDeviceIOProcID?
      let createIoProcStatus = AudioDeviceCreateIOProcID(
        aggregateContext.deviceId,
        outputTapIOProc,
        Unmanaged.passUnretained(self).toOpaque(),
        &ioProcId
      )
      guard createIoProcStatus == noErr, let ioProcId else {
        destroyAggregateDevice(id: aggregateContext.deviceId)
        destroyTap(id: tapContext.tapObjectId)
        emitError(
          flow: .output,
          code: "aggregate_ioproc_create_failed",
          message: "Failed to register a CoreAudio IO callback for the aggregate tap device."
        )
        return
      }

      let startStatus = AudioDeviceStart(aggregateContext.deviceId, ioProcId)
      guard startStatus == noErr else {
        AudioDeviceDestroyIOProcID(aggregateContext.deviceId, ioProcId)
        destroyAggregateDevice(id: aggregateContext.deviceId)
        destroyTap(id: tapContext.tapObjectId)
        emitError(
          flow: .output,
          code: "aggregate_device_start_failed",
          message: "Failed to start the aggregate tap device for macOS system audio metering."
        )
        return
      }

      stateLock.lock()
      outputIoProcId = ioProcId
      outputRunningAggregateDeviceId = aggregateContext.deviceId
      outputTapObjectId = tapContext.tapObjectId
      outputStreamFormat = tapContext.streamFormat
      outputPendingLeftPeak = 0.0
      outputPendingRightPeak = 0.0
      outputLastEmitUptimeNanos = 0
      setCurrentDevice(device, flow: .output)
      outputCaptureActive = true
      stateLock.unlock()
      prepareInitialSilenceDetection(flow: .output)
    } catch let error as CaptureSetupError {
      emitError(flow: .output, code: error.code, message: error.message)
    } catch {
      emitError(flow: .output, code: "capture_setup_failed", message: "\(error)")
    }
  }

  private func stopOutputCapture() {
    stateLock.lock()
    let ioProcId = outputIoProcId
    let aggregateDeviceId = outputRunningAggregateDeviceId
    let tapObjectId = outputTapObjectId
    outputIoProcId = nil
    outputRunningAggregateDeviceId = 0
    outputTapObjectId = 0
    outputStreamFormat = AudioStreamBasicDescription()
    outputPendingLeftPeak = 0.0
    outputPendingRightPeak = 0.0
    outputLastEmitUptimeNanos = 0
    outputCaptureActive = false
    clearCurrentDevice(flow: .output)
    stateLock.unlock()
    resetSilenceDetectionState(flow: .output, preserveConfiguration: true)

    if let ioProcId, aggregateDeviceId != 0 {
      AudioDeviceStop(aggregateDeviceId, ioProcId)
      AudioDeviceDestroyIOProcID(aggregateDeviceId, ioProcId)
    }
    if #available(macOS 14.2, *) {
      if aggregateDeviceId != 0 {
        destroyAggregateDevice(id: aggregateDeviceId)
      }
      if tapObjectId != 0 {
        destroyTap(id: tapObjectId)
      }
    }
  }

  private func startInputCapture() {
    guard let device = resolveRequestedDevice(flow: .input) else {
      emitError(flow: .input, code: "no_input_device", message: "No active macOS input device is available for metering.")
      return
    }

    guard let streamFormat = readDeviceStreamFormat(for: device.audioDeviceId, flow: .input) else {
      emitError(
        flow: .input,
        code: "stream_format_failed",
        message: "Failed to read the CoreAudio stream format for the selected input device."
      )
      return
    }

    var ioProcId: AudioDeviceIOProcID?
    let createStatus = AudioDeviceCreateIOProcID(
      device.audioDeviceId,
      inputDeviceIOProc,
      Unmanaged.passUnretained(self).toOpaque(),
      &ioProcId
    )
    guard createStatus == noErr, let ioProcId else {
      emitError(
        flow: .input,
        code: "input_ioproc_create_failed",
        message: "Failed to register a CoreAudio IO callback for the selected input device."
      )
      return
    }

    let startStatus = AudioDeviceStart(device.audioDeviceId, ioProcId)
    guard startStatus == noErr else {
      AudioDeviceDestroyIOProcID(device.audioDeviceId, ioProcId)
      emitError(
        flow: .input,
        code: "input_device_start_failed",
        message: "Failed to start CoreAudio metering for the selected input device."
      )
      return
    }

    stateLock.lock()
    inputIoProcId = ioProcId
    inputRunningDeviceId = device.audioDeviceId
    inputStreamFormat = streamFormat
    inputPendingLeftPeak = 0.0
    inputPendingRightPeak = 0.0
    inputLastEmitUptimeNanos = 0
    setCurrentDevice(device, flow: .input)
    inputCaptureActive = true
    stateLock.unlock()
    prepareInitialSilenceDetection(flow: .input)
  }

  private func stopInputCapture() {
    stateLock.lock()
    let ioProcId = inputIoProcId
    let runningDeviceId = inputRunningDeviceId
    inputIoProcId = nil
    inputRunningDeviceId = 0
    inputStreamFormat = AudioStreamBasicDescription()
    inputPendingLeftPeak = 0.0
    inputPendingRightPeak = 0.0
    inputLastEmitUptimeNanos = 0
    inputCaptureActive = false
    clearCurrentDevice(flow: .input)
    stateLock.unlock()

    if let ioProcId, runningDeviceId != 0 {
      AudioDeviceStop(runningDeviceId, ioProcId)
      AudioDeviceDestroyIOProcID(runningDeviceId, ioProcId)
    }
    resetSilenceDetectionState(flow: .input, preserveConfiguration: true)
  }

  fileprivate func handleAudioCallback(
    flow: AudioFlow,
    inputData: UnsafePointer<AudioBufferList>?
  ) -> OSStatus {
    guard let inputData else {
      return noErr
    }

    stateLock.lock()
    let streamFormat = flow == .output ? outputStreamFormat : inputStreamFormat
    let currentDeviceId = flow == .output ? currentOutputDeviceId : currentInputDeviceId
    let currentDeviceName = flow == .output ? currentOutputDeviceName : currentInputDeviceName
    let sink = flow == .output ? outputEventSink : inputEventSink
    stateLock.unlock()

    let peaks = computeStereoPeaks(
      from: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData)),
      streamFormat: streamFormat
    )
    let now = DispatchTime.now().uptimeNanoseconds

    var leftToEmit = 0.0
    var rightToEmit = 0.0
    var shouldEmit = false

    stateLock.lock()
    switch flow {
    case .output:
      outputPendingLeftPeak = max(outputPendingLeftPeak, peaks.left)
      outputPendingRightPeak = max(outputPendingRightPeak, peaks.right)
      shouldEmit = outputLastEmitUptimeNanos == 0 ||
        now &- outputLastEmitUptimeNanos >= kEmitIntervalNanos
      if shouldEmit {
        leftToEmit = outputPendingLeftPeak
        rightToEmit = outputPendingRightPeak
        outputPendingLeftPeak = 0.0
        outputPendingRightPeak = 0.0
        outputLastEmitUptimeNanos = now
      }
    case .input:
      inputPendingLeftPeak = max(inputPendingLeftPeak, peaks.left)
      inputPendingRightPeak = max(inputPendingRightPeak, peaks.right)
      shouldEmit = inputLastEmitUptimeNanos == 0 ||
        now &- inputLastEmitUptimeNanos >= kEmitIntervalNanos
      if shouldEmit {
        leftToEmit = inputPendingLeftPeak
        rightToEmit = inputPendingRightPeak
        inputPendingLeftPeak = 0.0
        inputPendingRightPeak = 0.0
        inputLastEmitUptimeNanos = now
      }
    }
    stateLock.unlock()

    guard shouldEmit, let sink else {
      if shouldEmit {
        processSilenceDetection(
          flow: flow,
          peakLevel: max(leftToEmit, rightToEmit),
          nowUptimeNanos: now,
          deviceId: currentDeviceId,
          deviceName: currentDeviceName
        )
      }
      return noErr
    }

    processSilenceDetection(
      flow: flow,
      peakLevel: max(leftToEmit, rightToEmit),
      nowUptimeNanos: now,
      deviceId: currentDeviceId,
      deviceName: currentDeviceName
    )

    DispatchQueue.main.async {
      var payload: [String: Any] = [
        "leftPeak": leftToEmit,
        "rightPeak": rightToEmit,
        "timestamp": Int64(Date().timeIntervalSince1970 * 1000.0),
      ]
      if flow == .output {
        payload["outputDeviceId"] = currentDeviceId
        payload["outputDeviceName"] = currentDeviceName
      } else {
        payload["inputDeviceId"] = currentDeviceId
        payload["inputDeviceName"] = currentDeviceName
      }
      sink(payload)
    }

    return noErr
  }

  private func processSilenceDetection(
    flow: AudioFlow,
    peakLevel: Double,
    nowUptimeNanos: UInt64,
    deviceId: String,
    deviceName: String
  ) {
    stateLock.lock()
    let isEnabled: Bool
    let threshold: Double
    let durationNanos: UInt64
    var candidateStart: UInt64
    var isActive: Bool
    switch flow {
    case .output:
      isEnabled = outputSilenceDetectionEnabled
      threshold = outputSilenceThreshold
      durationNanos = outputSilenceDurationNanos
      candidateStart = outputSilenceCandidateStartUptimeNanos
      isActive = outputSilenceIsActive
    case .input:
      isEnabled = inputSilenceDetectionEnabled
      threshold = inputSilenceThreshold
      durationNanos = inputSilenceDurationNanos
      candidateStart = inputSilenceCandidateStartUptimeNanos
      isActive = inputSilenceIsActive
    }
    guard isEnabled else {
      stateLock.unlock()
      return
    }

    let clampedPeak = clampPeak(peakLevel)
    var eventType: String?
    let sink = silenceEventSink

    if clampedPeak < threshold {
      if !isActive {
        if candidateStart == 0 {
          candidateStart = nowUptimeNanos
        } else if nowUptimeNanos &- candidateStart >= durationNanos {
          isActive = true
          candidateStart = 0
          eventType = "silenceStarted"
        }
      }
    } else {
      candidateStart = 0
      if isActive {
        isActive = false
        eventType = "silenceEnded"
      }
    }

    switch flow {
    case .output:
      outputSilenceCandidateStartUptimeNanos = candidateStart
      outputSilenceIsActive = isActive
    case .input:
      inputSilenceCandidateStartUptimeNanos = candidateStart
      inputSilenceIsActive = isActive
    }
    stateLock.unlock()

    guard let eventType, let sink else {
      return
    }

    DispatchQueue.main.async {
      sink([
        "type": eventType,
        "flow": flow == .input ? "input" : "output",
        "peakLevel": clampedPeak,
        "timestamp": Int64(Date().timeIntervalSince1970 * 1000.0),
        "deviceId": deviceId,
        "deviceName": deviceName,
      ])
    }
  }

  private func resetSilenceDetectionState(flow: AudioFlow, preserveConfiguration: Bool) {
    stateLock.lock()
    switch flow {
    case .output:
      outputSilenceBootstrapTimer?.cancel()
      outputSilenceBootstrapTimer = nil
      outputSilenceCandidateStartUptimeNanos = 0
      outputSilenceIsActive = false
      if !preserveConfiguration {
        outputSilenceDetectionEnabled = false
        outputSilenceThreshold = 0.0
        outputSilenceDurationNanos = 0
      }
    case .input:
      inputSilenceBootstrapTimer?.cancel()
      inputSilenceBootstrapTimer = nil
      inputSilenceCandidateStartUptimeNanos = 0
      inputSilenceIsActive = false
      if !preserveConfiguration {
        inputSilenceDetectionEnabled = false
        inputSilenceThreshold = 0.0
        inputSilenceDurationNanos = 0
      }
    }
    stateLock.unlock()
  }

  private func prepareInitialSilenceDetection(flow: AudioFlow) {
    stateLock.lock()
    let now = DispatchTime.now().uptimeNanoseconds
    let enabled: Bool
    let durationNanos: UInt64
    switch flow {
    case .output:
      guard outputSilenceDetectionEnabled else {
        stateLock.unlock()
        return
      }
      outputSilenceCandidateStartUptimeNanos = now
      outputSilenceIsActive = false
      outputSilenceBootstrapTimer?.cancel()
      outputSilenceBootstrapTimer = nil
      enabled = outputSilenceDetectionEnabled
      durationNanos = outputSilenceDurationNanos
    case .input:
      guard inputSilenceDetectionEnabled else {
        stateLock.unlock()
        return
      }
      inputSilenceCandidateStartUptimeNanos = now
      inputSilenceIsActive = false
      inputSilenceBootstrapTimer?.cancel()
      inputSilenceBootstrapTimer = nil
      enabled = inputSilenceDetectionEnabled
      durationNanos = inputSilenceDurationNanos
    }
    stateLock.unlock()

    guard enabled, durationNanos > 0 else {
      return
    }

    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
    timer.schedule(deadline: .now() + .nanoseconds(Int(durationNanos)))
    timer.setEventHandler { [weak self] in
      self?.emitInitialSilenceIfNeeded(flow: flow)
    }
    timer.resume()

    stateLock.lock()
    switch flow {
    case .output:
      outputSilenceBootstrapTimer = timer
    case .input:
      inputSilenceBootstrapTimer = timer
    }
    stateLock.unlock()
  }

  private func emitInitialSilenceIfNeeded(flow: AudioFlow) {
    stateLock.lock()
    let now = DispatchTime.now().uptimeNanoseconds
    let sink = silenceEventSink
    let candidateStart: UInt64
    let durationNanos: UInt64
    let enabled: Bool
    let isActive: Bool
    let deviceId: String
    let deviceName: String

    switch flow {
    case .output:
      outputSilenceBootstrapTimer = nil
      candidateStart = outputSilenceCandidateStartUptimeNanos
      durationNanos = outputSilenceDurationNanos
      enabled = outputSilenceDetectionEnabled
      isActive = outputSilenceIsActive
      deviceId = currentOutputDeviceId
      deviceName = currentOutputDeviceName
      if enabled && !isActive && candidateStart != 0 &&
          now &- candidateStart >= durationNanos {
        outputSilenceIsActive = true
        outputSilenceCandidateStartUptimeNanos = 0
      } else {
        stateLock.unlock()
        return
      }
    case .input:
      inputSilenceBootstrapTimer = nil
      candidateStart = inputSilenceCandidateStartUptimeNanos
      durationNanos = inputSilenceDurationNanos
      enabled = inputSilenceDetectionEnabled
      isActive = inputSilenceIsActive
      deviceId = currentInputDeviceId
      deviceName = currentInputDeviceName
      if enabled && !isActive && candidateStart != 0 &&
          now &- candidateStart >= durationNanos {
        inputSilenceIsActive = true
        inputSilenceCandidateStartUptimeNanos = 0
      } else {
        stateLock.unlock()
        return
      }
    }
    stateLock.unlock()

    guard let sink else {
      return
    }

    sink([
      "type": "silenceStarted",
      "flow": flow == .input ? "input" : "output",
      "peakLevel": 0.0,
      "timestamp": Int64(Date().timeIntervalSince1970 * 1000.0),
      "deviceId": deviceId,
      "deviceName": deviceName,
    ])
  }

  @available(macOS 14.2, *)
  private func createTap(for device: AudioDeviceInfo) throws -> TapContext {
    let streamIds: [AudioStreamID] = readPropertyArray(
      objectId: device.audioDeviceId,
      address: propertyAddress(
        selector: kAudioDevicePropertyStreams,
        scope: kAudioDevicePropertyScopeOutput
      ),
      type: AudioStreamID.self
    ) ?? []
    guard !streamIds.isEmpty else {
      throw CaptureSetupError(
        code: "no_output_streams",
        message: "The selected macOS output device does not expose an output stream for system metering."
      )
    }

    let tapDescription = CATapDescription(
      excludingProcesses: [],
      deviceUID: device.id,
      stream: 0
    )
    tapDescription.name = "System Audio Meter Tap"
    tapDescription.isPrivate = true
    tapDescription.muteBehavior = .unmuted

    var tapObjectId = AudioObjectID(kAudioObjectUnknown)
    let createStatus = AudioHardwareCreateProcessTap(tapDescription, &tapObjectId)
    guard createStatus == noErr, tapObjectId != AudioObjectID(kAudioObjectUnknown) else {
      throw CaptureSetupError(
        code: "tap_create_failed",
        message: "Failed to create the Core Audio process tap for the selected output device."
      )
    }

    guard
      let tapUID = readStringProperty(
        objectId: tapObjectId,
        address: propertyAddress(
          selector: kAudioTapPropertyUID,
          scope: kAudioObjectPropertyScopeGlobal
        )
      )
    else {
      destroyTap(id: tapObjectId)
      throw CaptureSetupError(
        code: "tap_uid_failed",
        message: "Failed to read the Core Audio tap identifier for the selected output device."
      )
    }

    guard
      let streamFormat: AudioStreamBasicDescription = readProperty(
        objectId: tapObjectId,
        address: propertyAddress(
          selector: kAudioTapPropertyFormat,
          scope: kAudioObjectPropertyScopeGlobal
        ),
        type: AudioStreamBasicDescription.self
      )
    else {
      destroyTap(id: tapObjectId)
      throw CaptureSetupError(
        code: "tap_format_failed",
        message: "Failed to read the Core Audio tap stream format for the selected output device."
      )
    }

    return TapContext(
      tapObjectId: tapObjectId,
      tapUID: tapUID,
      streamFormat: streamFormat
    )
  }

  @available(macOS 14.2, *)
  private func createAggregateDevice(for device: AudioDeviceInfo, tapUID: String) throws
    -> AggregateContext
  {
    let aggregateUID = "com.openai.system_audio_meter.aggregate.\(UUID().uuidString)"
    let aggregateDescription: [String: Any] = [
      kAggregateDescriptionNameKey: "System Audio Meter Aggregate",
      kAggregateDescriptionUIDKey: aggregateUID,
      kAggregateDescriptionIsPrivateKey: 1,
      kAggregateDescriptionIsStackedKey: 0,
      kAggregateDescriptionTapAutoStartKey: 1,
      kAggregateDescriptionMainSubDeviceKey: device.id,
      kAggregateDescriptionSubDeviceListKey: [
        [kAggregateSubDeviceUIDKey: device.id]
      ],
      kAggregateDescriptionTapListKey: [
        [
          kAggregateSubTapUIDKey: tapUID,
          kAggregateSubTapDriftCompensationKey: 0,
        ]
      ],
    ]

    var aggregateDeviceId = AudioObjectID(0)
    let createStatus = AudioHardwareCreateAggregateDevice(
      aggregateDescription as CFDictionary,
      &aggregateDeviceId
    )
    guard createStatus == noErr, aggregateDeviceId != 0 else {
      throw CaptureSetupError(
        code: "aggregate_create_failed",
        message: "Failed to create the private aggregate device required for macOS system audio metering."
      )
    }

    return AggregateContext(deviceId: aggregateDeviceId)
  }

  @available(macOS 14.2, *)
  private func destroyAggregateDevice(id: AudioObjectID) {
    AudioHardwareDestroyAggregateDevice(id)
  }

  @available(macOS 14.2, *)
  private func destroyTap(id: AudioObjectID) {
    AudioHardwareDestroyProcessTap(id)
  }

  private func resolveRequestedDevice(flow: AudioFlow) -> AudioDeviceInfo? {
    let devices = enumerateDevices(flow: flow)

    stateLock.lock()
    let selectedId = flow == .output ? selectedOutputDeviceId : selectedInputDeviceId
    let selectedName = flow == .output ? selectedOutputDeviceName : selectedInputDeviceName
    stateLock.unlock()

    if !selectedId.isEmpty {
      if let exactMatch = devices.first(where: { $0.id == selectedId }) {
        return exactMatch
      }
      if !selectedName.isEmpty {
        if let nameMatch = devices.first(where: { $0.name == selectedName }) {
          return nameMatch
        }
      }
      return nil
    }

    if let defaultDevice = devices.first(where: { $0.isDefault }) {
      return defaultDevice
    }
    return devices.first
  }

  private func resolveCurrentDevice(flow: AudioFlow) -> AudioDeviceInfo? {
    let devices = enumerateDevices(flow: flow)

    stateLock.lock()
    let currentId = flow == .output ? currentOutputDeviceId : currentInputDeviceId
    let currentName = flow == .output ? currentOutputDeviceName : currentInputDeviceName
    let currentIsDefault = flow == .output ? currentOutputDeviceIsDefault : currentInputDeviceIsDefault
    let selectedId = flow == .output ? selectedOutputDeviceId : selectedInputDeviceId
    let selectedName = flow == .output ? selectedOutputDeviceName : selectedInputDeviceName
    stateLock.unlock()

    if !currentId.isEmpty {
      return AudioDeviceInfo(
        audioDeviceId: 0,
        id: currentId,
        name: currentName.isEmpty ? unknownDeviceName(flow: flow) : currentName,
        isDefault: currentIsDefault
      )
    }

    if !selectedId.isEmpty {
      if let exactMatch = devices.first(where: { $0.id == selectedId }) {
        return exactMatch
      }
      if !selectedName.isEmpty {
        if let nameMatch = devices.first(where: { $0.name == selectedName }) {
          return nameMatch
        }
      }
    }

    if let defaultDevice = devices.first(where: { $0.isDefault }) {
      return defaultDevice
    }
    return devices.first
  }

  private func enumerateDevices(flow: AudioFlow) -> [AudioDeviceInfo] {
    let scope: AudioObjectPropertyScope = flow == .output
      ? kAudioDevicePropertyScopeOutput
      : kAudioDevicePropertyScopeInput
    let defaultDeviceId = readDefaultDeviceId(flow: flow)
    let deviceIds: [AudioDeviceID] = readPropertyArray(
      objectId: AudioObjectID(kAudioObjectSystemObject),
      address: propertyAddress(
        selector: kAudioHardwarePropertyDevices,
        scope: kAudioObjectPropertyScopeGlobal
      ),
      type: AudioDeviceID.self
    ) ?? []

    return deviceIds.compactMap { deviceId in
      guard deviceSupportsIO(deviceId, scope: scope) else {
        return nil
      }
      let deviceUid = readStringProperty(
        objectId: deviceId,
        address: propertyAddress(
          selector: kAudioDevicePropertyDeviceUID,
          scope: kAudioObjectPropertyScopeGlobal
        )
      ) ?? "\(deviceId)"
      if deviceUid.hasPrefix(kAggregateDeviceUIDPrefix) {
        return nil
      }
      let deviceName = readStringProperty(
        objectId: deviceId,
        address: propertyAddress(
          selector: kAudioObjectPropertyName,
          scope: kAudioObjectPropertyScopeGlobal
        )
      ) ?? unknownDeviceName(flow: flow)
      return AudioDeviceInfo(
        audioDeviceId: deviceId,
        id: deviceUid,
        name: deviceName,
        isDefault: deviceId == defaultDeviceId
      )
    }
  }

  fileprivate func handleDevicePropertyChanges(_ addresses: [AudioObjectPropertyAddress]) {
    DispatchQueue.main.async {
      var outputDefaultChanged = false
      var inputDefaultChanged = false
      var devicesChanged = false

      for address in addresses {
        switch address.mSelector {
        case kAudioHardwarePropertyDevices, kAudioHardwarePropertyServiceRestarted:
          devicesChanged = true
        case kAudioHardwarePropertyDefaultOutputDevice:
          outputDefaultChanged = true
        case kAudioHardwarePropertyDefaultInputDevice:
          inputDefaultChanged = true
        default:
          break
        }
      }

      if devicesChanged || outputDefaultChanged {
        self.refreshDevices(flow: .output, defaultDeviceChanged: outputDefaultChanged)
      }
      if devicesChanged || inputDefaultChanged {
        self.refreshDevices(flow: .input, defaultDeviceChanged: inputDefaultChanged)
      }
    }
  }

  private func refreshDevices(flow: AudioFlow, defaultDeviceChanged: Bool) {
    let newDevices = Dictionary(uniqueKeysWithValues: enumerateDevices(flow: flow).map { ($0.id, $0) })

    stateLock.lock()
    let oldDevices = flow == .output ? knownOutputDevices : knownInputDevices
    if flow == .output {
      knownOutputDevices = newDevices
    } else {
      knownInputDevices = newDevices
    }
    let selectedId = flow == .output ? selectedOutputDeviceId : selectedInputDeviceId
    let currentId = flow == .output ? currentOutputDeviceId : currentInputDeviceId
    let isRunning = requestedRunning(flow: flow) && listenerActive(flow: flow)
    stateLock.unlock()

    let removedIds = Set(oldDevices.keys).subtracting(newDevices.keys)
    let addedIds = Set(newDevices.keys).subtracting(oldDevices.keys)

    for deviceId in addedIds {
      if let device = newDevices[deviceId] {
        emitDeviceEvent(
          flow: flow,
          kind: "connected",
          deviceId: device.id,
          deviceName: device.name,
          isDefault: device.isDefault,
          isSelected: !selectedId.isEmpty && selectedId == device.id
        )
      }
    }

    for deviceId in removedIds {
      let previous = oldDevices[deviceId]
      emitDeviceEvent(
        flow: flow,
        kind: "disconnected",
        deviceId: previous?.id ?? deviceId,
        deviceName: previous?.name ?? unknownDeviceName(flow: flow),
        isDefault: previous?.isDefault ?? false,
        isSelected: !selectedId.isEmpty && selectedId == deviceId
      )
    }

    guard isRunning else {
      return
    }

    var shouldRestart = false
    if defaultDeviceChanged && selectedId.isEmpty {
      shouldRestart = true
    }
    if !currentId.isEmpty && (removedIds.contains(currentId) || addedIds.contains(currentId)) {
      shouldRestart = true
    }
    if !selectedId.isEmpty && (removedIds.contains(selectedId) || addedIds.contains(selectedId)) {
      shouldRestart = true
    }
    if currentId.isEmpty && !addedIds.isEmpty {
      shouldRestart = true
    }

    if shouldRestart {
      syncCaptureState(flow: flow, forceRestart: true)
    }
  }

  private func emitDeviceEvent(
    flow: AudioFlow,
    kind: String,
    deviceId: String,
    deviceName: String,
    isDefault: Bool,
    isSelected: Bool
  ) {
    stateLock.lock()
    let sink = deviceEventSink
    stateLock.unlock()
    guard let sink else {
      return
    }

    DispatchQueue.main.async {
      sink([
        "kind": kind,
        "flow": flow == .input ? "input" : "output",
        "timestamp": Int64(Date().timeIntervalSince1970 * 1000.0),
        "deviceId": deviceId,
        "deviceName": deviceName,
        "isDefault": isDefault,
        "isSelected": isSelected,
      ])
    }
  }

  private func emitError(flow: AudioFlow, code: String, message: String) {
    stateLock.lock()
    let sink = flow == .output ? outputEventSink : inputEventSink
    stateLock.unlock()

    guard let sink else {
      return
    }

    DispatchQueue.main.async {
      sink(
        FlutterError(
          code: code,
          message: message,
          details: nil
        )
      )
    }
  }

  private func registerDeviceNotifications() {
    let objectId = AudioObjectID(kAudioObjectSystemObject)
    let addresses = [
      propertyAddress(selector: kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal),
      propertyAddress(selector: kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal),
      propertyAddress(selector: kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal),
      propertyAddress(selector: kAudioHardwarePropertyServiceRestarted, scope: kAudioObjectPropertyScopeGlobal),
    ]

    for var address in addresses {
      AudioObjectAddPropertyListener(
        objectId,
        &address,
        devicePropertyListener,
        Unmanaged.passUnretained(self).toOpaque()
      )
    }
  }

  private func unregisterDeviceNotifications() {
    let objectId = AudioObjectID(kAudioObjectSystemObject)
    let addresses = [
      propertyAddress(selector: kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal),
      propertyAddress(selector: kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal),
      propertyAddress(selector: kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal),
      propertyAddress(selector: kAudioHardwarePropertyServiceRestarted, scope: kAudioObjectPropertyScopeGlobal),
    ]

    for var address in addresses {
      AudioObjectRemovePropertyListener(
        objectId,
        &address,
        devicePropertyListener,
        Unmanaged.passUnretained(self).toOpaque()
      )
    }
  }

  private func readDefaultDeviceId(flow: AudioFlow) -> AudioDeviceID {
    var deviceId = AudioDeviceID(0)
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    let selector = flow == .output
      ? kAudioHardwarePropertyDefaultOutputDevice
      : kAudioHardwarePropertyDefaultInputDevice
    var address = propertyAddress(selector: selector, scope: kAudioObjectPropertyScopeGlobal)

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &dataSize,
      &deviceId
    )
    return status == noErr ? deviceId : 0
  }

  private func readDeviceStreamFormat(for deviceId: AudioDeviceID, flow: AudioFlow)
    -> AudioStreamBasicDescription?
  {
    let scope: AudioObjectPropertyScope = flow == .output
      ? kAudioDevicePropertyScopeOutput
      : kAudioDevicePropertyScopeInput
    let streamIds: [AudioStreamID] = readPropertyArray(
      objectId: deviceId,
      address: propertyAddress(selector: kAudioDevicePropertyStreams, scope: scope),
      type: AudioStreamID.self
    ) ?? []

    for streamId in streamIds {
      if let format: AudioStreamBasicDescription = readProperty(
        objectId: streamId,
        address: propertyAddress(
          selector: kAudioStreamPropertyVirtualFormat,
          scope: kAudioObjectPropertyScopeGlobal
        ),
        type: AudioStreamBasicDescription.self
      ) {
        return format
      }
    }

    return readProperty(
      objectId: deviceId,
      address: propertyAddress(
        selector: kAudioDevicePropertyStreamFormat,
        scope: scope
      ),
      type: AudioStreamBasicDescription.self
    )
  }

  private func deviceSupportsIO(_ deviceId: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
    var address = propertyAddress(
      selector: kAudioDevicePropertyStreamConfiguration,
      scope: scope
    )
    var dataSize: UInt32 = 0

    let sizeStatus = AudioObjectGetPropertyDataSize(deviceId, &address, 0, nil, &dataSize)
    guard sizeStatus == noErr, dataSize >= UInt32(MemoryLayout<AudioBufferList>.size) else {
      return false
    }

    let rawBuffer = UnsafeMutableRawPointer.allocate(
      byteCount: Int(dataSize),
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { rawBuffer.deallocate() }

    let dataStatus = AudioObjectGetPropertyData(deviceId, &address, 0, nil, &dataSize, rawBuffer)
    guard dataStatus == noErr else {
      return false
    }

    let audioBufferList = UnsafeMutableAudioBufferListPointer(
      rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
    )
    let channelCount = audioBufferList.reduce(0) { partialResult, buffer in
      partialResult + Int(buffer.mNumberChannels)
    }
    return channelCount > 0
  }

  private func setCurrentDevice(_ device: AudioDeviceInfo, flow: AudioFlow) {
    switch flow {
    case .output:
      currentOutputDeviceId = device.id
      currentOutputDeviceName = device.name
      currentOutputDeviceIsDefault = device.isDefault
    case .input:
      currentInputDeviceId = device.id
      currentInputDeviceName = device.name
      currentInputDeviceIsDefault = device.isDefault
    }
  }

  private func clearCurrentDevice(flow: AudioFlow) {
    switch flow {
    case .output:
      currentOutputDeviceId = ""
      currentOutputDeviceName = ""
      currentOutputDeviceIsDefault = false
    case .input:
      currentInputDeviceId = ""
      currentInputDeviceName = ""
      currentInputDeviceIsDefault = false
    }
  }

  private func unknownDeviceName(flow: AudioFlow) -> String {
    flow == .input ? "Unknown input device" : "Unknown output device"
  }

  private func encodeDevice(_ device: AudioDeviceInfo) -> [String: Any] {
    [
      "id": device.id,
      "name": device.name,
      "isDefault": device.isDefault,
    ]
  }

  private func computeStereoPeaks(
    from audioBufferList: UnsafeMutableAudioBufferListPointer,
    streamFormat: AudioStreamBasicDescription
  ) -> (left: Double, right: Double) {
    let formatFlags = streamFormat.mFormatFlags
    let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
    let isSignedInteger = (formatFlags & kAudioFormatFlagIsSignedInteger) != 0
    let isNonInterleaved = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0
    let isBigEndian = (formatFlags & kAudioFormatFlagIsBigEndian) != 0
    let bitsPerChannel = Int(streamFormat.mBitsPerChannel)
    let channelsPerFrame = max(Int(streamFormat.mChannelsPerFrame), 1)
    let bytesPerFrame = max(Int(streamFormat.mBytesPerFrame), max(bitsPerChannel / 8, 1))
    let bytesPerSample = max(bitsPerChannel / 8, 1)

    guard (isFloat || isSignedInteger), bitsPerChannel > 0 else {
      return (0.0, 0.0)
    }

    if isNonInterleaved {
      let left = audioBufferList.count > 0
        ? peakForSingleChannelBuffer(
          audioBufferList[0],
          isFloat: isFloat,
          bitsPerChannel: bitsPerChannel,
          bytesPerSample: bytesPerSample,
          isBigEndian: isBigEndian
        ) : 0.0
      let right = audioBufferList.count > 1
        ? peakForSingleChannelBuffer(
          audioBufferList[1],
          isFloat: isFloat,
          bitsPerChannel: bitsPerChannel,
          bytesPerSample: bytesPerSample,
          isBigEndian: isBigEndian
        ) : left
      return (clampPeak(left), clampPeak(right))
    }

    guard let firstBuffer = audioBufferList.first else {
      return (0.0, 0.0)
    }
    let peaks = peakForInterleavedBuffer(
      firstBuffer,
      isFloat: isFloat,
      bitsPerChannel: bitsPerChannel,
      bytesPerFrame: bytesPerFrame,
      bytesPerSample: bytesPerSample,
      channelsPerFrame: channelsPerFrame,
      isBigEndian: isBigEndian
    )
    return (clampPeak(peaks.left), clampPeak(peaks.right))
  }

  private func peakForSingleChannelBuffer(
    _ buffer: AudioBuffer,
    isFloat: Bool,
    bitsPerChannel: Int,
    bytesPerSample: Int,
    isBigEndian: Bool
  ) -> Double {
    guard let rawData = buffer.mData else {
      return 0.0
    }

    let frameCount = Int(buffer.mDataByteSize) / bytesPerSample
    var peak = 0.0
    for frameIndex in 0..<frameCount {
      let sample = decodeSample(
        rawData: rawData,
        offset: frameIndex * bytesPerSample,
        isFloat: isFloat,
        bitsPerChannel: bitsPerChannel,
        isBigEndian: isBigEndian
      )
      peak = max(peak, abs(sample))
    }
    return peak
  }

  private func peakForInterleavedBuffer(
    _ buffer: AudioBuffer,
    isFloat: Bool,
    bitsPerChannel: Int,
    bytesPerFrame: Int,
    bytesPerSample: Int,
    channelsPerFrame: Int,
    isBigEndian: Bool
  ) -> (left: Double, right: Double) {
    guard let rawData = buffer.mData else {
      return (0.0, 0.0)
    }

    let frameCount = Int(buffer.mDataByteSize) / bytesPerFrame
    var leftPeak = 0.0
    var rightPeak = 0.0

    for frameIndex in 0..<frameCount {
      let frameOffset = frameIndex * bytesPerFrame
      let leftSample = decodeSample(
        rawData: rawData,
        offset: frameOffset,
        isFloat: isFloat,
        bitsPerChannel: bitsPerChannel,
        isBigEndian: isBigEndian
      )
      leftPeak = max(leftPeak, abs(leftSample))

      let rightChannelIndex = min(1, channelsPerFrame - 1)
      let rightSample = decodeSample(
        rawData: rawData,
        offset: frameOffset + (rightChannelIndex * bytesPerSample),
        isFloat: isFloat,
        bitsPerChannel: bitsPerChannel,
        isBigEndian: isBigEndian
      )
      rightPeak = max(rightPeak, abs(rightSample))
    }

    return (leftPeak, rightPeak)
  }

  private func decodeSample(
    rawData: UnsafeMutableRawPointer,
    offset: Int,
    isFloat: Bool,
    bitsPerChannel: Int,
    isBigEndian: Bool
  ) -> Double {
    if isFloat {
      switch bitsPerChannel {
      case 32:
        var sample = rawData.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        if isBigEndian {
          sample = UInt32(bigEndian: sample)
        }
        return Double(Float(bitPattern: sample))
      case 64:
        var sample = rawData.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
        if isBigEndian {
          sample = UInt64(bigEndian: sample)
        }
        return Double(bitPattern: sample)
      default:
        return 0.0
      }
    }

    switch bitsPerChannel {
    case 16:
      var sample = rawData.loadUnaligned(fromByteOffset: offset, as: Int16.self)
      if isBigEndian {
        sample = Int16(bigEndian: sample)
      }
      return Double(sample) / Double(Int16.max)
    case 24:
      let bytes = rawData.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
      let rawValue: Int32
      if isBigEndian {
        rawValue = (Int32(bytes[0]) << 16) | (Int32(bytes[1]) << 8) | Int32(bytes[2])
      } else {
        rawValue = (Int32(bytes[2]) << 16) | (Int32(bytes[1]) << 8) | Int32(bytes[0])
      }
      let signedValue = (rawValue & 0x80_0000) != 0 ? rawValue | ~0x00FF_FFFF : rawValue
      return Double(signedValue) / Double(0x7F_FFFF)
    case 32:
      var sample = rawData.loadUnaligned(fromByteOffset: offset, as: Int32.self)
      if isBigEndian {
        sample = Int32(bigEndian: sample)
      }
      return Double(sample) / Double(Int32.max)
    default:
      return 0.0
    }
  }

  private func clampPeak(_ value: Double) -> Double {
    guard value.isFinite else {
      return 0.0
    }
    return min(max(value, 0.0), 1.0)
  }

  private func propertyAddress(
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: scope,
      mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    )
  }

  private func readStringProperty(
    objectId: AudioObjectID,
    address: AudioObjectPropertyAddress
  ) -> String? {
    var propertyAddress = address
    var value: Unmanaged<CFString>?
    var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

    let status = AudioObjectGetPropertyData(
      objectId,
      &propertyAddress,
      0,
      nil,
      &dataSize,
      &value
    )
    guard status == noErr else {
      return nil
    }
    return value?.takeUnretainedValue() as String?
  }

  private func readProperty<T>(
    objectId: AudioObjectID,
    address: AudioObjectPropertyAddress,
    type: T.Type
  ) -> T? {
    var propertyAddress = address
    var dataSize = UInt32(MemoryLayout<T>.size)
    let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { pointer.deallocate() }

    let status = AudioObjectGetPropertyData(
      objectId,
      &propertyAddress,
      0,
      nil,
      &dataSize,
      pointer
    )
    guard status == noErr else {
      return nil
    }
    return pointer.move()
  }

  private func readPropertyArray<T>(
    objectId: AudioObjectID,
    address: AudioObjectPropertyAddress,
    type: T.Type
  ) -> [T]? {
    var propertyAddress = address
    var dataSize: UInt32 = 0

    let sizeStatus = AudioObjectGetPropertyDataSize(
      objectId,
      &propertyAddress,
      0,
      nil,
      &dataSize
    )
    guard sizeStatus == noErr, dataSize >= UInt32(MemoryLayout<T>.size) else {
      return nil
    }

    let count = Int(dataSize) / MemoryLayout<T>.size
    var values = Array<T>(unsafeUninitializedCapacity: count) { _, initializedCount in
      initializedCount = count
    }

    let readStatus = values.withUnsafeMutableBytes { bytes in
      guard let baseAddress = bytes.baseAddress else {
        return kAudioHardwareUnspecifiedError
      }
      return AudioObjectGetPropertyData(
        objectId,
        &propertyAddress,
        0,
        nil,
        &dataSize,
        baseAddress
      )
    }

    guard readStatus == noErr else {
      return nil
    }
    return values
  }
}
