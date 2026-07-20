import Cocoa
import AVFoundation
import Speech

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[AppDelegate] initial mic authorization status = \(micStatus.rawValue) " +
              "(0=notDetermined,1=restricted,2=denied,3=authorized)")
        requestPermissions()
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
