import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassLauncherView: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    @FocusState private var isSearchFocused: Bool
    @Namespace private var rowGlassNamespace
    @Namespace private var selectionGlassNamespace
    @State private var handledSelectionScrollRequestID = 0
    @State private var iconPreloadTask: Task<Void, Never>?

    private let resultUpdateAnimation = Animation.interactiveSpring(duration: 0.24, extraBounce: 0.03)
    private let rowSelectionAnimation = Animation.smooth(duration: 0.18, extraBounce: 0)

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
        .onChange(of: model.mode) { _ in
            isSearchFocused = true
            preloadApplicationIcons()
        }
        .onChange(of: model.isPresented) { isPresented in
            if isPresented {
                isSearchFocused = true
                preloadApplicationIcons()
            } else {
                iconPreloadTask?.cancel()
                iconPreloadTask = nil
            }
        }
        .onChange(of: model.filteredItems) { _ in
            preloadApplicationIcons()
        }
        .animation(.interactiveSpring(duration: 0.22, extraBounce: 0.04), value: model.mode)
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
                .onChange(of: model.query) { _ in
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
                    .transition(.opacity)
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
                .glassEffectTransition(.materialize)
            }

            toolsModeControl
            pinControl
        }
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
        } else {
            Button {
                _ = model.handle(command: .toggleToolsMode)
            } label: {
                Image(systemName: "wrench.and.screwdriver")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.glass)
            .help("Tools (Command+/)")
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
        } else {
            Button {
                _ = model.handle(command: .togglePin)
            } label: {
                Image(systemName: "pin")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.glass)
            .help("Pin window (Command+P)")
        }
    }

    private var results: some View {
        ZStack {
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
    }

    private func resultScrollView<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 5) {
                    content()
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .animation(resultUpdateAnimation, value: resultListIdentity)
            }
            .scrollIndicators(.hidden)
            .scrollIndicatorsFlash(trigger: false)
            .onAppear {
                if let request = model.selectionScrollRequest,
                   request.id != handledSelectionScrollRequestID {
                    DispatchQueue.main.async {
                        handleSelectionScrollRequest(request, using: proxy)
                    }
                }
            }
            .onChange(of: model.selectionScrollRequest) { request in
                guard let request else { return }
                handleSelectionScrollRequest(request, using: proxy)
            }
        }
    }

    private func applicationRow(item: LaunchItem, index: Int) -> some View {
        let rowID = ResultRowID.application(item.url)

        return HStack(spacing: 14) {
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

            Button {
                model.exclude(item)
            } label: {
                Image(systemName: "eye.slash")
                    .frame(width: 16, height: 16)
                    .padding(6)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide from results")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            rowPanel(rowID: rowID, isSelected: index == model.selectedIndex)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .id(rowID)
        .onTapGesture {
            model.selectedIndex = index
            _ = model.handle(command: .open)
        }
    }

    private func toolRow(item: ToolItem, index: Int) -> some View {
        let rowID = ResultRowID.tool(item)

        return Button {
            model.selectedIndex = index
            _ = model.handle(command: .open)
        } label: {
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

                if item.kind == .calculation || item.kind == .calculationHistory {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.tertiary)
                } else if item.kind == .dictionary {
                    Image(systemName: "book")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                rowPanel(rowID: rowID, isSelected: index == model.selectedIndex)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(rowID)
    }

    @ViewBuilder
    private func rowPanel(rowID: ResultRowID, isSelected: Bool) -> some View {
        GlassEffectContainer(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(
                        .regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.035)).interactive(false),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .glassEffectID(rowID.glassEffectID, in: rowGlassNamespace)
                    .glassEffectTransition(.matchedGeometry)

                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(
                            .regular.tint(.accentColor.opacity(0.18)).interactive(),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .glassEffectID(RowGlassEffectID.selection, in: selectionGlassNamespace)
                        .glassEffectTransition(.matchedGeometry)
                }
            }
            .animation(rowSelectionAnimation, value: isSelected)
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

    private func handleSelectionScrollRequest(_ request: SelectionScrollRequest, using proxy: ScrollViewProxy) {
        guard request.id != handledSelectionScrollRequestID else { return }
        scrollSelectedRow(request, using: proxy)
        handledSelectionScrollRequestID = request.id
    }

    private func scrollSelectedRow(_ request: SelectionScrollRequest, using proxy: ScrollViewProxy) {
        guard let rowID = resultRowID(for: request.index) else {
            return
        }

        switch request.anchor {
        case .top:
            scrollToRow(rowID, anchor: .top, using: proxy)
            return
        case .bottom:
            scrollToRow(rowID, anchor: .bottom, using: proxy)
            return
        case .nearest:
            scrollToRow(rowID, anchor: nil, using: proxy)
        }
    }

    private func scrollToRow(_ rowID: ResultRowID, anchor: UnitPoint?, using proxy: ScrollViewProxy) {
        withAnimation(.interactiveSpring(duration: 0.18, extraBounce: 0.02)) {
            proxy.scrollTo(rowID, anchor: anchor)
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
                    .regular.tint(Color(nsColor: .windowBackgroundColor).opacity(model.resultCount == 0 ? 0.025 : 0.04)),
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                )
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
        if let cachedIcon = AppIconCache.shared.cachedIcon(for: url) {
            icon = cachedIcon
            return
        }

        icon = nil
        let loadedIcon = await AppIconCache.shared.icon(for: url)

        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            icon = loadedIcon
        }
    }
}

@available(macOS 26.0, *)
private final class AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Bucky.AppIconCache"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private let lock = NSLock()
    private var pendingContinuations: [String: [CheckedContinuation<NSImage, Never>]] = [:]

    func cachedIcon(for url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    func icon(for url: URL) async -> NSImage {
        let key = url.path as NSString
        if let cachedIcon = cache.object(forKey: key) {
            return cachedIcon
        }

        return await withCheckedContinuation { continuation in
            enqueueIconLoad(for: url.path, continuation: continuation)
        }
    }

    private func enqueueIconLoad(for path: String, continuation: CheckedContinuation<NSImage, Never>) {
        var shouldStartLoad = false

        lock.lock()
        if pendingContinuations[path] == nil {
            pendingContinuations[path] = []
            shouldStartLoad = true
        }
        pendingContinuations[path]?.append(continuation)
        lock.unlock()

        guard shouldStartLoad else { return }

        operationQueue.addOperation { [self] in
            let icon = NSWorkspace.shared.icon(forFile: path)
            cache.setObject(icon, forKey: path as NSString)

            lock.lock()
            let continuations = pendingContinuations.removeValue(forKey: path) ?? []
            lock.unlock()

            DispatchQueue.main.async {
                for continuation in continuations {
                    continuation.resume(returning: icon)
                }
            }
        }
    }
}
