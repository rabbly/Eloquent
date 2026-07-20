import AVFoundation
import Speech

@MainActor
class AudioCaptureEngine {
    @MainActor static let shared = AudioCaptureEngine()

    var bufferHandler: ((AnalyzerInput) -> Void)?

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var configChangeObserver: NSObjectProtocol?

    private nonisolated(unsafe) static var rawTapCount = 0
    private nonisolated(unsafe) static var convertOKCount = 0
    private nonisolated(unsafe) static var convertNilCount = 0

    private init() {}

    func startCapture(targetFormat: AVAudioFormat, handler: @escaping (AnalyzerInput) -> Void) {
        bufferHandler = handler
        stop()
        // reset handler because stop() nils it
        bufferHandler = handler
        startEngine(targetFormat: targetFormat)

        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startEngine(targetFormat: targetFormat)
            }
        }
    }

    func stop() {
        if let obs = configChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            configChangeObserver = nil
        }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        bufferHandler = nil
    }

    private func startEngine(targetFormat: AVAudioFormat) {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()

        let newEngine = AVAudioEngine()
        engine = newEngine

        let inputNode = newEngine.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)
        Log.verbose("🔊 [AudioCaptureEngine] hwFormat=\(hwFormat)")

        guard hwFormat.channelCount > 0, hwFormat.sampleRate > 0 else {
            Log.info("⚠️ [AudioCaptureEngine] Invalid hardware input format — aborting.")
            return
        }

        guard let newConverter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            Log.info("❌ [AudioCaptureEngine] Cannot create converter")
            return
        }
        converter = newConverter

        let mainMixer = newEngine.mainMixerNode
        newEngine.connect(inputNode, to: mainMixer, format: hwFormat)
        mainMixer.outputVolume = 0

        let handlerRef = bufferHandler
        Log.verbose("🔊 [AudioCaptureEngine] installing tap, handler is \(handlerRef == nil ? "NIL" : "set")")

        installTap(on: inputNode, format: hwFormat, converter: newConverter)

        newEngine.prepare()
        do {
            try newEngine.start()
            Log.verbose("🔊 [AudioCaptureEngine] engine started OK, isRunning=\(newEngine.isRunning)")
        } catch {
            Log.info("❌ [AudioCaptureEngine] Failed to start: \(error)")
        }
    }

    private nonisolated func installTap(
        on inputNode: AVAudioInputNode,
        format inputFormat: AVAudioFormat,
        converter: AVAudioConverter
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            Self.rawTapCount += 1

            guard let output = Self.convert(buffer, using: converter) else {
                Self.convertNilCount += 1
                if Self.convertNilCount % 20 == 1 {
                    Log.verbose("🔊 [AudioCaptureEngine] convert returned NIL (count=\(Self.convertNilCount))")
                }
                return
            }
            Self.convertOKCount += 1
            if Self.convertOKCount % 20 == 1 {
                Log.verbose("🔊 [AudioCaptureEngine] convert OK #\(Self.convertOKCount), outFrames=\(output.frameLength)")
            }

            let input = AnalyzerInput(buffer: output)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.bufferHandler == nil {
                    Log.verbose("🔊 [AudioCaptureEngine] bufferHandler is NIL at delivery time")
                }
                self.bufferHandler?(input)
            }
        }
    }

    private nonisolated static func convert(
        _ inputBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter
    ) -> AVAudioPCMBuffer? {
        let targetFormat = converter.outputFormat
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(
                Double(inputBuffer.frameLength) * targetFormat.sampleRate / converter.inputFormat.sampleRate + 1
            )
        ) else {
            Log.verbose("🔊 [AudioCaptureEngine] failed to allocate output buffer")
            return nil
        }

        var conversionError: NSError?
        var inputConsumed = false

        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            Log.info("❌ [AudioCaptureEngine] conversion error: \(conversionError)")
            return nil
        }
        return outputBuffer.frameLength > 0 ? outputBuffer : nil
    }
}
