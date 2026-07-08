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
    @State private var scrollTargetID: ResultRowID?
    @State private var scrollTargetAnchor: UnitPoint?
    @State private var renderedDictionaryPreview: DictionaryDefinitionPreview?
    @State private var isDictionaryPreviewVisible = false

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

    private var dictionaryPreviewAnimation: Animation {
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
            synchronizeDictionaryPreview(animated: false)
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
                synchronizeDictionaryPreview(animated: false)
                preloadApplicationIcons()
            } else {
                isSearchFocused = false
                clearRenderedDictionaryPreview()
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
        .onChange(of: model.dictionaryPreview) { _, _ in
            synchronizeDictionaryPreview(animated: true)
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
        HelpView(globalHotKeyTitle: settingsModel.hotKeyTitle, onBack: {
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
            guard model.isPresented,
                  !model.isShowingSettings,
                  !model.isShowingHelp,
                  model.mode.acceptsTextInput else { return }
            isSearchFocused = true
        }
    }

    private func synchronizeDictionaryPreview(animated: Bool) {
        if let dictionaryPreview = model.dictionaryPreview {
            renderedDictionaryPreview = dictionaryPreview
            if animated {
                withAnimation(dictionaryPreviewAnimation) {
                    isDictionaryPreviewVisible = true
                }
            } else {
                isDictionaryPreviewVisible = true
            }
            return
        }

        if animated {
            withAnimation(dictionaryPreviewAnimation) {
                isDictionaryPreviewVisible = false
            }
            let closingPreview = renderedDictionaryPreview
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                guard model.dictionaryPreview == nil,
                      renderedDictionaryPreview == closingPreview else {
                    return
                }
                renderedDictionaryPreview = nil
            }
        } else {
            clearRenderedDictionaryPreview()
        }
    }

    private func clearRenderedDictionaryPreview() {
        renderedDictionaryPreview = nil
        isDictionaryPreviewVisible = false
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

            if model.isApplicationDictionaryActive, let loadingTerm = model.dictionaryPreviewLoadingTerm {
                DictionaryPreviewSkeleton(term: loadingTerm, tint: LauncherModeTintPolicy.panelColor(for: .dictionary(term: loadingTerm)))
                    .transition(.opacity)
            } else if let dictionaryPreview = renderedDictionaryPreview {
                DictionaryDefinitionPreviewOverlay(preview: dictionaryPreview, tint: LauncherModeTintPolicy.panelColor(for: .dictionary(term: dictionaryPreview.term)))
                    .opacity(isDictionaryPreviewVisible ? 1 : 0)
                    .scaleEffect(isDictionaryPreviewVisible ? 1 : 0.985)
                    .allowsHitTesting(isDictionaryPreviewVisible)
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
                    .tint(resultsPaneTint.opacity(LauncherVisualStyle.resultsPaneModeTintOpacity))
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

    private var resultsPaneTint: Color {
        if model.isApplicationDictionaryActive {
            return LauncherModeTintPolicy.panelColor(for: model.applicationQueryRoute)
        }
        if model.isApplicationCalculatorActive {
            return LauncherModeTintPolicy.panelColor(for: model.applicationQueryRoute)
        }
        return LauncherModeTintPolicy.panelColor(for: model.mode)
    }

    private var resultsPaneShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LauncherVisualStyle.resultsPaneCornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var results: some View {
        if model.mode == .files {
            if let fileBrowserModel = model.activeFileBrowserModel {
                FileBrowserView(
                    model: fileBrowserModel,
                    selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode)
                )
                    .transition(.opacity)
            } else {
                Text("Loading files")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        await Task.yield()
                        model.prepareFileBrowserMode()
                    }
            }
        } else if model.isDictionaryLookupLoading {
            resultScrollView(reconstructionID: "dictionary-loading", usesEagerRows: true) {
                ForEach(0..<4, id: \.self) { _ in
                    LauncherAppsResultSkeletonRow()
                }
            }
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
                    if model.isApplicationToolActive {
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
                    } else {
                        resultScrollView(reconstructionID: applicationsReconstructionIdentity) {
                            ForEach(Array(model.filteredItemIDs.enumerated()), id: \.element) { index, id in
                                if let item = model.item(for: id) {
                                    applicationRow(item: item, id: id, index: index)
                                }
                            }
                        }
                    }
                case .files:
                    if let fileBrowserModel = model.activeFileBrowserModel {
                        FileBrowserView(
                            model: fileBrowserModel,
                            selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode)
                        )
                    } else {
                        Text("Loading files")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .task {
                                await Task.yield()
                                model.prepareFileBrowserMode()
                            }
                    }
                }
            }
        }
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

    private func applicationRow(item: LaunchItem, id: AppRowID, index: Int) -> some View {
        let rowID = ResultRowID.application(id)
        let isSelected = index == model.selectedIndex

        return LauncherAppsResultRow(
            isSelected: isSelected,
            selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode),
            selectionNamespace: selectionGlassNamespace,
            onActivate: {
                model.selectedIndex = index
                _ = model.handle(command: .open)
            },
            leading: {
                ApplicationIconView(url: item.url)
            },
            details: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            },
            metadata: {
                Text(item.category.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .accessibilityLabel("Result type: \(item.category.title)")
            },
            action: {
                Button {
                    model.exclude(item)
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
            }
        )
        .id(rowID)
    }

    private func toolRow(item: ToolItem, index: Int) -> some View {
        let rowID = ResultRowID.tool(item)
        let isSelected = index == model.selectedIndex
        let actionConfiguration = toolActionConfiguration(for: item)

        return LauncherAppsResultRow(
            isSelected: isSelected,
            selectionTint: LauncherModeTintPolicy.selectionColor(for: model.mode),
            selectionNamespace: selectionGlassNamespace,
            onActivate: {
                model.selectedIndex = index
                _ = model.handle(command: .open)
            },
            leading: {
                Image(systemName: toolSymbol(for: item.kind))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(toolColor(for: item.kind))
                    .frame(width: 38, height: 38)
            },
            details: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: item.kind == .calculation ? 26 : 18, weight: .semibold, design: item.kind == .calculation ? .rounded : .default))
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            },
            metadata: {
                EmptyView()
            },
            action: {
                if let actionConfiguration {
                    Button {
                        model.selectedIndex = index
                        performToolRowAction(actionConfiguration.action, item: item)
                    } label: {
                        Image(systemName: actionConfiguration.symbol)
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
        )
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
            if model.isApplicationToolActive {
                guard index >= 0, index < model.toolItems.count else { return nil }
                return .tool(model.toolItems[index])
            }

            guard index >= 0, index < model.filteredItemIDs.count else { return nil }
            return .application(model.filteredItemIDs[index])
        case .files:
            guard index >= 0, index < model.fileBrowserModel.entries.count else { return nil }
            return .file(model.fileBrowserModel.entries[index].url)
        }
    }

    private var toolResultTransition: AnyTransition {
        .opacity.combined(with: .move(edge: .top))
    }

    private var applicationsReconstructionIdentity: AnyHashable {
        AnyHashable(model.filteredItemIDs.map { "\($0.rawValue)" }.joined(separator: "\u{1F}"))
    }

    private var toolResultsSnapshotIdentity: String {
        model.toolItems.map { item in
            "\(item.kind)|\(item.title)|\(item.subtitle)|\(item.copyText ?? "")|\(item.inputText ?? "")|\(item.previewText ?? "")"
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
        case .calculation:
            guard item.copyText != nil else { return nil }
            return RowActionConfiguration(symbol: "doc.on.doc", help: "Copy result", action: .open)
        case .calculationHistory:
            guard item.inputText != nil else { return nil }
            return RowActionConfiguration(symbol: "pencil", help: "Edit calculation", action: .open)
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
        let urls = AppIconPreloadPolicy.preloadURLs(for: model.filteredIconURLs)
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
private struct DictionaryPreviewSkeleton: View {
    let term: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(term).font(.title2.weight(.semibold)).foregroundStyle(tint)
            RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.14)).frame(height: 18)
            RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.10)).frame(height: 72)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .redacted(reason: .placeholder)
    }
}

@available(macOS 26.0, *)
private struct DictionaryDefinitionPreviewOverlay: View {
    let preview: DictionaryDefinitionPreview
    let tint: Color

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)

                Text(preview.term)
                    .font(.system(size: 22, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 12)
            }

            Divider()

            ScrollView {
                DictionaryFormattedDefinitionView(
                    previewTerm: preview.term,
                    sections: DictionaryDefinitionFormatter.sections(from: preview.definition, term: preview.term),
                    tint: tint
                )
            }
            .scrollIndicators(.visible)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            shape
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.34))
                .glassEffect(.regular.tint(tint.opacity(0.10)).interactive(false), in: shape)
        }
        .overlay {
            shape
                .strokeBorder(LauncherVisualStyle.resultsPaneRim.opacity(0.26), lineWidth: 1)
        }
        .padding(LauncherVisualStyle.resultsPaneContentInset * 2)
        .accessibilityElement(children: .combine)
    }
}

@available(macOS 26.0, *)
private enum DictionaryPreviewLayout {
    static let imageFlowHeight: CGFloat = 156
}

@available(macOS 26.0, *)
private struct DictionaryImageFlowSection: View {
    let term: String
    let imageSearchURL: URL?
    let tint: Color
    @State private var imageURLs: [URL] = []
    @State private var isLoadingImages = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Wikimedia Commons", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)

                Spacer(minLength: 8)

                if let imageSearchURL {
                    Button {
                        NSWorkspace.shared.open(imageSearchURL)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Open Wikimedia Commons images for \(term)")
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.08))

                if !imageURLs.isEmpty {
                    DictionaryImageCarousel(imageURLs: imageURLs, tint: tint)
                } else if isLoadingImages {
                    DictionaryImageCarouselSkeleton(tint: tint)
                } else {
                    Text("No image results")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: DictionaryPreviewLayout.imageFlowHeight)
        }
        .task(id: term) {
            isLoadingImages = true
            imageURLs = await CommonsImageSearchClient.shared.imageURLs(for: term)
            isLoadingImages = false
        }
    }
}

@available(macOS 26.0, *)
private struct DictionaryImageCarousel: View {
    let imageURLs: [URL]
    let tint: Color

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(imageURLs, id: \.self) { url in
                    DictionaryRemoteImageView(url: url)
                        .frame(width: 118, height: DictionaryPreviewLayout.imageFlowHeight - 24)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(tint.opacity(0.16), lineWidth: 1)
                        }
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
    }
}

@available(macOS 26.0, *)
private struct DictionaryRemoteImageView: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                Color.secondary.opacity(0.14)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Image(systemName: "photo")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.10))
            @unknown default:
                Color.secondary.opacity(0.10)
            }
        }
    }
}

@available(macOS 26.0, *)
private struct DictionaryImageCarouselSkeleton: View {
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 118, height: DictionaryPreviewLayout.imageFlowHeight - 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

@available(macOS 26.0, *)
private struct DictionaryFormattedDefinitionView: View {
    let previewTerm: String
    let sections: [DictionaryDefinitionSection]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(sections) { section in
                DictionaryDefinitionVariantCard(
                    section: section,
                    imageTerm: section.imageSearchTerm(for: previewTerm),
                    imageSearchURL: DictionaryDefinitionPreview.commonsImageSearchURL(for: section.imageSearchTerm(for: previewTerm)),
                    tint: tint
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.trailing, 6)
    }
}

@available(macOS 26.0, *)
private struct DictionaryDefinitionVariantCard: View {
    let section: DictionaryDefinitionSection
    let imageTerm: String
    let imageSearchURL: URL?
    let tint: Color

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Divider().opacity(0.42)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(section.items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.marker ?? (item.kind == .subdefinition ? "•" : ""))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .trailing)

                        definitionItemText(item)
                    }
                }
            }

            DictionaryImageFlowSection(term: imageTerm, imageSearchURL: imageSearchURL, tint: tint)
        }
        .padding(14)
        .background {
            shape
                .fill(tint.opacity(0.055))
                .glassEffect(.regular.tint(tint.opacity(0.07)).interactive(false), in: shape)
        }
        .overlay {
            shape
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func definitionItemText(_ item: DictionaryDefinitionSection.Item) -> some View {
        if item.kind == .example {
            Text(item.text)
                .font(.system(size: 14, weight: .regular))
                .italic()
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .textSelection(.enabled)
        } else {
            Text(item.text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .textSelection(.enabled)
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
    case application(AppRowID)
    case tool(ToolItem)
    case file(URL)
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

@available(macOS 26.0, *)
private actor AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlightTasks: [String: Task<NSImage, Never>] = [:]
    private var activeLoadCount = 0
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private let maxConcurrentLoads = 4

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
