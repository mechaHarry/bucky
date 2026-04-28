import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

final class ResultCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ResultCellView")

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let excludeButton = NSButton(title: "", target: nil, action: nil)
    private var onExclude: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildView()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    func configure(with item: LaunchItem, onExclude: @escaping () -> Void) {
        self.onExclude = onExclude
        iconView.image = NSWorkspace.shared.icon(forFile: item.url.path)
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = item.subtitle
        excludeButton.isHidden = false
        excludeButton.isEnabled = true
        updateColors()
    }

    func configure(with item: ToolItem) {
        onExclude = nil
        iconView.image = Self.icon(for: item.kind)
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = item.subtitle
        excludeButton.isHidden = true
        excludeButton.isEnabled = false
        updateColors()
    }

    private func buildView() {
        identifier = Self.reuseIdentifier

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        excludeButton.translatesAutoresizingMaskIntoConstraints = false
        excludeButton.target = self
        excludeButton.action = #selector(excludeClicked)
        applyPreferredButtonBezelStyle(excludeButton)
        excludeButton.setButtonType(.momentaryPushIn)
        excludeButton.contentTintColor = .secondaryLabelColor
        excludeButton.toolTip = "Hide"
        excludeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        if let image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide") {
            excludeButton.image = image
            excludeButton.imagePosition = .imageOnly
        } else {
            excludeButton.title = "Hide"
            excludeButton.font = .systemFont(ofSize: 11, weight: .medium)
        }

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        addSubview(iconView)
        addSubview(textStack)
        addSubview(excludeButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: excludeButton.leadingAnchor, constant: -12),

            excludeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            excludeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            excludeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
            excludeButton.heightAnchor.constraint(equalToConstant: 26)
        ])

        updateColors()
    }

    private static func icon(for kind: ToolItem.Kind) -> NSImage? {
        let symbolName: String

        switch kind {
        case .calculation:
            symbolName = "equal.circle"
        case .calculationHistory:
            symbolName = "clock.arrow.circlepath"
        case .dictionary:
            symbolName = "book"
        case .message:
            symbolName = "info.circle"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func excludeClicked() {
        onExclude?()
    }

    private func updateColors() {
        let selected = backgroundStyle == .emphasized
        titleLabel.textColor = selected ? .selectedTextColor : .labelColor
        subtitleLabel.textColor = selected ? .selectedTextColor : .secondaryLabelColor
        excludeButton.contentTintColor = selected ? .selectedTextColor : .secondaryLabelColor
    }
}
