import AppKit

@MainActor
class BannerContentView: NSViewController {
    private let wordLabel = NSTextField(labelWithString: "")
    private let visualEffect = NSVisualEffectView()

    var text: String = "" {
        didSet { wordLabel.stringValue = text }
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 64))

        // Dark translucent pill background
        visualEffect.frame = container.bounds
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.masksToBounds = true
        container.addSubview(visualEffect)

        // Label
        wordLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        wordLabel.textColor = .white
        wordLabel.alignment = .center
        wordLabel.isBezeled = false
        wordLabel.isEditable = false
        wordLabel.isSelectable = false
        wordLabel.drawsBackground = false
        wordLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wordLabel)

        NSLayoutConstraint.activate([
            wordLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            wordLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            wordLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            wordLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
        ])

        self.view = container
    }
}
