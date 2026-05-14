import SwiftUI

@available(macOS 26.0, *)
struct ModeSwitcherView: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    @FocusState.Binding var isSearchFocused: Bool
    @Namespace private var modeGlassNamespace
    @State private var activePillExpansionProgress: CGFloat = 1

    @ViewBuilder
    var body: some View {
        if ModeSwitcherGlassTransitionPolicy.usesOuterContainer(for: model.mode) {
            GlassEffectContainer(spacing: ModeSwitcherLayoutPolicy.modeSwitcherSpacing) {
                modeSwitcherContent
            }
        } else {
            modeSwitcherContent
        }
    }

    private var modeSwitcherContent: some View {
        GeometryReader { proxy in
            let activeFrame = ModeSwitcherLayoutPolicy.activePillFrame(
                for: model.mode,
                availableWidth: proxy.size.width,
                expansionProgress: activePillExpansionProgress
            )

            ZStack(alignment: .topLeading) {
                activePill(for: model.mode, availableWidth: proxy.size.width)
                    .frame(
                        width: activeFrame.width,
                        height: ModeSwitcherLayoutPolicy.activePillHeight
                    )
                    .offset(x: activeFrame.minX, y: 0)
                    .clipped()
                    .zIndex(ModeSwitcherLayoutPolicy.activePillZIndex)

                ForEach(LauncherMode.ordered, id: \.self) { mode in
                    if mode != model.mode {
                        modeOrb(for: mode)
                            .frame(
                                width: ModeSwitcherLayoutPolicy.inactiveStoneSlotWidth,
                                height: ModeSwitcherLayoutPolicy.activePillHeight
                            )
                            .position(
                                x: ModeSwitcherLayoutPolicy.stoneCenterX(
                                    for: mode,
                                    availableWidth: proxy.size.width
                                ),
                                y: ModeSwitcherLayoutPolicy.activePillHeight / 2
                            )
                            .glassEffectID(mode, in: modeGlassNamespace)
                            .glassEffectTransition(.matchedGeometry)
                            .zIndex(ModeSwitcherLayoutPolicy.inactiveStoneZIndex)
                    }
                }
            }
            .frame(width: proxy.size.width, height: ModeSwitcherLayoutPolicy.activePillHeight)
        }
        .frame(maxWidth: .infinity, minHeight: ModeSwitcherLayoutPolicy.activePillHeight, maxHeight: ModeSwitcherLayoutPolicy.activePillHeight)
        .onChange(of: model.mode) {
            startActivePillExpansion()
        }
    }

    private func modeOrb(for mode: LauncherMode) -> some View {
        Button {
            _ = model.handle(command: .switchMode(mode))
        } label: {
            Image(systemName: symbol(for: mode))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LauncherModeTintPolicy.inactiveOrbIconColor(for: mode))
                .frame(width: 20, height: 20)
                .padding(10)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(LauncherModeTintPolicy.inactiveOrbColor(for: mode))
        .help(helpText(for: mode))
    }

    @ViewBuilder
    private func activePill(for mode: LauncherMode, availableWidth: CGFloat) -> some View {
        switch mode {
        case .applications, .calculator, .dictionary:
            TextInputModePill(
                model: model,
                mode: mode,
                symbol: symbol(for: mode),
                glassNamespace: modeGlassNamespace,
                inputLeadingInset: ModeSwitcherLayoutPolicy.activeTextPillClearedInputLeadingInset(
                    for: mode,
                    availableWidth: availableWidth
                ),
                isSearchFocused: $isSearchFocused
            )
        case .files:
            GeometryReader { proxy in
                let pathWidth = ModeSwitcherLayoutPolicy.filesPathTextWidth(
                    in: proxy.size.width,
                    path: displayedFileURL.path
                )
                let modeTint = LauncherModeTintPolicy.activeColor(for: mode)

                HStack(spacing: ModeSwitcherLayoutPolicy.filesContentSpacing) {
                    Button {
                        try? MacFileServices().copyPathsToPasteboard([displayedFileURL])
                    } label: {
                        HStack(spacing: ModeSwitcherLayoutPolicy.filesPathIconSpacing) {
                            Image(systemName: symbol(for: mode))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(modeTint)
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
                .tint(modeTint)
                .glassEffect(
                    .regular.tint(modeTint.opacity(ModeSwitcherTintPolicy.activePillTintOpacity)).interactive(),
                    in: Capsule()
                )
                .glassEffectID(mode, in: modeGlassNamespace)
                .glassEffectTransition(.matchedGeometry)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: ModeSwitcherLayoutPolicy.activePillHeight, maxHeight: ModeSwitcherLayoutPolicy.activePillHeight)
            .layoutPriority(1)
        }
    }

    private func startActivePillExpansion() {
        activePillExpansionProgress = 0
        withAnimation(.easeOut(duration: 0.22)) {
            activePillExpansionProgress = 1
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

    private func helpText(for mode: LauncherMode) -> String {
        "\(mode.placeholder) (\(shortcutText(for: mode)))"
    }

    private func shortcutText(for mode: LauncherMode) -> String {
        switch mode {
        case .applications:
            return "Command+1"
        case .calculator:
            return "Command+2"
        case .dictionary:
            return "Command+3"
        case .files:
            return "Command+4"
        }
    }
}

struct ModeSwitcherLayoutPolicy {
    static let activePillHeight: CGFloat = 48
    static var inactiveStoneSlotWidth: CGFloat { activePillHeight }
    static var modeSwitcherSpacing: CGFloat { 10 }
    static var launcherHeaderTopInset: CGFloat { activePillHeight / 12 }
    static var launcherHeaderHorizontalInset: CGFloat { activePillHeight / 24 }
    static var launcherHeaderBottomInset: CGFloat { activePillHeight / 24 }
    static var activeTextPillHorizontalInset: CGFloat { activePillHeight / 3 }
    static var activeTextPillVerticalInset: CGFloat { activePillHeight * 3 / 16 }
    static var activeTextPillControlHeight: CGFloat { activePillHeight - activeTextPillVerticalInset * 2 }
    static var activeTextPillIconLeadingInset: CGFloat { activeTextPillHorizontalInset }
    static var activeTextPillIconWidth: CGFloat { activePillHeight / 2 }
    static var activeTextPillIconHeight: CGFloat { activeTextPillControlHeight }
    static var activeTextPillIconGlyphSize: CGFloat { activePillHeight / 2 }
    static var activeTextPillInputLeadingInset: CGFloat { activePillHeight + activePillHeight / 12 }
    static var activeTextPillInputHeight: CGFloat { activeTextPillControlHeight }
    static var activeTextPillTextFieldHeight: CGFloat { activeTextPillControlHeight }
    static var activeTextPillProgressWidth: CGFloat { activeTextPillControlHeight }
    static var activePillZIndex: Double { 0 }
    static var inactiveStoneZIndex: Double { 2 }
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

    static func stoneCenterX(for mode: LauncherMode, availableWidth: CGFloat) -> CGFloat {
        inactiveStoneFrame(for: mode, availableWidth: availableWidth).midX
    }

    static func compactModeControlsFrame(availableWidth: CGFloat) -> CGRect {
        guard let firstMode = LauncherMode.ordered.first,
              let lastMode = LauncherMode.ordered.last else {
            return .zero
        }

        let firstFrame = inactiveStoneFrame(for: firstMode, availableWidth: availableWidth)
        let lastFrame = inactiveStoneFrame(for: lastMode, availableWidth: availableWidth)
        return CGRect(
            x: firstFrame.minX,
            y: 0,
            width: lastFrame.maxX - firstFrame.minX,
            height: activePillHeight
        )
    }

    static func inactiveStoneFrame(for mode: LauncherMode, availableWidth: CGFloat) -> CGRect {
        let modes = LauncherMode.ordered
        guard let modeIndex = modes.firstIndex(of: mode) else {
            return CGRect(x: 0, y: 0, width: inactiveStoneSlotWidth, height: activePillHeight)
        }

        let slotStride = inactiveStoneSlotWidth + modeSwitcherSpacing
        return CGRect(
            x: CGFloat(modeIndex) * slotStride,
            y: 0,
            width: inactiveStoneSlotWidth,
            height: activePillHeight
        )
    }

    static func activePillFrame(for mode: LauncherMode, availableWidth: CGFloat) -> CGRect {
        let modes = LauncherMode.ordered
        let reservedInactiveWidth = CGFloat(modes.count - 1) * inactiveStoneSlotWidth
        let reservedSpacing = CGFloat(modes.count - 1) * modeSwitcherSpacing
        let width = max(inactiveStoneSlotWidth, availableWidth - reservedInactiveWidth - reservedSpacing)

        return CGRect(
            x: inactiveStoneFrame(for: mode, availableWidth: availableWidth).minX,
            y: 0,
            width: width,
            height: activePillHeight
        )
    }

    static func activePillFrame(
        for mode: LauncherMode,
        availableWidth: CGFloat,
        expansionProgress: CGFloat
    ) -> CGRect {
        let finalFrame = activePillFrame(for: mode, availableWidth: availableWidth)
        let clampedProgress = min(max(expansionProgress, 0), 1)
        let width = inactiveStoneSlotWidth + (finalFrame.width - inactiveStoneSlotWidth) * clampedProgress

        return CGRect(
            x: finalFrame.minX,
            y: finalFrame.minY,
            width: width,
            height: finalFrame.height
        )
    }

    static func activeTextPillClearedInputLeadingInset(
        for mode: LauncherMode,
        availableWidth: CGFloat
    ) -> CGFloat {
        let activeFrame = activePillFrame(for: mode, availableWidth: availableWidth)
        let compactControlsFrame = compactModeControlsFrame(availableWidth: availableWidth)
        let clearedLeadingInset = compactControlsFrame.maxX
            - activeFrame.minX
            + activeTextPillHorizontalInset
        return max(activeTextPillInputLeadingInset, clearedLeadingInset)
    }

    static func activeTextPillInputTrailingInset(isShowingProgress: Bool) -> CGFloat {
        activeTextPillHorizontalInset
            + (isShowingProgress ? activeTextPillProgressWidth + activePillHeight / 4 : 0)
    }
}

struct ModeSwitcherGlassTransitionPolicy {
    static func usesMatchedGeometry(for mode: LauncherMode) -> Bool {
        true
    }

    static func usesOuterContainer(for mode: LauncherMode) -> Bool {
        true
    }
}

@available(macOS 26.0, *)
private struct TextInputModePill: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    let mode: LauncherMode
    let symbol: String
    let glassNamespace: Namespace.ID
    let inputLeadingInset: CGFloat
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        TextInputPillForegroundLayer(
            symbol: symbol,
            placeholder: mode.placeholder,
            tint: LauncherModeTintPolicy.activeColor(for: mode),
            isShowingProgress: model.isIndexing && mode == .applications,
            inputLeadingInset: inputLeadingInset,
            text: $model.query,
            isSearchFocused: $isSearchFocused,
            onQueryChange: {
                model.queryDidChange()
            },
            onSubmit: {
                _ = model.handle(command: .open)
            }
        )
        .frame(
            maxWidth: .infinity,
            minHeight: ModeSwitcherLayoutPolicy.activePillHeight,
            maxHeight: ModeSwitcherLayoutPolicy.activePillHeight,
            alignment: .center
        )
        .background {
            TextInputPillGlassSurface(tint: LauncherModeTintPolicy.activeColor(for: mode))
                .glassEffectID(mode, in: glassNamespace)
                .glassEffectTransition(.matchedGeometry)
        }
        .contentShape(Capsule())
    }
}

private struct TextInputPillGlassSurface: View {
    let tint: Color

    var body: some View {
        Capsule()
            .fill(Color.clear)
            .glassEffect(
                .regular.tint(tint.opacity(ModeSwitcherTintPolicy.activePillTintOpacity)).interactive(),
                in: Capsule()
            )
    }
}

@available(macOS 26.0, *)
private struct TextInputPillForegroundLayer: View {
    let symbol: String
    let placeholder: String
    let tint: Color
    let isShowingProgress: Bool
    let inputLeadingInset: CGFloat
    @Binding var text: String
    @FocusState.Binding var isSearchFocused: Bool
    let onQueryChange: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            ActiveTextPillIcon(symbol: symbol)
                .foregroundStyle(tint)
                .padding(.leading, ModeSwitcherLayoutPolicy.activeTextPillIconLeadingInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            ActiveTextPillInput(
                placeholder: placeholder,
                tint: tint,
                text: $text,
                isFocused: $isSearchFocused,
                onQueryChange: onQueryChange,
                onSubmit: onSubmit
            )
            .padding(.leading, inputLeadingInset)
            .padding(
                .trailing,
                ModeSwitcherLayoutPolicy.activeTextPillInputTrailingInset(isShowingProgress: isShowingProgress)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            if isShowingProgress {
                ProgressView()
                    .controlSize(.small)
                    .frame(
                        width: ModeSwitcherLayoutPolicy.activeTextPillProgressWidth,
                        height: ModeSwitcherLayoutPolicy.activeTextPillControlHeight,
                        alignment: .center
                    )
                    .padding(.trailing, ModeSwitcherLayoutPolicy.activeTextPillHorizontalInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .glassEffectTransition(.materialize)
            }
        }
    }
}

@available(macOS 26.0, *)
private struct ActiveTextPillInput: View {
    let placeholder: String
    let tint: Color
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onQueryChange: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                ActiveTextPillPlaceholder(placeholder: placeholder)
            }

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .tint(tint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ModeSwitcherLayoutPolicy.activeTextPillTextFieldHeight,
                    maxHeight: ModeSwitcherLayoutPolicy.activeTextPillTextFieldHeight,
                    alignment: .center
                )
                .focused($isFocused)
                .onChange(of: text) {
                    onQueryChange()
                }
                .onSubmit {
                    onSubmit()
                }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ModeSwitcherLayoutPolicy.activeTextPillInputHeight,
            maxHeight: ModeSwitcherLayoutPolicy.activeTextPillInputHeight,
            alignment: .center
        )
        .layoutPriority(1)
    }
}

private struct ActiveTextPillPlaceholder: View {
    let placeholder: String

    var body: some View {
        Text(placeholder)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct ActiveTextPillIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .symbolRenderingMode(.monochrome)
            .frame(
                width: ModeSwitcherLayoutPolicy.activeTextPillIconGlyphSize,
                height: ModeSwitcherLayoutPolicy.activeTextPillIconGlyphSize,
                alignment: .center
            )
            .frame(
                width: ModeSwitcherLayoutPolicy.activeTextPillIconWidth,
                height: ModeSwitcherLayoutPolicy.activeTextPillIconHeight,
                alignment: .center
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
