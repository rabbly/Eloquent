import CoreAudio
import Combine
import AppKit

@MainActor
class MicActivityWatcher: ObservableObject {
    @Published private(set) var isActive: Bool = false

    private var timer: Timer?

    init() {
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t

        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        isActive = isMonitoredAppUsingMicrophone()
    }

    // MARK: - Monitored-app mic detection (macOS 14.4+)

    private func isMonitoredAppUsingMicrophone() -> Bool {
        let prefixes = Settings.monitoredBundlePrefixes.map { $0.lowercased() }
        guard !prefixes.isEmpty else { return false }

        var listAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &listAddr, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else { return false }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](repeating: 0, count: count)
        status = processIDs.withUnsafeMutableBufferPointer { buf in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &listAddr, 0, nil, &dataSize, buf.baseAddress!
            )
        }
        guard status == noErr else { return false }

        var bundleIDAddr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var runningInputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        for processID in processIDs {
            var running: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            let runStatus = AudioObjectGetPropertyData(
                processID, &runningInputAddr, 0, nil, &runSize, &running
            )
            guard runStatus == noErr, running != 0 else { continue }

            var bundleIDCF: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let bStatus = AudioObjectGetPropertyData(
                processID, &bundleIDAddr, 0, nil, &bundleSize, &bundleIDCF
            )
            guard bStatus == noErr, let cf = bundleIDCF?.takeRetainedValue() else { continue }
            let bundleID = (cf as String).lowercased()

            if prefixes.contains(where: { bundleID.hasPrefix($0) }) {
                return true
            }
        }

        return false
    }
}
