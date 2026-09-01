import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassLauncherView: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    @ObservedObject var settingsModel: SettingsViewModel
    @FocusState private var isSearchFocused: Bool
    @Namespace private var selectionGlassNamespace
    @State private var handledSelectionScrollRequestID = 0
    @State private var iconPreloadTask: Task<Void, Never>?
    @State private var scrollTargetID: StoneResultRow.ID?
    @State private var scrollTargetAnchor: UnitPoint?

    private var resultUpdateAnimation: Animation {
        model.animationTiming.animation(duration: 0.08)
    }

    private var selectionScrollAnimation: Animation {
        model.animationTiming.animation(duration: 0.08)
    }

    private var toolSnapshotUpdateAnimation: Animation {
        model.animationTiming.animation(duration: 0.08)
    }

    private var settingsModeAnimation: Animation {
        model.animationTiming.animation(duration: 0.16)
    }

    private var settingsModeTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.985))
    }

    var body: some View {
        ZStack {
            if model.isPresented {
                activeSurface
                    .modifier(LauncherWindowFocusVisualModifier(isKeyWindow: model.isWindowKey))
            }
        }
        .onAppear {
            synchronizeSearchFocus()
            preloadApplicationIcons()
        }
        .onChange(of: model.mode) {
            synchronizeSearchFocus()
            preloadApplicationIcons()
        }
        .onChange(of: model.isShowingSettings) {
            synchronizeSearchFocus()
            if !model.isShowingSettings {
                preloadApplicationIcons()
            }
        }
        .onChange(of: model.isShowingHelp) {
            synchronizeSearchFocus()
            if !model.isShowingHelp {
                preloadApplicationIcons()
            }
        }
        .onChange(of: model.isPresented) { _, isPresented in
            if isPresented {
                synchronizeSearchFocus()
                preloadApplicationIcons()
            } else {
                isSearchFocused = false
                iconPreloadTask?.cancel()
                iconPreloadTask = nil
            }
        }
        .onChange(of: model.isWindowKey) { _, isWindowKey in
            if isWindowKey {
                synchronizeSearchFocus()
            }
        }
        .onChange(of: model.filteredItemIDs) {
            preloadApplicationIcons()
        }
        .animation(resultUpdateAnimation, value: model.mode)
        .animation(settingsModeAnimation, value: model.isShowingSettings)
        .animation(settingsModeAnimation, value: model.isShowingHelp)
    }

    @ViewBuilder
    private var activeSurface: some View {
        ZStack {
            if model.isShowingSettings {
                settingsSurface
                    .transition(settingsModeTransition)
            } else if model.isShowingHelp {
                helpSurface
                    .transition(settingsModeTransition)
            } else {
                launcherSurface
                    .transition(settingsModeTransition)
            }
        }
    }

    private var launcherSurface: some View {
        resultsPane
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var settingsSurface: some View {
        SettingsView(model: settingsModel, onBack: {
            model.returnToLauncherAction?()
        })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }

    private var helpSurface: some View {
        HelpView(globalHotKeyTitle: settingsModel.hotKeyTitle, modes: model.availableModes, onBack: {
            model.returnToLauncherAction?()
        })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }

    private func synchronizeSearchFocus() {
        let shouldFocus = model.isPresented && !model.isShowingSettings && !model.isShowingHelp && model.mode.acceptsTextInput
        isSearchFocused = false
        guard shouldFocus else { return }

        DispatchQueue.main.async {
            guard model.isPresented, !model.isShowingSettings, !model.isShowingHelp, model.mode.acceptsTextInput else { return }
            isSearchFocused = true
        }
    }

    private var header: some View {
        ModeSwitcherView(model: model, isSearchFocused: $isSearchFocused)
            .padding(.top, ModeSwitcherLayoutPolicy.launcherHeaderTopInset)
            .padding(.horizontal, ModeSwitcherLayoutPolicy.launcherHeaderHorizontalInset)
            .padding(.bottom, ModeSwitcherLayoutPolicy.launcherHeaderBottomInset)
            .padding(.horizontal, LauncherVisualStyle.resultsPaneContentInset)
            .padding(.top, LauncherVisualStyle.resultsPaneContentInset)
    }

    private var resultsPane: some View {
        ZStack {
            resultsPaneBackdrop

            VStack(spacing: LauncherVisualStyle.paneContentSpacing) {
                header

                results
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(resultsPaneShape)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(resultsPaneShape)
    }

    private var resultsPaneBackdrop: some View {
        resultsPaneShape
            .fill(Color.clear)
            .glassEffect(
                .regular
                    .tint(LauncherModeTintPolicy.panelColor(for: model.mode).opacity(LauncherVisualStyle.resultsPaneModeTintOpacity))
                    .interactive(false),
                in: resultsPaneShape
            )
            .overlay {
                resultsPaneShape
                    .strokeBorder(
                        LauncherPinnedBorderPolicy.color(isPinned: model.isPinned),
                        lineWidth: LauncherPinnedBorderPolicy.lineWidth(isPinned: model.isPinned)
                    )
            }
    }

    private var resultsPaneShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LauncherVisualStyle.resultsPaneCornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var results: some View {
        if model.mode.stoneDefinition.surface.usesFileBrowser {
            fileBrowserResults
        } else {
            stoneResults(model.resultSnapshot)
        }
    }

    @ViewBuilder
    private var fileBrowserResults: some View {
        if let fileBrowserModel = model.activeFileBrowserModel {
            FileBrowserView(
                model: fileBrowserModel,
                selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode)
            )
                .transition(.opacity)
        } else {
            SkeletonLoadingView(label: "Loading files", surface: .fileResults)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    await Task.yield()
                    model.prepareFileBrowserMode()
                }
        }
    }

    @ViewBuilder
    private func stoneResults(_ snapshot: StoneResultSnapshot) -> some View {
        switch snapshot {
        case let .loading(message):
            SkeletonLoadingView(label: message, surface: .launcherResults)
                .transition(.opacity)
        case let .empty(message):
            surfaceMessage(message)
        case .message, .loaded:
            resultContent(snapshot)
        }
    }

    private func surfaceMessage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
    }

    private func resultContent(_ snapshot: StoneResultSnapshot) -> some View {
        resultScrollView(reconstructionID: snapshot.identity) {
            ForEach(Array(snapshot.rows.enumerated()), id: \.element.id) { index, row in
                stoneRow(row, index: index)
                    .transition(rowTransition(for: row))
            }
        }
        .animation(
            toolSnapshotAnimation(for: snapshot),
            value: snapshot.identity
        )
    }

    private func resultScrollView<Content: View>(
        reconstructionID: AnyHashable,
        usesEagerRows: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        LauncherResultList(
            scrollTargetID: $scrollTargetID,
            scrollTargetAnchor: scrollTargetAnchor,
            reconstructionID: reconstructionID,
            usesEagerRows: usesEagerRows,
            content: content
        )
        .onAppear {
            if let request = model.selectionScrollRequest,
               request.id != handledSelectionScrollRequestID {
                handleSelectionScrollRequest(request)
            }
        }
        .onChange(of: model.selectionScrollRequest) { _, request in
            guard let request else { return }
            handleSelectionScrollRequest(request)
        }
    }

    private func stoneRow(_ row: StoneResultRow, index: Int) -> some View {
        let isSelected = index == model.selectedIndex
        let actionConfiguration = row.accessoryPresentation

        return LauncherResultRow(
            isSelected: isSelected,
            selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode),
            selectionNamespace: selectionGlassNamespace,
            verticalPadding: row.kind == .application ? 10 : 11
        ) {
            HStack(spacing: 14) {
                HStack(spacing: 14) {
                    rowIcon(for: row)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.display)
                            .font(rowTitleFont(for: row.kind))
                            .lineLimit(1)
                        Text(row.subtitle)
                            .font(rowSubtitleFont(for: row.kind))
                            .foregroundStyle(.secondary)
                            .lineLimit(row.kind == .application ? 1 : 2)
                    }

                    Spacer(minLength: 12)

                    if let accessoryText = row.accessoryText {
                        Text(accessoryText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .accessibilityLabel("Result type: \(accessoryText)")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    model.selectedIndex = index
                    model.activate(row)
                }

                if row.kind == .application {
                    Button {
                        model.exclude(row)
                    } label: {
                        Image(systemName: "eye.slash")
                            .frame(width: 16, height: 16)
                            .padding(5)
                    }
                    .buttonStyle(.plain)
                    .background {
                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.34))
                    }
                    .foregroundStyle(.secondary)
                    .help("Hide from results")
                    .launcherActionButtonRim()
                } else if let actionConfiguration {
                    Button {
                        model.selectedIndex = index
                        model.performAccessoryActivation(for: row)
                    } label: {
                        Image(systemName: actionConfiguration.systemImage)
                            .frame(width: 16, height: 16)
                            .padding(5)
                    }
                    .buttonStyle(.plain)
                    .background {
                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.34))
                    }
                    .foregroundStyle(.secondary)
                    .help(actionConfiguration.help)
                    .launcherActionButtonRim()
                }
            }
        }
        .id(row.id)
    }

    private func handleSelectionScrollRequest(_ request: SelectionScrollRequest) {
        guard request.id != handledSelectionScrollRequestID else { return }
        scrollSelectedRow(request)
        handledSelectionScrollRequestID = request.id
    }

    private func scrollSelectedRow(_ request: SelectionScrollRequest) {
        guard let rowID = resultRowID(for: request.index) else {
            return
        }

        guard SelectionScrollAnimationPolicy.shouldAnimate(anchor: request.anchor) else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scrollTargetAnchor = request.anchor.unitPoint
                scrollTargetID = rowID
            }
            return
        }

        withAnimation(selectionScrollAnimation) {
            scrollTargetAnchor = request.anchor.unitPoint
            scrollTargetID = rowID
        }
    }

    private func resultRowID(for index: Int) -> StoneResultRow.ID? {
        if model.mode.stoneDefinition.surface.usesFileBrowser {
            guard index >= 0, index < model.fileBrowserModel.entries.count else { return nil }
            return .file(model.fileBrowserModel.entries[index].url)
        }

        return model.resultRow(at: index)?.id
    }

    private func rowTransition(for row: StoneResultRow) -> AnyTransition {
        switch row.kind {
        case .dictionary, .dictionaryHistory, .calculation, .calculationHistory, .message:
            return .opacity.combined(with: .move(edge: .top))
        case .application, .file:
            return .opacity
        }
    }

    private func toolSnapshotAnimation(for snapshot: StoneResultSnapshot) -> Animation? {
        switch ToolResultsSnapshotPolicy.animation(for: model.mode, snapshot: snapshot) {
        case .none:
            return nil
        case .subtle:
            return toolSnapshotUpdateAnimation
        }
    }

    @ViewBuilder
    private func rowIcon(for row: StoneResultRow) -> some View {
        if row.kind == .application, let iconURL = row.iconURL {
            ApplicationIconView(url: iconURL)
        } else {
            Image(systemName: toolSymbol(for: row.kind))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(toolColor(for: row.kind))
                .frame(width: 38, height: 38)
        }
    }

    private func rowTitleFont(for kind: StoneResultRow.Kind) -> Font {
        if kind == .calculation {
            return .system(size: 26, weight: .semibold, design: .rounded)
        }
        return .system(size: 18, weight: .semibold)
    }

    private func rowSubtitleFont(for kind: StoneResultRow.Kind) -> Font {
        kind == .application
            ? .system(size: 12, weight: .regular)
            : .system(size: 13)
    }

    private func toolSymbol(for kind: StoneResultRow.Kind) -> String {
        switch kind {
        case .calculation:
            return "function"
        case .calculationHistory:
            return "clock.arrow.circlepath"
        case .dictionary:
            return "text.book.closed"
        case .dictionaryHistory:
            return "clock.arrow.circlepath"
        case .message:
            return "info.circle"
        case .application:
            return "app.dashed"
        case .file:
            return "doc"
        }
    }

    private func toolColor(for kind: StoneResultRow.Kind) -> Color {
        switch kind {
        case .calculation, .calculationHistory:
            return .cyan
        case .dictionary, .dictionaryHistory:
            return .mint
        case .message:
            return .secondary
        case .application, .file:
            return .secondary
        }
    }

    private func preloadApplicationIcons() {
        guard model.mode == .applications, model.isPresented else { return }
        let urls = AppIconPreloadPolicy.preloadURLs(for: model.filteredIconURLs)
        guard !urls.isEmpty else { return }

        iconPreloadTask?.cancel()
        iconPreloadTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: AppIconPreloadPolicy.initialDelayNanoseconds)
            guard !Task.isCancelled else { return }

            for (index, url) in urls.enumerated() {
                if Task.isCancelled { return }
                _ = await IconCache.applications.icon(for: url)
                if index == AppIconPreloadPolicy.initialVisibleLimit - 1 {
                    try? await Task.sleep(nanoseconds: AppIconPreloadPolicy.tailDelayNanoseconds)
                }
                if AppIconPreloadPolicy.shouldYield(afterLoadingItemAt: index) {
                    await Task.yield()
                }
            }
        }
    }
}

@available(macOS 26.0, *)
private struct LauncherWindowFocusVisualModifier: ViewModifier {
    let isKeyWindow: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.controlActiveState, .key)
            .opacity(LauncherWindowFocusVisualPolicy.contentOpacity(isKeyWindow: isKeyWindow))
            .blur(radius: LauncherWindowFocusVisualPolicy.blurRadius(isKeyWindow: isKeyWindow))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black.opacity(LauncherWindowFocusVisualPolicy.dimOverlayOpacity(isKeyWindow: isKeyWindow)))
                    .allowsHitTesting(false)
            }
            .animation(.smooth(duration: 0.18), value: isKeyWindow)
    }
}

@available(macOS 26.0, *)
enum LauncherVisualStyle {
    static let windowCornerRadius: CGFloat = 30
    static let aetherContentSpacing: CGFloat = 14
    static let paneContentSpacing: CGFloat = 12
    static let resultsPaneCornerRadius: CGFloat = 24
    static let resultsPaneContentInset: CGFloat = 12
    static let resultsPaneModeTintOpacity = 0.08
    static let rowFill = Color(nsColor: .windowBackgroundColor)
    static let selectionFill = Color(nsColor: .selectedContentBackgroundColor)
    static let surfaceRim = Color(nsColor: .separatorColor)
    static let resultsPaneRim = Color(nsColor: .separatorColor)
    static let selectionRim = Color(nsColor: .selectedContentBackgroundColor)
    static let actionRim = Color(nsColor: .separatorColor)

}

@available(macOS 26.0, *)
struct LauncherPinnedBorderPolicy {
    static func lineWidth(isPinned: Bool) -> CGFloat {
        isPinned ? 3 : 1
    }

    static func color(isPinned: Bool) -> Color {
        isPinned
            ? Color.accentColor.opacity(0.68)
            : LauncherVisualStyle.resultsPaneRim.opacity(0.24)
    }
}

@available(macOS 26.0, *)
private extension SelectionScrollAnchor {
    var unitPoint: UnitPoint? {
        switch self {
        case .nearest:
            return nil
        case .top:
            return UnitPoint(x: 0.5, y: 0.08)
        case .bottom:
            return UnitPoint(x: 0.5, y: 0.92)
        }
    }
}

@available(macOS 26.0, *)
private extension View {
    func launcherActionButtonRim() -> some View {
        self.overlay {
            Circle()
                .strokeBorder(LauncherVisualStyle.actionRim.opacity(0.34), lineWidth: 1)
        }
    }
}

@available(macOS 26.0, *)
private struct ApplicationIconView: View {
    let url: URL

    @State private var icon: NSImage?

    var body: some View {
        ZStack {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .transition(.opacity)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 38, height: 38)
        .task(id: url) {
            await loadIcon()
        }
    }

    @MainActor
    private func loadIcon() async {
        if let cachedIcon = await IconCache.applications.cachedIcon(for: url) {
            icon = cachedIcon
            return
        }

        icon = nil
        let loadedIcon = await IconCache.applications.icon(for: url)

        guard !Task.isCancelled else { return }
        icon = loadedIcon
    }
}

@available(macOS 26.0, *)
struct AppIconPreloadPolicy {
    static let initialVisibleLimit = 24
    static let preloadLimit = 256
    static let initialDelayNanoseconds: UInt64 = 0
    static let tailDelayNanoseconds: UInt64 = 250_000_000
    static let yieldStride = 8

    static func preloadURLs(for items: [LaunchItem]) -> [URL] {
        Array(items.prefix(preloadLimit).map(\.url))
    }

    static func preloadURLs(for urls: [URL]) -> [URL] {
        Array(urls.prefix(preloadLimit))
    }

    static func shouldYield(afterLoadingItemAt index: Int) -> Bool {
        (index + 1) % yieldStride == 0
    }
}
