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
            HStack(spacing: 12) {
                Image(systemName: symbol(for: mode))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                TextField(mode.placeholder, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
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
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: Capsule())
        case .files:
            HStack(spacing: 12) {
                Button {
                    try? MacFileServices().copyPathsToPasteboard([displayedFileURL])
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: symbol(for: mode))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)

                        FadeMarqueeText(
                            text: displayedFileURL.path,
                            font: .system(size: 16, weight: .semibold)
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .help("Copy path")

                sortMenu
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .glassEffect(.regular.interactive(), in: Capsule())
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
