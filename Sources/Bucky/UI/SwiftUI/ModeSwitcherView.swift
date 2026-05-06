import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct ModeSwitcherView: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    @FocusState.Binding var isSearchFocused: Bool
    @Namespace private var modeGlassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(LauncherMode.ordered, id: \.self) { mode in
                    if mode == model.mode {
                        activePill(for: mode)
                            .glassEffectID(mode, in: modeGlassNamespace)
                            .glassEffectTransition(.matchedGeometry)
                    } else {
                        modeOrb(for: mode)
                            .glassEffectID(mode, in: modeGlassNamespace)
                            .glassEffectTransition(.matchedGeometry)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func modeOrb(for mode: LauncherMode) -> some View {
        Button {
            _ = model.handle(command: .switchMode(mode))
        } label: {
            Image(systemName: symbol(for: mode))
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 20, height: 20)
                .padding(10)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(mode.placeholder)
    }

    @ViewBuilder
    private func activePill(for mode: LauncherMode) -> some View {
        switch mode {
        case .applications, .calculator, .dictionary:
            TextInputModePill(
                model: model,
                mode: mode,
                symbol: symbol(for: mode),
                isSearchFocused: $isSearchFocused
            )
        case .files:
            GeometryReader { proxy in
                let pathWidth = ModeSwitcherLayoutPolicy.filesPathTextWidth(
                    in: proxy.size.width,
                    path: displayedFileURL.path
                )

                HStack(spacing: ModeSwitcherLayoutPolicy.filesContentSpacing) {
                    Button {
                        try? MacFileServices().copyPathsToPasteboard([displayedFileURL])
                    } label: {
                        HStack(spacing: ModeSwitcherLayoutPolicy.filesPathIconSpacing) {
                            Image(systemName: symbol(for: mode))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: ModeSwitcherLayoutPolicy.filesPathIconWidth)

                            FadeMarqueeText(
                                text: displayedFileURL.path,
                                font: .system(size: 16, weight: .semibold),
                                constrainedWidth: pathWidth
                            )
                            .frame(width: pathWidth, height: ModeSwitcherLayoutPolicy.filesPathTextHeight, alignment: .leading)
                            .clipped()
                            .layoutPriority(0)
                        }
                        .frame(width: ModeSwitcherLayoutPolicy.filesPathButtonWidth(in: proxy.size.width), alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .clipped()
                    .layoutPriority(0)
                    .help("Copy path")

                    sortMenu
                        .layoutPriority(1)
                }
                .padding(.leading, ModeSwitcherLayoutPolicy.filesPillLeadingPadding)
                .padding(.trailing, ModeSwitcherLayoutPolicy.filesPillTrailingPadding)
                .frame(width: proxy.size.width, height: ModeSwitcherLayoutPolicy.activePillHeight, alignment: .leading)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: ModeSwitcherLayoutPolicy.activePillHeight, maxHeight: ModeSwitcherLayoutPolicy.activePillHeight)
            .layoutPriority(1)
        }
    }

    private var displayedFileURL: URL {
        if let selectedEntry = model.fileBrowserModel.selectedEntry,
           selectedEntry.kind != .directory {
            return selectedEntry.url
        }
        return model.fileBrowserModel.currentDirectory
    }

    private var sortMenu: some View {
        Picker("Sort", selection: Binding(
            get: { model.fileBrowserModel.sort },
            set: { model.fileBrowserModel.setSort($0) }
        )) {
            ForEach(FileBrowserSort.allCases, id: \.self) { sort in
                Text(sort.displayName).tag(sort)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: 128)
        .fixedSize(horizontal: true, vertical: false)
        .help("Sort files")
    }

    private func symbol(for mode: LauncherMode) -> String {
        switch mode {
        case .applications:
            return "square.grid.2x2"
        case .calculator:
            return "function"
        case .dictionary:
            return "text.book.closed"
        case .files:
            return "folder"
        }
    }
}

struct ModeSwitcherLayoutPolicy {
    static let activePillHeight: CGFloat = 48
    static let activeTextPillSpacing: CGFloat = 12
    static let activeTextPillControlHeight: CGFloat = 30
    static let activeTextPillIconWidth: CGFloat = 22
    static let activeTextPillIconHeight: CGFloat = activeTextPillControlHeight
    static let activeTextPillInputHeight: CGFloat = activeTextPillControlHeight
    static let activeTextPillInputVerticalOffset: CGFloat = 0
    static let activeTextPillCalculatorIconVerticalOffset: CGFloat = 0
    static let activeTextPillDictionaryIconVerticalOffset: CGFloat = 0
    static let filesPillLeadingPadding: CGFloat = 16
    static let filesPillTrailingPadding: CGFloat = 12
    static let filesContentSpacing: CGFloat = 12
    static let filesPathIconSpacing: CGFloat = 10
    static let filesPathIconWidth: CGFloat = 22
    static let filesPathTextHeight: CGFloat = 22
    static let filesSortMenuWidth: CGFloat = 128

    static func filesPathButtonWidth(in pillWidth: CGFloat) -> CGFloat {
        let fixedWidth = filesPillLeadingPadding
            + filesPillTrailingPadding
            + filesContentSpacing
            + filesSortMenuWidth
        return max(0, pillWidth - fixedWidth)
    }

    static func filesPathTextWidth(in pillWidth: CGFloat, path: String) -> CGFloat {
        let fixedWidth = filesPathIconWidth + filesPathIconSpacing
        return max(0, filesPathButtonWidth(in: pillWidth) - fixedWidth)
    }

    static func filesPathMarqueeWidth(in pillWidth: CGFloat) -> CGFloat {
        let fixedWidth = filesPathIconWidth + filesPathIconSpacing
        return max(0, filesPathButtonWidth(in: pillWidth) - fixedWidth)
    }

    static func activeTextPillIconVerticalOffset(for mode: LauncherMode) -> CGFloat {
        switch mode {
        case .applications, .files:
            return 0
        case .calculator:
            return activeTextPillCalculatorIconVerticalOffset
        case .dictionary:
            return activeTextPillDictionaryIconVerticalOffset
        }
    }

    static func activeTextPillEditorFrame(in bounds: CGRect, editorHeight: CGFloat) -> CGRect {
        let height = min(bounds.height, max(0, editorHeight))
        return CGRect(
            x: bounds.minX,
            y: bounds.minY + (bounds.height - height) / 2,
            width: bounds.width,
            height: height
        )
    }
}

@available(macOS 26.0, *)
private struct TextInputModePill: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    let mode: LauncherMode
    let symbol: String
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: ModeSwitcherLayoutPolicy.activeTextPillSpacing) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(
                    width: ModeSwitcherLayoutPolicy.activeTextPillIconWidth,
                    height: ModeSwitcherLayoutPolicy.activeTextPillIconHeight,
                    alignment: .center
                )
                .offset(y: ModeSwitcherLayoutPolicy.activeTextPillIconVerticalOffset(for: mode))

            CenteredLauncherTextField(
                text: $model.query,
                placeholder: mode.placeholder,
                isFocused: $isSearchFocused
            ) {
                _ = model.handle(command: .open)
            }
                .frame(
                    maxWidth: .infinity,
                    minHeight: ModeSwitcherLayoutPolicy.activeTextPillInputHeight,
                    maxHeight: ModeSwitcherLayoutPolicy.activeTextPillInputHeight,
                    alignment: .center
                )
                .layoutPriority(1)
                .offset(y: ModeSwitcherLayoutPolicy.activeTextPillInputVerticalOffset)
                .onChange(of: model.query) {
                    model.queryDidChange()
                }

            if model.isIndexing && mode == .applications {
                ProgressView()
                    .controlSize(.small)
                    .glassEffectTransition(.materialize)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .frame(
            maxWidth: .infinity,
            minHeight: ModeSwitcherLayoutPolicy.activePillHeight,
            maxHeight: ModeSwitcherLayoutPolicy.activePillHeight,
            alignment: .center
        )
        .contentShape(Capsule())
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}

@available(macOS 26.0, *)
private struct CenteredLauncherTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.cell = CenteredLauncherTextFieldCell()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.isEditable = true
        field.isSelectable = true
        field.font = Self.textFont
        field.textColor = .labelColor
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applyPlaceholder(to: field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = isFocused
        context.coordinator.onSubmit = onSubmit

        if field.stringValue != text {
            field.stringValue = text
        }
        field.font = Self.textFont
        field.textColor = .labelColor
        applyPlaceholder(to: field)
        syncFocus(for: field)
    }

    private func applyPlaceholder(to field: NSTextField) {
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: Self.textFont,
                .foregroundColor: NSColor.placeholderTextColor
            ]
        )
    }

    private func syncFocus(for field: NSTextField) {
        guard let window = field.window else { return }

        if isFocused.wrappedValue {
            guard field.currentEditor() == nil else { return }
            DispatchQueue.main.async { [weak field, weak window] in
                guard let field,
                      let window,
                      field.window === window,
                      field.currentEditor() == nil else {
                    return
                }
                window.makeFirstResponder(field)
            }
        } else if field.currentEditor() != nil {
            window.makeFirstResponder(nil)
        }
    }

    private static let textFont: NSFont = {
        let font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        if let descriptor = font.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: descriptor, size: 22) {
            return rounded
        }
        return font
    }()

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var isFocused: FocusState<Bool>.Binding
        var onSubmit: () -> Void

        init(
            text: Binding<String>,
            isFocused: FocusState<Bool>.Binding,
            onSubmit: @escaping () -> Void
        ) {
            self.text = text
            self.isFocused = isFocused
            self.onSubmit = onSubmit
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isFocused.wrappedValue = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isFocused.wrappedValue = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                text.wrappedValue = textView.string
                onSubmit()
                return true
            }
            return false
        }
    }
}

private final class CenteredLauncherTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredFrame(in: rect)
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: centeredFrame(in: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: centeredFrame(in: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }

    private func centeredFrame(in rect: NSRect) -> NSRect {
        let proposedHeight = max(cellSize.height, font?.boundingRectForFont.height ?? 0)
        return ModeSwitcherLayoutPolicy.activeTextPillEditorFrame(
            in: rect,
            editorHeight: proposedHeight
        )
    }
}

private extension FileBrowserSort {
    var displayName: String {
        switch self {
        case .name:
            return "Name"
        case .dateCreated:
            return "Date Created"
        case .dateModified:
            return "Date Modified"
        case .size:
            return "Size"
        }
    }
}
