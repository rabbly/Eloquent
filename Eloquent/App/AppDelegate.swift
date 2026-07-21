import Cocoa
import AVFoundation
import Speech

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?
    private var demoController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Design-review hook: ELOQUENT_DEMO=1 builds the full menu bar UI and plays
        // sample banners, but skips the permission/recognizer path so the UI can be
        // reviewed in isolation.
        if ProcessInfo.processInfo.environment["ELOQUENT_DEMO"] == "1" {
            var demoStats = SessionStats()
            for _ in 0..<24 { demoStats.record("um") }
            for _ in 0..<16 { demoStats.record("uh") }
            for _ in 0..<9  { demoStats.record("like") }
            let controller = StatusBarController(stats: demoStats)
            controller.update(stats: demoStats)
            demoController = controller
            runBannerDemo()
            return
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[AppDelegate] initial mic authorization status = \(micStatus.rawValue) " +
              "(0=notDetermined,1=restricted,2=denied,3=authorized)")
        requestPermissions()
    }

    private func runBannerDemo() {
        let samples: [(String, Int)] = [("um", 1), ("like", 3), ("you know", 7)]
        for (i, s) in samples.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(i) * 3.0) {
                BannerOverlay.shared.show(word: s.0, count: s.1)
            }
        }
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] micGranted in
            print("[AppDelegate] mic requestAccess granted = \(micGranted)")
            guard micGranted else {
                DispatchQueue.main.async { self?.showPermissionAlert(for: "Microphone") }
                return
            }
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                print("[AppDelegate] speech authorization status = \(status.rawValue)")
                DispatchQueue.main.async {
                    if status == .authorized {
                        self?.appController = AppController()
                    } else {
                        self?.showPermissionAlert(for: "Speech Recognition")
                    }
                }
            }
        }
    }

    private func showPermissionAlert(for permission: String) {
        let alert = NSAlert()
        alert.messageText = "\(permission) Access Required"
        alert.informativeText = "Eloquent needs \(permission) access to work. Please grant it in System Settings > Privacy & Security."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
        } else {
            NSApp.terminate(nil)
        }
    }
}
