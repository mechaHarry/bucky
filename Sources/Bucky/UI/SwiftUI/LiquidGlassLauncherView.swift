import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassLauncherView: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    @FocusState private var isSearchFocused: Bool
    @Namespace private var selectionGlassNamespace
    @Namespace private var headerGlassNamespace
    @State private var handledSelectionScrollRequestID = 0
    @State private var iconPreloadTask: Task<Void, Never>?
    @State private var scrollTargetID: ResultRowID?
    @State private var scrollTargetAnchor: UnitPoint?

    private var resultUpdateAnimation: Animation {
        model.animationTiming.animation(duration: 0.22)
    }

    private var selectionScrollAnimation: Animation {
        model.animationTiming.animation(duration: 0.16)
    }

    private var toolSnapshotUpdateAnimation: Animation {
        model.animationTiming.animation(duration: 0.14)
    }

    private var headerControlAnimation: Animation {
        model.animationTiming.animation(duration: 0.18)
    }

    var body: some View {
        ZStack {
            if model.isPresented {
                launcherSurface
                    .modifier(LauncherWindowFocusVisualModifier(isKeyWindow: model.isWindowKey))
                    .glassEffectTransition(.materialize)
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
        .onChange(of: model.filteredItems) {
            preloadApplicationIcons()
        }
        .animation(resultUpdateAnimation, value: model.mode)
    }

    private var launcherSurface: some View {
        VStack(spacing: 8) {
            header
            results
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(windowBackdrop)
        .clipShape(launcherOuterShape)
    }

    private var launcherOuterShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LauncherVisualStyle.windowCornerRadius, style: .continuous)
    }

    private func synchronizeSearchFocus() {
        let shouldFocus = model.isPresented && model.mode.acceptsTextInput
        isSearchFocused = false
        guard shouldFocus else { return }

        DispatchQueue.main.async {
            guard model.isPresented, model.mode.acceptsTextInput else { return }
            isSearchFocused = true
        }
    }

    private var header: some View {
        ModeSwitcherView(model: model, isSearchFocused: $isSearchFocused)
            .padding(.top, ModeSwitcherLayoutPolicy.launcherHeaderTopInset)
            .padding(.horizontal, ModeSwitcherLayoutPolicy.launcherHeaderHorizontalInset)
            .padding(.bottom, ModeSwitcherLayoutPolicy.launcherHeaderBottomInset)
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            if model.mode == .calculator {
                Button {
                    _ = model.handle(command: .clearHistory)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.glass)
                .disabled(!model.canClearHistory)
                .help("Clear calculation history")
                .glassEffectID(HeaderGlassEffectID.clearHistory, in: headerGlassNamespace)
                .glassEffectTransition(.materialize)
            }

            calculatorModeControl
            pinControl
        }
        .animation(headerControlAnimation, value: model.mode)
        .animation(headerControlAnimation, value: model.isPinned)
    }

    @ViewBuilder
    private var calculatorModeControl: some View {
        if model.mode == .calculator {
            Button {
                _ = model.handle(command: .switchMode(.applications))
            } label: {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .frame(width: 18, height: 18)
            }
            .launcherHeaderButtonStyle(LauncherHeaderButtonStylePolicy(isActive: true))
            .help("Applications (Command+1)")
            .glassEffectID(HeaderGlassEffectID.calculatorMode, in: headerGlassNamespace)
            .glassEffectTransition(.matchedGeometry)
        } else {
            Button {
                _ = model.handle(command: .switchMode(.calculator))
            } label: {
                Image(systemName: "wrench.and.screwdriver")
                    .frame(width: 18, height: 18)
            }
            .launcherHeaderButtonStyle(LauncherHeaderButtonStylePolicy(isActive: false))
            .help("Calculator (Command+2)")
            .glassEffectID(HeaderGlassEffectID.calculatorMode, in: headerGlassNamespace)
            .glassEffectTransition(.matchedGeometry)
        }
    }

    @ViewBuilder
    private var pinControl: some View {
        if model.isPinned {
            Button {
                _ = model.handle(command: .togglePin)
            } label: {
                Image(systemName: "pin.fill")
                    .frame(width: 18, height: 18)
            }
            .launcherHeaderButtonStyle(LauncherHeaderButtonStylePolicy(isActive: true))
            .help("Unpin window (Command+P)")
            .glassEffectID(HeaderGlassEffectID.pin, in: headerGlassNamespace)
            .glassEffectTransition(.matchedGeometry)
        } else {
            Button {
                _ = model.handle(command: .togglePin)
            } label: {
                Image(systemName: "pin")
                    .frame(width: 18, height: 18)
            }
            .launcherHeaderButtonStyle(LauncherHeaderButtonStylePolicy(isActive: false))
            .help("Pin window (Command+P)")
            .glassEffectID(HeaderGlassEffectID.pin, in: headerGlassNamespace)
            .glassEffectTransition(.matchedGeometry)
        }
    }

    private var results: some View {
        ZStack {
            resultsBackdrop
            resultContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LauncherVisualStyle.panelRim.opacity(0.26), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        if model.mode == .files {
            FileBrowserView(
                model: model.fileBrowserModel,
                selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode)
            )
                .transition(.opacity)
        } else if let emptyMessage = model.emptyMessage {
            Text(emptyMessage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        } else {
            Group {
                switch model.mode {
                case .applications:
                    resultScrollView(reconstructionID: applicationsReconstructionIdentity) {
                        ForEach(Array(model.filteredItems.enumerated()), id: \.element.url) { index, item in
                            applicationRow(item: item, index: index)
                        }
                    }
                case .calculator, .dictionary:
                    resultScrollView(reconstructionID: toolResultsSnapshotIdentity) {
                        ForEach(Array(model.toolItems.enumerated()), id: \.element) { index, item in
                            toolRow(item: item, index: index)
                                .transition(toolResultTransition)
                        }
                    }
                    .animation(
                        toolSnapshotAnimation(for: model.toolItems),
                        value: toolResultsSnapshotIdentity
                    )
                case .files:
                    FileBrowserView(
                        model: model.fileBrowserModel,
                        selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode)
                    )
                }
            }
        }
    }

    private var resultsBackdrop: some View {
        GlassEffectContainer(spacing: 0) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.clear)
                .glassEffect(
                    .regular.tint(
                        LauncherModeTintPolicy.panelColor(for: model.mode)
                            .opacity(LauncherVisualStyle.panelModeTintOpacity(resultCount: model.resultCount))
                    ),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
        }
    }

    private func resultScrollView<Content: View>(
        reconstructionID: AnyHashable,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        LauncherResultList(
            scrollTargetID: $scrollTargetID,
            scrollTargetAnchor: scrollTargetAnchor,
            reconstructionID: reconstructionID,
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

    private func applicationRow(item: LaunchItem, index: Int) -> some View {
        let rowID = ResultRowID.application(item.url)
        let isSelected = index == model.selectedIndex

        return LauncherResultRow(
            isSelected: isSelected,
            selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode),
            selectionNamespace: selectionGlassNamespace
        ) {
            HStack(spacing: 14) {
                HStack(spacing: 14) {
                    ApplicationIconView(url: item.url)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 18, weight: .semibold))
                            .lineLimit(1)
                        Text(item.subtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    model.selectedIndex = index
                    _ = model.handle(command: .open)
                }

                Button {
                    model.exclude(item)
                } label: {
                    Image(systemName: "eye.slash")
                        .frame(width: 16, height: 16)
                        .padding(5)
                }
                .buttonStyle(.glass)
                .foregroundStyle(.secondary)
                .help("Hide from results")
                .launcherActionButtonRim()
            }
        }
        .id(rowID)
    }

    private func toolRow(item: ToolItem, index: Int) -> some View {
        let rowID = ResultRowID.tool(item)
        let isSelected = index == model.selectedIndex
        let actionConfiguration = toolActionConfiguration(for: item)

        return LauncherResultRow(
            isSelected: isSelected,
            selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode),
            selectionNamespace: selectionGlassNamespace,
            verticalPadding: 11
        ) {
            HStack(spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: toolSymbol(for: item.kind))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(toolColor(for: item.kind))
                        .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.system(size: item.kind == .calculation ? 26 : 18, weight: .semibold, design: item.kind == .calculation ? .rounded : .default))
                            .lineLimit(1)
                        Text(item.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    model.selectedIndex = index
                    _ = model.handle(command: .open)
                }

                if let actionConfiguration {
                    Button {
                        model.selectedIndex = index
                        performToolRowAction(actionConfiguration.action, item: item)
                    } label: {
                        Image(systemName: actionConfiguration.symbol)
                            .frame(width: 16, height: 16)
                            .padding(5)
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(.secondary)
                    .help(actionConfiguration.help)
                    .launcherActionButtonRim()
                }
            }
        }
        .id(rowID)
    }

    private func performToolRowAction(_ action: RowAction, item: ToolItem) {
        switch action {
        case .open:
            _ = model.handle(command: .open)
        case .removeDictionaryHistory:
            model.removeDictionaryHistory(item)
        }
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

    private func resultRowID(for index: Int) -> ResultRowID? {
        switch model.mode {
        case .applications:
            guard index >= 0, index < model.filteredItems.count else { return nil }
            return .application(model.filteredItems[index].url)
        case .calculator, .dictionary:
            guard index >= 0, index < model.toolItems.count else { return nil }
            return .tool(model.toolItems[index])
        case .files:
            guard index >= 0, index < model.fileBrowserModel.entries.count else { return nil }
            return .file(model.fileBrowserModel.entries[index].url)
        }
    }

    private var toolResultTransition: AnyTransition {
        .opacity.combined(with: .move(edge: .top))
    }

    private var applicationsReconstructionIdentity: AnyHashable {
        AnyHashable(model.filteredItems.map(\.url.path).joined(separator: "\u{1F}"))
    }

    private var toolResultsSnapshotIdentity: String {
        model.toolItems.map { item in
            "\(item.kind)|\(item.title)|\(item.subtitle)|\(item.copyText ?? "")"
        }
        .joined(separator: "\u{1F}")
    }

    private func toolSnapshotAnimation(for items: [ToolItem]) -> Animation? {
        switch ToolResultsSnapshotPolicy.animation(for: model.mode, items: items) {
        case .none:
            return nil
        case .subtle:
            return toolSnapshotUpdateAnimation
        }
    }

    private var windowBackdrop: some View {
        GlassEffectContainer(spacing: 0) {
            launcherOuterShape
                .fill(Color.clear)
                .glassEffect(
                    .regular.tint(
                        LauncherModeTintPolicy.panelColor(for: model.mode)
                            .opacity(LauncherVisualStyle.windowModeTintOpacity(resultCount: model.resultCount))
                    ),
                    in: launcherOuterShape
                )
        }
        .overlay {
            launcherOuterShape
                .strokeBorder(LauncherVisualStyle.surfaceRim.opacity(0.30), lineWidth: 1)
        }
        .padding(2)
    }

    private func toolSymbol(for kind: ToolItem.Kind) -> String {
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
        }
    }

    private func toolColor(for kind: ToolItem.Kind) -> Color {
        switch kind {
        case .calculation, .calculationHistory:
            return .cyan
        case .dictionary, .dictionaryHistory:
            return .mint
        case .message:
            return .secondary
        }
    }

    private func toolActionConfiguration(for item: ToolItem) -> RowActionConfiguration? {
        switch item.kind {
        case .calculation, .calculationHistory:
            guard item.copyText != nil else { return nil }
            return RowActionConfiguration(symbol: "doc.on.doc", help: "Copy result", action: .open)
        case .dictionary:
            return RowActionConfiguration(symbol: "book", help: "Open in Dictionary", action: .open)
        case .dictionaryHistory:
            return RowActionConfiguration(
                symbol: "trash",
                help: "Remove from dictionary history",
                action: .removeDictionaryHistory
            )
        case .message:
            return nil
        }
    }

    private func preloadApplicationIcons() {
        guard model.mode == .applications, model.isPresented else { return }
        let urls = AppIconPreloadPolicy.preloadURLs(for: model.filteredItems)
        guard !urls.isEmpty else { return }

        iconPreloadTask?.cancel()
        iconPreloadTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: AppIconPreloadPolicy.initialDelayNanoseconds)
            guard !Task.isCancelled else { return }

            for (index, url) in urls.enumerated() {
                if Task.isCancelled { return }
                _ = await AppIconCache.shared.icon(for: url)
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
private enum ResultRowID: Hashable {
    case application(URL)
    case tool(ToolItem)
    case file(URL)
}

@available(macOS 26.0, *)
private enum HeaderGlassEffectID: Hashable, Sendable {
    case clearHistory
    case calculatorMode
    case pin
}

@available(macOS 26.0, *)
private enum LauncherVisualStyle {
    static let windowCornerRadius: CGFloat = 30
    static let rowFill = Color(nsColor: .windowBackgroundColor)
    static let selectionFill = Color(nsColor: .selectedContentBackgroundColor)
    static let activeHeaderControlTint = Color(nsColor: .controlAccentColor)
    static let surfaceRim = Color(nsColor: .separatorColor)
    static let panelRim = Color(nsColor: .separatorColor)
    static let selectionRim = Color(nsColor: .selectedContentBackgroundColor)
    static let actionRim = Color(nsColor: .separatorColor)

    static func panelModeTintOpacity(resultCount: Int) -> Double {
        resultCount == 0 ? 0.026 : 0.045
    }

    static func windowModeTintOpacity(resultCount: Int) -> Double {
        resultCount == 0 ? 0.028 : 0.040
    }
}

@available(macOS 26.0, *)
private struct RowActionConfiguration {
    let symbol: String
    let help: String
    let action: RowAction
}

@available(macOS 26.0, *)
private enum RowAction {
    case open
    case removeDictionaryHistory
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
    @ViewBuilder
    func launcherHeaderButtonStyle(_ policy: LauncherHeaderButtonStylePolicy) -> some View {
        switch policy.style {
        case .stockGlass:
            buttonStyle(.glass)
        case .prominentAccentGlass:
            buttonStyle(.glassProminent)
                .tint(LauncherVisualStyle.activeHeaderControlTint)
        }
    }

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
        if let cachedIcon = await AppIconCache.shared.cachedIcon(for: url) {
            icon = cachedIcon
            return
        }

        icon = nil
        let loadedIcon = await AppIconCache.shared.icon(for: url)

        guard !Task.isCancelled else { return }
        icon = loadedIcon
    }
}

@available(macOS 26.0, *)
struct AppIconPreloadPolicy {
    static let initialVisibleLimit = 24
    static let preloadLimit = 512
    static let initialDelayNanoseconds: UInt64 = 40_000_000
    static let tailDelayNanoseconds: UInt64 = 140_000_000
    static let yieldStride = 16

    static func preloadURLs(for items: [LaunchItem]) -> [URL] {
        Array(items.prefix(preloadLimit).map(\.url))
    }

    static func shouldYield(afterLoadingItemAt index: Int) -> Bool {
        (index + 1) % yieldStride == 0
    }
}

@available(macOS 26.0, *)
private actor AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlightTasks: [String: Task<NSImage, Never>] = [:]
    private var activeLoadCount = 0
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private let maxConcurrentLoads = 2

    private init() {
        cache.countLimit = AppIconPreloadPolicy.preloadLimit
        cache.totalCostLimit = 128 * 1024 * 1024
    }

    func cachedIcon(for url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    func icon(for url: URL) async -> NSImage {
        let key = url.path as NSString
        if let cachedIcon = cache.object(forKey: key) {
            return cachedIcon
        }

        if let inFlightTask = inFlightTasks[url.path] {
            return await inFlightTask.value
        }

        let path = url.path
        let task = Task.detached(priority: .utility) { [self] in
            await acquireLoadSlot()
            return NSWorkspace.shared.icon(forFile: path)
        }
        inFlightTasks[path] = task

        let icon = await task.value
        releaseLoadSlot()
        cache.setObject(icon, forKey: key, cost: estimatedCost(for: icon))
        inFlightTasks[path] = nil
        return icon
    }

    private func estimatedCost(for icon: NSImage) -> Int {
        let largestPixelArea = icon.representations
            .map { max(1, $0.pixelsWide) * max(1, $0.pixelsHigh) }
            .max() ?? Int(max(1, icon.size.width) * max(1, icon.size.height))

        return largestPixelArea * 4
    }

    private func acquireLoadSlot() async {
        if activeLoadCount < maxConcurrentLoads {
            activeLoadCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            loadWaiters.append(continuation)
        }
    }

    private func releaseLoadSlot() {
        if loadWaiters.isEmpty {
            activeLoadCount = max(0, activeLoadCount - 1)
        } else {
            loadWaiters.removeFirst().resume()
        }
    }
}
