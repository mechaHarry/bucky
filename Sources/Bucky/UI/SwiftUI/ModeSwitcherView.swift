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
                                font: .system(size: 16, weight: .semibold)
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
    static let activeTextPillCalculatorIconVerticalOffset: CGFloat = -1
    static let activeTextPillDictionaryIconVerticalOffset: CGFloat = -1
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

            TextField(mode.placeholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .frame(height: ModeSwitcherLayoutPolicy.activeTextPillInputHeight, alignment: .center)
                .offset(y: ModeSwitcherLayoutPolicy.activeTextPillInputVerticalOffset)
                .focused($isSearchFocused)
                .onChange(of: model.query) {
                    model.queryDidChange()
                }
                .onSubmit {
                    _ = model.handle(command: .open)
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
