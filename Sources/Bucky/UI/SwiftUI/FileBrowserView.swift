import AppKit
import AVKit
import SwiftUI

@available(macOS 26.0, *)
struct FileBrowserView: View {
    @ObservedObject var model: FileBrowserModel
    let selectionTint: Color
    @Namespace private var browseSelectionGlassNamespace
    @Namespace private var pinnedSelectionGlassNamespace
    @State private var transferGlow = false
    @State private var wobblePhase: CGFloat = 0
    @State private var browseScrollTargetID: URL?
    @State private var browseScrollTargetAnchor: UnitPoint?
    @State private var pinnedScrollTargetID: URL?
    @State private var handledSelectionScrollEventID = 0
    @State private var fileIconPreloadTask: Task<Void, Never>?

    init(
        model: FileBrowserModel,
        selectionTint: Color = LauncherModeTintPolicy.selectionColor(for: .files)
    ) {
        self.model = model
        self.selectionTint = selectionTint
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            browsePane
                .modifier(FileBrowserPaneWobbleEffect(phase: wobblePhase))

            if model.focusState == .previewActions {
                actionOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if case .transferPending = model.focusState {
                actionOverlay
                    .offset(x: 214)
                    .opacity(0.34)
                    .blur(radius: 2.5)
                    .allowsHitTesting(false)
                transferHint
                    .transition(.opacity)
            }

            focusedOverlay

            if let statusMessage = model.statusMessage {
                statusOverlay(statusMessage)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            transferGlow = isTransferPending
            preloadFileIcons()
        }
        .onDisappear {
            fileIconPreloadTask?.cancel()
            fileIconPreloadTask = nil
        }
        .onChange(of: isTransferPending) { _, isPending in
            transferGlow = isPending
        }
        .onChange(of: model.entries.map(\.url)) { _, _ in
            preloadFileIcons()
        }
        .onChange(of: model.sidebarDirectories) { _, _ in
            preloadFileIcons()
        }
        .onChange(of: model.wobbleEvent?.id) { _, id in
            guard id != nil else { return }
            withAnimation(.smooth(duration: 0.20)) {
                wobblePhase += 1
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.focusState)
    }

    private var browsePane: some View {
        HStack(spacing: 10) {
            pinnedRail
                .frame(width: 150)

            currentDirectoryColumn
                .opacity(model.focusState == .pinnedItems ? 0.46 : 1)
                .blur(radius: model.focusState == .pinnedItems ? 2.0 : 0)
        }
        .overlay {
            if isTransferPending {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(transferGlow ? 0.70 : 0.25), lineWidth: 1.5)
                    .shadow(color: Color.accentColor.opacity(transferGlow ? 0.52 : 0.18), radius: 16)
                    .padding(8)
                    .animation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true), value: transferGlow)
            }
        }
    }

    private var pinnedRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.sidebarDirectories.isEmpty {
                placeholder("Mounts and pins will appear here")
            } else {
                LauncherResultList(
                    scrollTargetID: $pinnedScrollTargetID,
                    reconstructionID: pinnedReconstructionIdentity
                ) {
                    ForEach(Array(model.sidebarDirectories.enumerated()), id: \.element) { index, url in
                        FileBrowserPinnedRow(
                            url: url,
                            isSelected: model.focusState == .pinnedItems && index == model.focusedPinnedIndex,
                            selectionTint: selectionTint,
                            selectionNamespace: pinnedSelectionGlassNamespace,
                            model: model
                        )
                        .id(url)
                        .help(url.path)
                    }
                }
                .onAppear {
                    scrollFocusedPin(animated: false)
                }
                .onChange(of: model.focusedPinnedIndex) { _, _ in
                    scrollFocusedPin(animated: true)
                }
                .onChange(of: model.focusState) { _, _ in
                    scrollFocusedPin(animated: true)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var currentDirectoryColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                LauncherResultList(
                    scrollTargetID: $browseScrollTargetID,
                    scrollTargetAnchor: browseScrollTargetAnchor,
                    reconstructionID: entriesReconstructionIdentity
                ) {
                    ForEach(Array(model.entries.enumerated()), id: \.element.url) { _, entry in
                        FileBrowserRow(
                            entry: entry,
                            isSelected: entry.url == model.selectedEntry?.url,
                            isMarked: model.selectedURLs.contains(entry.url),
                            selectionTint: selectionTint,
                            selectionNamespace: browseSelectionGlassNamespace,
                            model: model
                        )
                        .id(entry.url)
                    }
                }

                if model.entries.isEmpty {
                    placeholder(model.isLoadingEntries ? "Loading files" : "No readable files")
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                scrollSelectedEntry(animated: false)
            }
            .onChange(of: model.entries.map(\.url)) { _, _ in
                scrollSelectedEntry(animated: false)
            }
            .onChange(of: model.selectionScrollEvent?.id) { _, _ in
                scrollSelectionEvent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionOverlay: some View {
        GeometryReader { proxy in
            actionOverlayPane(
                maxHeight: max(0, proxy.size.height - FileBrowserActionPaneLayoutPolicy.outerPadding * 2)
            )
            .padding(FileBrowserActionPaneLayoutPolicy.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }

    private func actionOverlayPane(maxHeight: CGFloat) -> some View {
        ScrollViewReader { actionScrollProxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    FileBrowserActionSelectionSummary(
                        urls: model.activeSelectionURLs,
                        model: model
                    )

                    Divider()
                        .opacity(0.42)

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(model.focusableActions.enumerated()), id: \.element) { index, action in
                            ActionRow(
                                action: action,
                                isFocused: index == model.focusedActionIndex
                            )
                            .id(index)
                        }
                    }
                }
                .padding(FileBrowserActionPaneLayoutPolicy.padding)
                .frame(width: FileBrowserActionPaneLayoutPolicy.width)
            }
            .scrollIndicators(.hidden)
            .frame(width: FileBrowserActionPaneLayoutPolicy.width)
            .frame(maxHeight: maxHeight)
            .clipped()
            .glassEffect(.regular.interactive(false), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 14)
            .onAppear {
                scrollFocusedAction(in: actionScrollProxy, animated: false)
            }
            .onChange(of: model.focusedActionIndex) { _, _ in
                scrollFocusedAction(in: actionScrollProxy, animated: true)
            }
            .onChange(of: model.focusState) { _, _ in
                scrollFocusedAction(in: actionScrollProxy, animated: false)
            }
        }
    }

    private func scrollFocusedAction(in actionScrollProxy: ScrollViewProxy, animated: Bool) {
        guard model.focusState == .previewActions else { return }

        if animated {
            withAnimation(.easeInOut(duration: 0.14)) {
                actionScrollProxy.scrollTo(model.focusedActionIndex, anchor: .center)
            }
        } else {
            actionScrollProxy.scrollTo(model.focusedActionIndex, anchor: .center)
        }
    }

    private var transferHint: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text("Destination staged")
                .font(.callout.weight(.semibold))
            Text("Return confirms here. Escape cancels.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(false), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.accentColor.opacity(0.36), lineWidth: 1)
        }
        .shadow(color: Color.accentColor.opacity(0.24), radius: 18)
        .padding(.trailing, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    @ViewBuilder
    private var focusedOverlay: some View {
        switch model.focusState {
        case .renaming:
            RenameOverlay(model: model)
                .transition(.scale(scale: 0.97).combined(with: .opacity))
        case let .confirming(.transfer(transfer, destination)):
            ConfirmationOverlay(
                title: "Confirm \(transfer.displayName)",
                message: "Return \(transfer.confirmationVerb) the staged items into \(displayName(for: destination)). Escape returns to destination selection."
            )
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        case let .confirming(.trash(urls, step)):
            ConfirmationOverlay(
                title: step == 1 ? "Move to Trash?" : "Confirm Trash",
                message: step == 1
                    ? "Return continues. \(urls.count) item\(urls.count == 1 ? "" : "s") will be moved to Trash, never permanently deleted."
                    : "Return moves the selected item\(urls.count == 1 ? "" : "s") to Trash. Escape cancels."
            )
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        case let .confirming(.unmount(url)):
            ConfirmationOverlay(
                title: "Unmount \(displayName(for: url))?",
                message: "Return asks macOS to unmount this volume. Escape cancels."
            )
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        case let .confirming(.conflict(_, _, conflicts)):
            ConflictOverlay(conflicts: conflicts, focusedResolution: model.focusedConflictResolution)
                .transition(.scale(scale: 0.97).combined(with: .opacity))
        default:
            EmptyView()
        }
    }

    private func statusOverlay(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
            Text(message)
                .font(.caption.weight(.medium))
                .lineLimit(2)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(false), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.red.opacity(0.34), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 18)
    }

    private var isTransferPending: Bool {
        if case .transferPending = model.focusState {
            return true
        }
        return false
    }

    private var entriesReconstructionIdentity: AnyHashable {
        AnyHashable(model.entries.map(\.url.path).joined(separator: "\u{1F}"))
    }

    private var pinnedReconstructionIdentity: AnyHashable {
        AnyHashable(model.sidebarDirectories.map(\.path).joined(separator: "\u{1F}"))
    }

    private func preloadFileIcons() {
        let urls = FileIconPreloadPolicy.preloadURLs(
            entries: model.entries,
            pinnedDirectories: model.sidebarDirectories
        )
        guard !urls.isEmpty else { return }

        fileIconPreloadTask?.cancel()
        fileIconPreloadTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: FileIconPreloadPolicy.initialDelayNanoseconds)
            guard !Task.isCancelled else { return }

            for (index, url) in urls.enumerated() {
                if Task.isCancelled { return }
                _ = await IconCache.files.icon(for: url)

                if FileIconPreloadPolicy.shouldYield(afterLoadingItemAt: index) {
                    await Task.yield()
                }
            }
        }
    }

    private func scrollSelectedEntry(animated: Bool) {
        guard let url = model.selectedEntry?.url else { return }
        scrollEntry(url, anchor: .nearest, animated: animated)
    }

    private func scrollSelectionEvent() {
        guard let event = model.selectionScrollEvent,
              event.id != handledSelectionScrollEventID else {
            return
        }
        handledSelectionScrollEventID = event.id
        scrollEntry(event.url, anchor: event.anchor, animated: false)
    }

    private func scrollEntry(
        _ url: URL,
        anchor: FileBrowserSelectionScrollAnchor,
        animated: Bool
    ) {
        guard model.entries.contains(where: { $0.url == url }) else { return }
        let unitPoint = anchor.unitPoint

        if animated {
            withAnimation(.smooth(duration: 0.16)) {
                browseScrollTargetAnchor = unitPoint
                browseScrollTargetID = url
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                browseScrollTargetAnchor = unitPoint
                browseScrollTargetID = url
            }
        }
    }

    private func scrollFocusedPin(animated: Bool) {
        guard let url = model.focusedPinnedURL else { return }

        if animated {
            withAnimation(.smooth(duration: 0.16)) {
                pinnedScrollTargetID = url
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pinnedScrollTargetID = url
            }
        }
    }

    private func title(for directory: URL) -> String {
        let title = directory.lastPathComponent
        return title.isEmpty ? "/" : title
    }

    private func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

@available(macOS 26.0, *)
private struct FileBrowserActionSelectionSummary: View {
    let urls: [URL]
    @ObservedObject var model: FileBrowserModel

    private var rows: FileBrowserActionPaneSelectionRows {
        FileBrowserActionPaneSelectionPolicy.rows(for: urls)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.headline)

            if urls.count <= 1, let url = urls.first {
                singleSelectionSummary(url)
            } else {
                if FileBrowserActionPaneLayoutPolicy.usesCardStack(selectionCount: urls.count) {
                    FileBrowserSelectionCardStack(urls: urls, model: model)
                        .frame(width: FileBrowserActionPaneLayoutPolicy.contentWidth, height: FileBrowserActionPaneLayoutPolicy.cardStackHeight)
                }

                multipleSelectionSummary
            }
        }
        .frame(width: FileBrowserActionPaneLayoutPolicy.contentWidth, alignment: .leading)
    }

    private func singleSelectionSummary(_ url: URL) -> some View {
        HStack(spacing: 8) {
            FileIconView(url: url, model: model)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                boundedMarquee(url.lastPathComponent, font: .callout.weight(.semibold), height: 18, width: singleSelectionTextWidth)
                boundedMarquee(url.path, font: .caption, height: 16, width: singleSelectionTextWidth)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: FileBrowserActionPaneLayoutPolicy.contentWidth, alignment: .leading)
    }

    private var multipleSelectionSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(urls.count) selected")
                .font(.caption.monospacedDigit().weight(.semibold))

            if let parent = urls.first?.deletingLastPathComponent() {
                boundedMarquee(parent.path, font: .caption, height: 16)
                    .foregroundStyle(.secondary)
            }

            ForEach(rows.visible, id: \.self) { url in
                HStack(spacing: 6) {
                    FileIconView(url: url, model: model)
                        .frame(width: 16, height: 16)

                    FadeMarqueeText(
                        text: url.lastPathComponent,
                        font: .caption,
                        constrainedWidth: FileBrowserActionPaneLayoutPolicy.contentWidth - 22
                    )
                    .frame(width: FileBrowserActionPaneLayoutPolicy.contentWidth - 22, height: FileBrowserActionPaneLayoutPolicy.selectionRowHeight, alignment: .leading)
                }
                .frame(width: FileBrowserActionPaneLayoutPolicy.contentWidth, height: FileBrowserActionPaneLayoutPolicy.selectionRowHeight, alignment: .leading)
                .clipped()
            }

            if rows.remainingCount > 0 {
                Text("+ \(rows.remainingCount) more")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(height: FileBrowserActionPaneLayoutPolicy.selectionRowHeight)
            }
        }
    }

    private var singleSelectionTextWidth: CGFloat {
        FileBrowserActionPaneLayoutPolicy.contentWidth - 38
    }

    private func boundedMarquee(
        _ text: String,
        font: Font,
        height: CGFloat,
        width: CGFloat = FileBrowserActionPaneLayoutPolicy.contentWidth
    ) -> some View {
        FadeMarqueeText(
            text: text,
            font: font,
            constrainedWidth: width
        )
        .frame(width: width, height: height, alignment: .leading)
        .clipped()
    }
}

@available(macOS 26.0, *)
private struct FileBrowserSelectionCardStack: View {
    let urls: [URL]
    @ObservedObject var model: FileBrowserModel

    private var visibleURLs: [URL] {
        Array(urls.prefix(5))
    }

    var body: some View {
        ZStack {
            if visibleURLs.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.18))
            } else {
                ForEach(Array(visibleURLs.enumerated()), id: \.element) { index, url in
                    selectionCard(url)
                        .rotationEffect(.degrees(rotation(for: index)))
                        .offset(x: offset(for: index) * 22, y: yOffset(for: index))
                        .zIndex(Double(index))
                }

                if urls.count > visibleURLs.count {
                    Text("+\(urls.count - visibleURLs.count)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.22), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color.accentColor.opacity(0.36), lineWidth: 1)
                        }
                        .offset(x: 76, y: -18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectionCard(_ url: URL) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.36))
            .frame(width: 52, height: 46)
            .overlay {
                FileIconView(url: url, model: model)
                    .frame(width: 34, height: 34)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.36), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 5)
    }

    private func offset(for index: Int) -> CGFloat {
        CGFloat(index) - CGFloat(visibleURLs.count - 1) / 2
    }

    private func rotation(for index: Int) -> Double {
        Double(offset(for: index)) * 7
    }

    private func yOffset(for index: Int) -> CGFloat {
        abs(offset(for: index)) * 3
    }

}

@available(macOS 26.0, *)
private struct FileBrowserPaneWobbleEffect: GeometryEffect {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(phase * .pi * 2 * FileBrowserMotionPolicy.wobbleOscillations)
            * FileBrowserMotionPolicy.wobbleAmplitude
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

@available(macOS 26.0, *)
private extension FileBrowserSelectionScrollAnchor {
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
private struct FileBrowserRow: View {
    let entry: FileBrowserEntry
    let isSelected: Bool
    let isMarked: Bool
    let selectionTint: Color
    let selectionNamespace: Namespace.ID
    @ObservedObject var model: FileBrowserModel

    var body: some View {
        LauncherResultRow(
            isSelected: isSelected,
            isMarked: isMarked,
            selectionTint: selectionTint,
            markedTint: selectionTint,
            selectionNamespace: selectionNamespace,
            horizontalPadding: 12,
            verticalPadding: 8,
            minHeight: 42
        ) {
            HStack(spacing: 12) {
                FileIconView(url: entry.url, model: model)
                    .frame(width: 30, height: 30)

                FileBrowserRowNameText(
                    text: entry.name,
                    font: .system(size: 14, weight: .medium),
                    height: 18
                )
                    .layoutPriority(1)

                Spacer(minLength: 8)

                if isMarked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(selectionTint)
                    .frame(
                        width: FileBrowserRowFocusIndicatorPolicy.activeIndicatorWidth,
                        height: FileBrowserRowFocusIndicatorPolicy.activeIndicatorHeight
                    )
                    .padding(.leading, 6)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            NativeFileDragSourceView(
                url: entry.url,
                urlsProvider: {
                    FileBrowserDragPolicy.draggedURLs(for: entry.url, selectedURLs: model.selectedURLs)
                }
            )
                .accessibilityHidden(true)
        }
    }
}

@available(macOS 26.0, *)
private struct FileBrowserPinnedRow: View {
    let url: URL
    let isSelected: Bool
    let selectionTint: Color
    let selectionNamespace: Namespace.ID
    @ObservedObject var model: FileBrowserModel

    var body: some View {
        LauncherResultRow(
            isSelected: isSelected,
            selectionTint: selectionTint,
            selectionNamespace: selectionNamespace,
            horizontalPadding: 9,
            verticalPadding: 8,
            minHeight: 38
        ) {
            HStack(spacing: 8) {
                FileIconView(url: url, model: model)
                    .frame(width: 22, height: 22)

                FileBrowserRowNameText(
                    text: url.lastPathComponent,
                    font: .system(size: 13, weight: .medium),
                    height: 17
                )
                    .layoutPriority(1)
            }
        }
        .overlay {
            NativeFileDragSourceView(
                url: url,
                urlsProvider: { [url] }
            )
                .accessibilityHidden(true)
        }
    }
}

@available(macOS 26.0, *)
private struct FileBrowserRowNameText: View {
    let text: String
    let font: Font
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            FadeMarqueeText(
                text: text,
                font: font,
                constrainedWidth: max(0, proxy.size.width)
            )
            .foregroundStyle(.primary)
            .frame(width: proxy.size.width, height: height, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
    }
}

@available(macOS 26.0, *)
private struct ActionRow: View {
    let action: FileBrowserAction
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(isFocused ? .primary : .secondary)

            Text(action.displayName)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            if isFocused {
                Image(systemName: "return")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isFocused ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.24) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.38) : .clear, lineWidth: 1)
        }
    }
}

@available(macOS 26.0, *)
private struct RenameOverlay: View {
    @ObservedObject var model: FileBrowserModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: state?.mode == .batch ? "textformat.123" : "pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state?.mode == .batch ? "Batch Rename" : "Rename")
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Name", text: Binding(
                get: { state?.proposedName ?? "" },
                set: { model.setRenameText($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit {
                model.handle(.open)
            }

            Text("Return confirms. Escape cancels.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 340)
        .glassEffect(.regular.interactive(false), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.26), radius: 28, x: 0, y: 16)
        .onAppear {
            isFocused = true
        }
    }

    private var state: FileBrowserRenameState? {
        model.renameState
    }

    private var subtitle: String {
        guard let state else { return "" }
        switch state.mode {
        case .single:
            return state.urls.first?.lastPathComponent ?? ""
        case .batch:
            return "\(state.urls.count) items, numbered suffixes"
        }
    }
}

@available(macOS 26.0, *)
private struct ConfirmationOverlay: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Return confirms. Escape cancels.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 340)
        .glassEffect(.regular.interactive(false), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.26), radius: 28, x: 0, y: 16)
    }
}

@available(macOS 26.0, *)
private struct ConflictOverlay: View {
    let conflicts: [FileBrowserConflict]
    let focusedResolution: FileBrowserConflictResolution

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name Conflict")
                    .font(.headline)
                Text(conflictSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(spacing: 5) {
                ForEach(FileBrowserConflictResolution.allCases, id: \.self) { resolution in
                    ConflictResolutionRow(
                        resolution: resolution,
                        isFocused: resolution == focusedResolution
                    )
                }
            }

            Text("Up and Down choose. Return applies.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 340)
        .glassEffect(.regular.interactive(false), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.26), radius: 28, x: 0, y: 16)
    }

    private var conflictSummary: String {
        guard let first = conflicts.first else {
            return "A destination already contains an item with the same name."
        }
        let extraCount = conflicts.count - 1
        let suffix = extraCount > 0 ? " and \(extraCount) more" : ""
        return "\(first.destination.lastPathComponent)\(suffix)"
    }
}

@available(macOS 26.0, *)
private struct ConflictResolutionRow: View {
    let resolution: FileBrowserConflictResolution
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: resolution.symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(isFocused ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(resolution.displayName)
                    .font(.system(size: 14, weight: .medium))
                Text(resolution.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isFocused {
                Image(systemName: "return")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isFocused ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.24) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.38) : .clear, lineWidth: 1)
        }
    }
}

@available(macOS 26.0, *)
struct QuickLookPreviewSurface: View {
    @ObservedObject var model: FileBrowserModel
    let preview: FileBrowserPreview
    let entry: FileBrowserEntry?
    @State private var nativePreviewFailed = false

    var body: some View {
        GeometryReader { proxy in
            let surfaceSize = FileBrowserPreviewLayoutPolicy.surfaceSize(
                for: resolvedMode,
                availableSize: proxy.size
            )
            let contentSize = FileBrowserPreviewLayoutPolicy.contentSize(surfaceSize: surfaceSize)

            previewContent(size: contentSize)
                .padding(FileBrowserPreviewLayoutPolicy.surfacePadding)
                .frame(width: surfaceSize.width, height: surfaceSize.height)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.30), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 34, x: 0, y: 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .onChange(of: preview.url) {
                    nativePreviewFailed = false
                }
            }
        }

    private var resolvedMode: FileBrowserPreviewMode {
        if preview.mode == .nativeThumbnail, nativePreviewFailed {
            return .metadataFallback
        }
        return preview.mode
    }

    @ViewBuilder
    private func previewContent(size: CGSize) -> some View {
        switch resolvedMode {
        case .nativeThumbnail:
            nativePreview(size: size)
        case .video:
            videoPreview(size: size)
        case .codeText:
            codePreview(size: size)
        case .metadataFallback:
            metadataPreview(size: size)
        }
    }

    private func nativePreview(size: CGSize) -> some View {
        let previewAreaHeight = FileBrowserPreviewLayoutPolicy.previewAreaHeight(
            for: .nativeThumbnail,
            contentSize: size
        )

        return ZStack(alignment: .bottomLeading) {
            NativeQuickLookThumbnailView(
                url: preview.url,
                thumbnailSize: CGSize(width: size.width, height: previewAreaHeight),
                model: model,
                didFail: $nativePreviewFailed
            )
                .frame(width: size.width, height: previewAreaHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 1)
                }

            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 118)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 5) {
                previewTitle(width: max(0, titleWidth(for: size) - 28))
                previewPath(width: max(0, titleWidth(for: size) - 28))
            }
            .padding(14)
        }
    }

    private func videoPreview(size: CGSize) -> some View {
        VStack(spacing: 12) {
            AutoPlayingVideoPreview(url: preview.url)
                .frame(width: size.width, height: FileBrowserPreviewLayoutPolicy.previewAreaHeight(for: .video, contentSize: size))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 1)
                }

            previewTitle(width: titleWidth(for: size))
            previewPath(width: titleWidth(for: size))
        }
    }

    private func codePreview(size: CGSize) -> some View {
        VStack(spacing: 12) {
            CodeTextFilePreview(url: preview.url)
                .frame(width: size.width, height: FileBrowserPreviewLayoutPolicy.previewAreaHeight(for: .codeText, contentSize: size))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 1)
                }

            previewTitle(width: titleWidth(for: size))
            previewPath(width: titleWidth(for: size))
        }
    }

    private func metadataPreview(size: CGSize) -> some View {
        VStack(spacing: 12) {
            FileIconView(url: preview.url, model: model)
                .frame(width: 72, height: 72)

            previewTitle(width: titleWidth(for: size))

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                metadataRow("Kind", entry?.kind.displayName ?? "Unknown")
                metadataRow("Size", formattedSize)
                metadataRow("Created", formattedDate(entry?.createdAt))
                metadataRow("Modified", formattedDate(entry?.modifiedAt))
            }
            .font(.caption)

            previewPath(width: titleWidth(for: size))
        }
    }

    private func previewTitle(width: CGFloat) -> some View {
        FadeMarqueeText(
            text: preview.url.lastPathComponent,
            font: .headline,
            constrainedWidth: width
        )
        .frame(width: width, height: 22, alignment: .leading)
    }

    private func previewPath(width: CGFloat) -> some View {
        FadeMarqueeText(
            text: preview.url.path,
            font: .caption,
            constrainedWidth: width
        )
        .foregroundStyle(.secondary)
        .frame(width: width, height: 16, alignment: .leading)
    }

    private func titleWidth(for size: CGSize) -> CGFloat {
        max(0, size.width)
    }

    private var formattedSize: String {
        guard let size = entry?.size else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return Self.dateFormatter.string(from: date)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

@available(macOS 26.0, *)
private struct AutoPlayingVideoPreview: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .background(Color.black)
            .onAppear {
                startPlayback()
            }
            .onDisappear {
                player?.pause()
            }
            .onChange(of: url) {
                startPlayback()
            }
    }

    private func startPlayback() {
        let nextPlayer = AVPlayer(url: url)
        player?.pause()
        player = nextPlayer
        nextPlayer.play()
    }
}

@available(macOS 26.0, *)
private struct CodeTextFilePreview: View {
    let url: URL
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(errorMessage ?? text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(nsColor: errorMessage == nil
                    ? FileBrowserCodePreviewTheme.foreground
                    : FileBrowserCodePreviewTheme.secondaryForeground))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .background(Color(nsColor: FileBrowserCodePreviewTheme.background))
        .task(id: url) {
            text = "Loading preview..."
            errorMessage = nil
            do {
                let loadedText = try await Task.detached(priority: .utility) {
                    try FileBrowserTextPreviewLoader.loadSnippet(from: url)
                }.value
                guard !Task.isCancelled else { return }
                text = loadedText
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                text = ""
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum FileBrowserTextPreviewLoader {
    static let maxPreviewBytes = 64 * 1024
    static let maxRenderedLineLength = 240

    static func loadSnippet(from url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let data = try handle.read(upToCount: maxPreviewBytes + 1) ?? Data()
        let isTruncated = data.count > maxPreviewBytes
        let previewData = data.prefix(maxPreviewBytes)
        let text = wrapLongLines(String(decoding: previewData, as: UTF8.self))

        if isTruncated {
            return text + "\n\n... preview truncated ..."
        }

        return text
    }

    static func wrapLongLines(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count + text.count / maxRenderedLineLength)
        var lineLength = 0

        for character in text {
            if character == "\n" {
                output.append(character)
                lineLength = 0
                continue
            }

            if lineLength >= maxRenderedLineLength {
                output.append("\n")
                lineLength = 0
            }

            output.append(character)
            lineLength += 1
        }

        return output
    }
}

@available(macOS 26.0, *)
private struct NativeQuickLookThumbnailView: NSViewRepresentable {
    let url: URL
    let thumbnailSize: CGSize
    @ObservedObject var model: FileBrowserModel
    @Binding var didFail: Bool

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        context.coordinator.loadThumbnail(
            for: url,
            thumbnailSize: thumbnailSize,
            model: model,
            into: imageView,
            didFail: $didFail
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var representedURL: URL?
        private var representedSize = CGSize.zero

        @MainActor
        func loadThumbnail(
            for url: URL,
            thumbnailSize: CGSize,
            model: FileBrowserModel,
            into imageView: NSImageView,
            didFail: Binding<Bool>
        ) {
            guard representedURL != url || representedSize != thumbnailSize else { return }
            representedURL = url
            representedSize = thumbnailSize
            imageView.image = nil
            didFail.wrappedValue = false

            let scale = NSScreen.main?.backingScaleFactor ?? 2
            model.loadPreviewThumbnail(for: url, size: thumbnailSize, scale: scale) { image in
                guard self.representedURL == url, self.representedSize == thumbnailSize else { return }
                if let image {
                    imageView.image = image
                } else {
                    didFail.wrappedValue = true
                }
            }
        }
    }
}

@available(macOS 26.0, *)
struct FileIconPreloadPolicy {
    static let preloadLimit = 768
    static let initialDelayNanoseconds: UInt64 = 30_000_000
    static let yieldStride = 24

    static func preloadURLs(entries: [FileBrowserEntry], pinnedDirectories: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var urls: [URL] = []

        for url in pinnedDirectories + entries.map(\.url) {
            guard FileBrowserIconPolicy.systemSymbolOverride(for: url) == nil else { continue }
            let key = url.standardizedFileURL.path
            guard seenPaths.insert(key).inserted else { continue }

            urls.append(url)
            if urls.count == preloadLimit { break }
        }

        return urls
    }

    static func shouldYield(afterLoadingItemAt index: Int) -> Bool {
        (index + 1) % yieldStride == 0
    }
}

@available(macOS 26.0, *)
private struct FileIconView: View {
    let url: URL
    @ObservedObject var model: FileBrowserModel
    @State private var icon: NSImage?

    var body: some View {
        ZStack {
            if let symbol = FileBrowserIconPolicy.systemSymbolOverride(for: url) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            await loadIcon()
        }
    }

    @MainActor
    private func loadIcon() async {
        guard FileBrowserIconPolicy.systemSymbolOverride(for: url) == nil else {
            icon = nil
            return
        }

        if let cachedIcon = await IconCache.files.cachedIcon(for: url) {
            icon = cachedIcon
            return
        }

        icon = nil
        let loadedIcon = await IconCache.files.icon(for: url)
        guard !Task.isCancelled else { return }
        icon = loadedIcon
    }
}

private extension FileBrowserAction {
    var displayName: String {
        switch self {
        case .open:
            return "Open"
        case .rename:
            return "Rename"
        case .batchRename:
            return "Batch Rename"
        case .revealInFinder:
            return "Reveal in Finder"
        case .copyPath:
            return "Copy Path"
        case .copyPaths:
            return "Copy Paths"
        case .copy:
            return "Copy"
        case .move:
            return "Move"
        case .moveToTrash:
            return "Move to Trash"
        case .unmount:
            return "Unmount"
        }
    }

    var symbol: String {
        switch self {
        case .open:
            return "arrow.up.right.square"
        case .rename, .batchRename:
            return "pencil"
        case .revealInFinder:
            return "finder"
        case .copyPath, .copyPaths:
            return "doc.on.doc"
        case .copy:
            return "plus.square.on.square"
        case .move:
            return "arrow.right.square"
        case .moveToTrash:
            return "trash"
        case .unmount:
            return "eject"
        }
    }
}

private extension FileBrowserTransfer {
    var displayName: String {
        switch self {
        case .copy:
            return "Copy"
        case .move:
            return "Move"
        }
    }

    var confirmationVerb: String {
        switch self {
        case .copy:
            return "copies"
        case .move:
            return "moves"
        }
    }
}

private extension FileBrowserConflictResolution {
    var displayName: String {
        switch self {
        case .keepBoth:
            return "Keep Both"
        case .replace:
            return "Replace"
        case .cancel:
            return "Cancel"
        }
    }

    var detail: String {
        switch self {
        case .keepBoth:
            return "Create a numbered copy"
        case .replace:
            return "Overwrite the destination item"
        case .cancel:
            return "Leave files unchanged"
        }
    }

    var symbol: String {
        switch self {
        case .keepBoth:
            return "plus.square.on.square"
        case .replace:
            return "arrow.triangle.2.circlepath"
        case .cancel:
            return "xmark.circle"
        }
    }
}

private extension FileBrowserEntry.Kind {
    var displayName: String {
        switch self {
        case .file:
            return "File"
        case .directory:
            return "Directory"
        case .package:
            return "Package"
        case .symbolicLink:
            return "Alias"
        case .other:
            return "Other"
        }
    }
}
