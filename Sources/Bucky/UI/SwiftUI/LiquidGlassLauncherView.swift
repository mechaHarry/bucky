import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassLauncherView: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    @FocusState private var isSearchFocused: Bool
    @Namespace private var rowGlassNamespace
    @Namespace private var selectionGlassNamespace
    @Namespace private var headerGlassNamespace
    @State private var handledSelectionScrollRequestID = 0
    @State private var iconPreloadTask: Task<Void, Never>?
    @State private var scrollTargetID: ResultRowID?
    @State private var scrollTargetAnchor: UnitPoint?
    @State private var hoveredRowID: ResultRowID?

    private var resultUpdateAnimation: Animation {
        model.animationTiming.animation(duration: 0.22)
    }

    private var selectionScrollAnimation: Animation {
        model.animationTiming.animation(duration: 0.16)
    }

    private var rowSelectionAnimation: Animation {
        model.animationTiming.animation(duration: 0.18)
    }

    private var headerControlAnimation: Animation {
        model.animationTiming.animation(duration: 0.18)
    }

    var body: some View {
        ZStack {
            if model.isPresented {
                launcherSurface
                    .glassEffectTransition(.materialize)
            }
        }
        .onAppear {
            isSearchFocused = true
            preloadApplicationIcons()
        }
        .onChange(of: model.mode) {
            isSearchFocused = true
            preloadApplicationIcons()
        }
        .onChange(of: model.isPresented) { _, isPresented in
            if isPresented {
                isSearchFocused = true
                preloadApplicationIcons()
            } else {
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
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: model.mode == .applications ? "square.grid.2x2" : "function")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)

            TextField(model.placeholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .focused($isSearchFocused)
                .onChange(of: model.query) {
                    withAnimation(resultUpdateAnimation) {
                        model.queryDidChange()
                    }
                }
                .onSubmit {
                    _ = model.handle(command: .open)
                }

            if model.isIndexing && model.mode == .applications {
                ProgressView()
                    .controlSize(.small)
                    .glassEffectTransition(.materialize)
            }

            headerControls
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            GlassEffectContainer(spacing: 0) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LauncherVisualStyle.surfaceRim.opacity(0.24), lineWidth: 1)
        }
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            if model.mode == .tools {
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

            toolsModeControl
            pinControl
        }
        .animation(headerControlAnimation, value: model.mode)
        .animation(headerControlAnimation, value: model.isPinned)
    }

    @ViewBuilder
    private var toolsModeControl: some View {
        if model.mode == .tools {
            Button {
                _ = model.handle(command: .toggleToolsMode)
            } label: {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.glassProminent)
            .help("Tools (Command+/)")
            .glassEffectID(HeaderGlassEffectID.toolsMode, in: headerGlassNamespace)
            .glassEffectTransition(.matchedGeometry)
        } else {
            Button {
                _ = model.handle(command: .toggleToolsMode)
            } label: {
                Image(systemName: "wrench.and.screwdriver")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.glass)
            .help("Tools (Command+/)")
            .glassEffectID(HeaderGlassEffectID.toolsMode, in: headerGlassNamespace)
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
            .buttonStyle(.glassProminent)
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
            .buttonStyle(.glass)
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
        if let emptyMessage = model.emptyMessage {
            Text(emptyMessage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        } else {
            Group {
                switch model.mode {
                case .applications:
                    resultScrollView {
                        ForEach(Array(model.filteredItems.enumerated()), id: \.element.url) { index, item in
                            applicationRow(item: item, index: index)
                        }
                    }
                case .tools:
                    resultScrollView {
                        ForEach(Array(model.toolItems.enumerated()), id: \.element) { index, item in
                            toolRow(item: item, index: index)
                        }
                    }
                }
            }
        }
    }

    private var resultsBackdrop: some View {
        GlassEffectContainer(spacing: 0) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.clear)
                .glassEffect(
                    .regular.tint(LauncherVisualStyle.panelFill.opacity(model.resultCount == 0 ? 0.018 : 0.032)),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
        }
    }

    private func resultScrollView<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 5) {
                content()
            }
            .scrollTargetLayout()
            .frame(maxWidth: .infinity)
            .animation(resultUpdateAnimation, value: resultListIdentity)
        }
        .contentMargins(.vertical, 10, for: .scrollContent)
        .scrollPosition(id: $scrollTargetID, anchor: scrollTargetAnchor)
        .scrollIndicators(.hidden)
        .scrollIndicatorsFlash(trigger: false)
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
        let isHovered = hoveredRowID == rowID
        let actionVisibility = LauncherRowActionVisibilityPolicy(
            hasAction: true,
            isSelected: isSelected,
            isHovered: isHovered
        )

        return HStack(spacing: 14) {
            HStack(spacing: 14) {
                ApplicationIconView(url: item.url, animationTiming: model.animationTiming)

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
            .opacity(actionVisibility.isVisible ? 1 : 0)
            .allowsHitTesting(actionVisibility.allowsHitTesting)
            .launcherActionButtonRim(isVisible: actionVisibility.isVisible)
            .animation(rowSelectionAnimation, value: actionVisibility)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            rowPanel(rowID: rowID, isSelected: isSelected, isHovered: isHovered)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .id(rowID)
        .onHover { isHovering in
            updateHoveredRow(rowID, isHovering: isHovering)
        }
    }

    private func toolRow(item: ToolItem, index: Int) -> some View {
        let rowID = ResultRowID.tool(item)
        let isSelected = index == model.selectedIndex
        let isHovered = hoveredRowID == rowID
        let actionConfiguration = toolActionConfiguration(for: item)
        let actionVisibility = LauncherRowActionVisibilityPolicy(
            hasAction: actionConfiguration != nil,
            isSelected: isSelected,
            isHovered: isHovered
        )

        return HStack(spacing: 14) {
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
                    _ = model.handle(command: .open)
                } label: {
                    Image(systemName: actionConfiguration.symbol)
                        .frame(width: 16, height: 16)
                        .padding(5)
                }
                .buttonStyle(.glass)
                .foregroundStyle(.secondary)
                .help(actionConfiguration.help)
                .opacity(actionVisibility.isVisible ? 1 : 0)
                .allowsHitTesting(actionVisibility.allowsHitTesting)
                .launcherActionButtonRim(isVisible: actionVisibility.isVisible)
                .animation(rowSelectionAnimation, value: actionVisibility)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            rowPanel(rowID: rowID, isSelected: isSelected, isHovered: isHovered)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .id(rowID)
        .onHover { isHovering in
            updateHoveredRow(rowID, isHovering: isHovering)
        }
    }

    @ViewBuilder
    private func rowPanel(rowID: ResultRowID, isSelected: Bool, isHovered: Bool) -> some View {
        GlassEffectContainer(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(
                        .regular.tint(LauncherVisualStyle.rowFill.opacity(isHovered ? 0.060 : 0.035)).interactive(false),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .glassEffectID(rowID.glassEffectID, in: rowGlassNamespace)
                    .glassEffectTransition(.matchedGeometry)

                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(
                            .regular.tint(LauncherVisualStyle.selectionFill.opacity(0.18)).interactive(),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .glassEffectID(RowGlassEffectID.selection, in: selectionGlassNamespace)
                        .glassEffectTransition(.matchedGeometry)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(LauncherVisualStyle.selectionRim.opacity(0.42), lineWidth: 1)
                        }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? LauncherVisualStyle.selectionRim.opacity(0.34) : LauncherVisualStyle.surfaceRim.opacity(isHovered ? 0.28 : 0.18),
                        lineWidth: isSelected ? 1.15 : 1
                    )
            }
            .animation(rowSelectionAnimation, value: isSelected)
            .animation(rowSelectionAnimation, value: isHovered)
        }
    }

    private func updateHoveredRow(_ rowID: ResultRowID, isHovering: Bool) {
        withAnimation(rowSelectionAnimation) {
            if isHovering {
                hoveredRowID = rowID
            } else if hoveredRowID == rowID {
                hoveredRowID = nil
            }
        }
    }

    private var resultListIdentity: String {
        switch model.mode {
        case .applications:
            let firstPath = model.filteredItems.first?.url.path ?? "empty"
            return "apps|\(model.query)|\(model.filteredItems.count)|\(firstPath)"
        case .tools:
            let firstItem = model.toolItems.first
            return "tools|\(model.query)|\(model.toolItems.count)|\(firstItem?.title ?? "empty")|\(firstItem?.subtitle ?? "")"
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
        case .tools:
            guard index >= 0, index < model.toolItems.count else { return nil }
            return .tool(model.toolItems[index])
        }
    }

    private var windowBackdrop: some View {
        GlassEffectContainer(spacing: 0) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.clear)
                .glassEffect(
                    .regular.tint(LauncherVisualStyle.windowFill.opacity(model.resultCount == 0 ? 0.025 : 0.04)),
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(LauncherVisualStyle.surfaceRim.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 30, x: 0, y: 20)
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
        case .message:
            return "info.circle"
        }
    }

    private func toolColor(for kind: ToolItem.Kind) -> Color {
        switch kind {
        case .calculation, .calculationHistory:
            return .cyan
        case .dictionary:
            return .mint
        case .message:
            return .secondary
        }
    }

    private func toolActionConfiguration(for item: ToolItem) -> RowActionConfiguration? {
        switch item.kind {
        case .calculation, .calculationHistory:
            guard item.copyText != nil else { return nil }
            return RowActionConfiguration(symbol: "doc.on.doc", help: "Copy result")
        case .dictionary:
            return RowActionConfiguration(symbol: "book", help: "Open in Dictionary")
        case .message:
            return nil
        }
    }

    private func preloadApplicationIcons() {
        guard model.mode == .applications, model.isPresented else { return }
        let urls = Array(model.filteredItems.prefix(18).map(\.url))
        guard !urls.isEmpty else { return }

        iconPreloadTask?.cancel()
        iconPreloadTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            for (index, url) in urls.enumerated() {
                if Task.isCancelled { return }
                _ = await AppIconCache.shared.icon(for: url)
                if index % 4 == 3 {
                    await Task.yield()
                }
            }
        }
    }
}

@available(macOS 26.0, *)
private enum ResultRowID: Hashable {
    case application(URL)
    case tool(ToolItem)

    var glassEffectID: RowGlassEffectID {
        switch self {
        case .application(let url):
            return .application(path: url.path)
        case .tool(let item):
            return .tool(
                kind: item.kind.glassEffectID,
                title: item.title,
                subtitle: item.subtitle,
                copyText: item.copyText ?? ""
            )
        }
    }
}

@available(macOS 26.0, *)
private enum RowGlassEffectID: Hashable, Sendable {
    case application(path: String)
    case tool(kind: String, title: String, subtitle: String, copyText: String)
    case selection
}

@available(macOS 26.0, *)
private enum HeaderGlassEffectID: Hashable, Sendable {
    case clearHistory
    case toolsMode
    case pin
}

@available(macOS 26.0, *)
private enum LauncherVisualStyle {
    static let windowFill = Color(nsColor: .windowBackgroundColor)
    static let panelFill = Color(nsColor: .underPageBackgroundColor)
    static let rowFill = Color(nsColor: .windowBackgroundColor)
    static let selectionFill = Color(nsColor: .selectedContentBackgroundColor)
    static let surfaceRim = Color(nsColor: .separatorColor)
    static let panelRim = Color(nsColor: .separatorColor)
    static let selectionRim = Color(nsColor: .selectedContentBackgroundColor)
    static let actionRim = Color(nsColor: .separatorColor)
}

@available(macOS 26.0, *)
private struct RowActionConfiguration {
    let symbol: String
    let help: String
}

@available(macOS 26.0, *)
private extension SelectionScrollAnchor {
    var unitPoint: UnitPoint? {
        switch self {
        case .nearest:
            return nil
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }
}

@available(macOS 26.0, *)
private extension View {
    func launcherActionButtonRim(isVisible: Bool) -> some View {
        self.overlay {
            Circle()
                .strokeBorder(LauncherVisualStyle.actionRim.opacity(isVisible ? 0.34 : 0), lineWidth: 1)
        }
    }
}

@available(macOS 26.0, *)
private extension ToolItem.Kind {
    var glassEffectID: String {
        switch self {
        case .calculation:
            return "calculation"
        case .calculationHistory:
            return "calculationHistory"
        case .dictionary:
            return "dictionary"
        case .message:
            return "message"
        }
    }
}

@available(macOS 26.0, *)
private struct ApplicationIconView: View {
    let url: URL
    let animationTiming: LauncherAnimationTiming

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
        withAnimation(animationTiming.animation(duration: 0.12)) {
            icon = loadedIcon
        }
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
        cache.countLimit = 192
        cache.totalCostLimit = 64 * 1024 * 1024
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
