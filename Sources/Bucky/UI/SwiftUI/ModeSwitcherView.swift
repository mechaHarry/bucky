import SwiftUI

@available(macOS 26.0, *)
struct ModeSwitcherView: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    @FocusState.Binding var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        modeSwitcherContent
    }

    private var modeSwitcherContent: some View {
        HStack(spacing: 10) {
            ForEach(model.availableModes, id: \.self) { mode in
                modeSwitcherElement(for: mode)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func modeSwitcherElement(for mode: LauncherMode) -> some View {
        if mode == model.mode {
            activePill(for: mode)
        } else {
            modeOrb(for: mode)
        }
    }

    private func modeOrb(for mode: LauncherMode) -> some View {
        Button {
            _ = model.handle(command: .switchMode(mode))
        } label: {
            Image(systemName: mode.helpSystemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LauncherModeTintPolicy.inactiveOrbIconColor(for: mode, colorScheme: colorScheme))
                .frame(width: 20, height: 20)
                .padding(10)
        }
        .buttonStyle(.plain)
        .background {
            ModeControlBackground(
                shape: Circle(),
                fill: LauncherModeTintPolicy.inactiveOrbColor(for: mode),
                tint: LauncherModeTintPolicy.activeColor(for: mode),
                isActive: false
            )
        }
        .help(helpText(for: mode))
    }

    @ViewBuilder
    private func activePill(for mode: LauncherMode) -> some View {
        switch mode.stoneDefinition.surface {
        case .textInput:
            TextInputModePill(
                model: model,
                mode: mode,
                symbol: mode.helpSystemImage,
                isSearchFocused: $isSearchFocused
            )
        case .fileBrowser:
            GeometryReader { proxy in
                let displayedPath = displayedFilePath
                let pathWidth = ModeSwitcherLayoutPolicy.filesPathTextWidth(
                    in: proxy.size.width,
                    path: displayedPath
                )
                let modeTint = LauncherModeTintPolicy.activeColor(for: mode)
                let iconTint = LauncherModeTintPolicy.iconColor(for: mode, colorScheme: colorScheme)

                HStack(spacing: ModeSwitcherLayoutPolicy.filesContentSpacing) {
                    Button {
                        if let displayedFileURL {
                            try? MacFileServices().copyPathsToPasteboard([displayedFileURL])
                        }
                    } label: {
                        HStack(spacing: ModeSwitcherLayoutPolicy.filesPathIconSpacing) {
                            Image(systemName: mode.helpSystemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(iconTint)
                                .frame(width: ModeSwitcherLayoutPolicy.filesPathIconWidth)

                            FadeMarqueeText(
                                text: displayedPath,
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

                    foldersFirstToggle
                        .layoutPriority(1)
                }
                .padding(.leading, ModeSwitcherLayoutPolicy.filesPillLeadingPadding)
                .padding(.trailing, ModeSwitcherLayoutPolicy.filesPillTrailingPadding)
                .frame(width: proxy.size.width, height: ModeSwitcherLayoutPolicy.activePillHeight, alignment: .leading)
                .background {
                    ModeControlBackground(
                        shape: Capsule(),
                        fill: Color(nsColor: .windowBackgroundColor),
                        tint: modeTint,
                        isActive: true
                    )
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: ModeSwitcherLayoutPolicy.activePillHeight, maxHeight: ModeSwitcherLayoutPolicy.activePillHeight)
            .layoutPriority(1)
        }
    }

    private var displayedFileURL: URL? {
        guard let fileBrowserModel = model.activeFileBrowserModel else {
            return nil
        }
        if let selectedEntry = fileBrowserModel.selectedEntry,
           selectedEntry.kind != .directory {
            return selectedEntry.url
        }
        return fileBrowserModel.currentDirectory
    }

    private var displayedFilePath: String {
        displayedFileURL?.path ?? "Loading files"
    }

    private var sortMenu: some View {
        Picker("Sort", selection: Binding(
            get: { model.activeFileBrowserModel?.sort ?? .name },
            set: { model.activeFileBrowserModel?.setSort($0) }
        )) {
            ForEach(FileBrowserSort.allCases, id: \.self) { sort in
                Text(sort.displayName).tag(sort)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: ModeSwitcherLayoutPolicy.filesSortMenuWidth)
        .fixedSize(horizontal: true, vertical: false)
        .help("Sort files")
    }

    private var foldersFirstToggle: some View {
        Toggle(isOn: Binding(
            get: { model.activeFileBrowserModel?.foldersFirst ?? false },
            set: { model.activeFileBrowserModel?.setFoldersFirst($0) }
        )) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13, weight: .semibold))
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .frame(width: ModeSwitcherLayoutPolicy.filesFoldersFirstToggleWidth)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Folders first")
        .help("Folders first")
    }

    private func helpText(for mode: LauncherMode) -> String {
        "\(mode.placeholder) (\(shortcutText(for: mode)))"
    }

    private func shortcutText(for mode: LauncherMode) -> String {
        mode.shortcutDisplayText
    }
}

struct ModeSwitcherLayoutPolicy {
    static let activePillHeight: CGFloat = 48
    static var launcherHeaderTopInset: CGFloat { activePillHeight / 12 }
    static var launcherHeaderHorizontalInset: CGFloat { 0 }
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
    static let filesPillLeadingPadding: CGFloat = 16
    static let filesPillTrailingPadding: CGFloat = 12
    static let filesContentSpacing: CGFloat = 12
    static let filesPathIconSpacing: CGFloat = 10
    static let filesPathIconWidth: CGFloat = 22
    static let filesPathTextHeight: CGFloat = 22
    static let filesSortMenuWidth: CGFloat = 128
    static let filesFoldersFirstToggleWidth: CGFloat = 34

    static func filesPathButtonWidth(in pillWidth: CGFloat) -> CGFloat {
        let fixedWidth = filesPillLeadingPadding
            + filesPillTrailingPadding
            + filesContentSpacing * 2
            + filesSortMenuWidth
            + filesFoldersFirstToggleWidth
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

    static func activeTextPillInputTrailingInset(isShowingProgress: Bool) -> CGFloat {
        activeTextPillHorizontalInset
            + (isShowingProgress ? activeTextPillProgressWidth + activePillHeight / 4 : 0)
    }
}

struct ModeSwitcherGlassTransitionPolicy {
    static func usesMatchedGeometry(for mode: LauncherMode) -> Bool {
        false
    }

    static func usesOuterContainer(for _: LauncherMode) -> Bool {
        false
    }
}

@available(macOS 26.0, *)
private struct TextInputModePill: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    let mode: LauncherMode
    let symbol: String
    @FocusState.Binding var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TextInputPillForegroundLayer(
            symbol: symbol,
            placeholder: mode.placeholder,
            tint: LauncherModeTintPolicy.iconColor(for: mode, colorScheme: colorScheme),
            isShowingProgress: model.isIndexing && mode == .applications,
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
            ModeControlBackground(
                shape: Capsule(),
                fill: Color(nsColor: .windowBackgroundColor),
                tint: LauncherModeTintPolicy.activeColor(for: mode),
                isActive: true
            )
        }
        .contentShape(Capsule())
    }
}

private struct ModeControlBackground<ShapeType: InsettableShape>: View {
    let shape: ShapeType
    let fill: Color
    let tint: Color
    let isActive: Bool

    var body: some View {
        shape
            .fill(fill.opacity(isActive ? 0.34 : 0.26))
            .overlay {
                shape
                    .fill(tint.opacity(isActive ? 0.18 : 0.10))
            }
            .overlay {
                shape
                    .strokeBorder(tint.opacity(isActive ? 0.38 : 0.24), lineWidth: 1)
            }
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isActive ? 0.36 : 0.24),
                                Color.white.opacity(0.04),
                                Color.black.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
    }
}

@available(macOS 26.0, *)
private struct TextInputPillForegroundLayer: View {
    let symbol: String
    let placeholder: String
    let tint: Color
    let isShowingProgress: Bool
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
            .padding(.leading, ModeSwitcherLayoutPolicy.activeTextPillInputLeadingInset)
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
