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
    @State private var isHeaderHovered = false
    @State private var hoveredHeaderControlID: HeaderGlassEffectID?
    @State private var hoveredRowActionID: ResultRowID?
    @State private var activatingRowActionID: ResultRowID?

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

    private var headerInteractionState: LauncherHeaderInteractionState {
        LauncherHeaderInteractionState(
            isHovered: isHeaderHovered,
            isFocused: isSearchFocused,
            isIndexing: model.isIndexing && model.mode == .applications
        )
    }

    private var resultsLayoutMetrics: LauncherResultsLayoutMetrics {
        .standard
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
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var header: some View {
        let interactionState = headerInteractionState

        return HStack(spacing: 12) {
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
            headerBackdrop(interactionState)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(interactionState.borderOpacity), lineWidth: 1)
        }
        .shadow(color: .black.opacity(interactionState.depthShadowOpacity), radius: interactionState.depthShadowRadius, x: 0, y: interactionState.depthShadowY)
        .shadow(color: .accentColor.opacity(interactionState.glowOpacity), radius: interactionState.isActive ? 22 : 0, x: 0, y: 0)
        .onHover { isHovered in
            updateHeaderHover(isHovered)
        }
        .animation(headerControlAnimation, value: interactionState)
    }

    private func headerBackdrop(_ interactionState: LauncherHeaderInteractionState) -> some View {
        GlassEffectContainer(spacing: 0) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.clear)
                .glassEffect(
                    .regular.tint(.accentColor.opacity(interactionState.tintOpacity)).interactive(),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
        }
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            if model.mode == .tools {
                let controlState = headerControlState(.clearHistory, isEnabled: model.canClearHistory)

                Button {
                    _ = model.handle(command: .clearHistory)
                } label: {
                    headerControlIcon(symbol: "trash", filledSymbol: "trash.fill", state: controlState)
                }
                .buttonStyle(.glass(.regular.tint(.accentColor.opacity(controlState.tintOpacity))))
                .disabled(!model.canClearHistory)
                .help("Clear calculation history")
                .glassEffectID(HeaderGlassEffectID.clearHistory, in: headerGlassNamespace)
                .glassEffectTransition(.materialize)
                .launcherHeaderControlDepth(controlState)
                .onHover { isHovered in
                    updateHoveredHeaderControl(.clearHistory, isHovered: isHovered)
                }
                .animation(headerControlAnimation, value: controlState)
            }

            toolsModeControl
            pinControl
        }
        .animation(headerControlAnimation, value: model.mode)
        .animation(headerControlAnimation, value: model.isPinned)
    }

    @ViewBuilder
    private var toolsModeControl: some View {
        let controlState = headerControlState(.toolsMode)

        if model.mode == .tools {
            Button {
                _ = model.handle(command: .toggleToolsMode)
            } label: {
                headerControlIcon(symbol: "wrench.and.screwdriver.fill", state: controlState)
            }
            .buttonStyle(.glassProminent)
            .help("Tools (Command+/)")
            .glassEffectID(HeaderGlassEffectID.toolsMode, in: headerGlassNamespace)
            .glassEffectTransition(.matchedGeometry)
            .launcherHeaderControlDepth(controlState)
            .onHover { isHovered in
                updateHoveredHeaderControl(.toolsMode, isHovered: isHovered)
            }
            .animation(headerControlAnimation, value: controlState)
        } else {
            Button {
                _ = model.handle(command: .toggleToolsMode)
            } label: {
                headerControlIcon(symbol: "wrench.and.screwdriver", filledSymbol: "wrench.and.screwdriver.fill", state: controlState)
            }
            .buttonStyle(.glass(.regular.tint(.accentColor.opacity(controlState.tintOpacity))))
            .help("Tools (Command+/)")
            .glassEffectID(HeaderGlassEffectID.toolsMode, in: headerGlassNamespace)
            .glassEffectTransition(.matchedGeometry)
            .launcherHeaderControlDepth(controlState)
            .onHover { isHovered in
                updateHoveredHeaderControl(.toolsMode, isHovered: isHovered)
            }
            .animation(headerControlAnimation, value: controlState)
        }
    }

    @ViewBuilder
    private var pinControl: some View {
        let controlState = headerControlState(.pin)

        if model.isPinned {
            Button {
                _ = model.handle(command: .togglePin)
            } label: {
                headerControlIcon(symbol: "pin.fill", state: controlState)
            }
            .buttonStyle(.glassProminent)
            .help("Unpin window (Command+P)")
            .glassEffectID(HeaderGlassEffectID.pin, in: headerGlassNamespace)
            .glassEffectTransition(.matchedGeometry)
            .launcherHeaderControlDepth(controlState)
            .onHover { isHovered in
                updateHoveredHeaderControl(.pin, isHovered: isHovered)
            }
            .animation(headerControlAnimation, value: controlState)
        } else {
            Button {
                _ = model.handle(command: .togglePin)
            } label: {
                headerControlIcon(symbol: "pin", filledSymbol: "pin.fill", state: controlState)
            }
            .buttonStyle(.glass(.regular.tint(.accentColor.opacity(controlState.tintOpacity))))
            .help("Pin window (Command+P)")
            .glassEffectID(HeaderGlassEffectID.pin, in: headerGlassNamespace)
            .glassEffectTransition(.matchedGeometry)
            .launcherHeaderControlDepth(controlState)
            .onHover { isHovered in
                updateHoveredHeaderControl(.pin, isHovered: isHovered)
            }
            .animation(headerControlAnimation, value: controlState)
        }
    }

    private func headerControlIcon(
        symbol: String,
        filledSymbol: String? = nil,
        state: LauncherHeaderControlInteractionState
    ) -> some View {
        ZStack {
            Image(systemName: symbol)
                .frame(width: 18, height: 18)

            if let filledSymbol {
                Image(systemName: filledSymbol)
                    .frame(width: 18, height: 18)
                    .opacity(state.fillSymbolOpacity)
            }
        }
        .opacity(state.symbolOpacity)
    }

    private func headerControlState(
        _ controlID: HeaderGlassEffectID,
        isEnabled: Bool = true
    ) -> LauncherHeaderControlInteractionState {
        LauncherHeaderControlInteractionState(
            isHovered: hoveredHeaderControlID == controlID,
            isEnabled: isEnabled
        )
    }

    private func updateHoveredHeaderControl(_ controlID: HeaderGlassEffectID, isHovered: Bool) {
        withAnimation(headerControlAnimation) {
            if isHovered {
                hoveredHeaderControlID = controlID
            } else if hoveredHeaderControlID == controlID {
                hoveredHeaderControlID = nil
            }
        }
    }

    private func updateHeaderHover(_ isHovered: Bool) {
        withAnimation(headerControlAnimation) {
            isHeaderHovered = isHovered
            if !isHovered {
                hoveredHeaderControlID = nil
            }
        }
    }

    private var results: some View {
        let metrics = resultsLayoutMetrics

        return ZStack {
            resultsBackdrop
            resultContent
        }
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(metrics.cornerRadius), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(metrics.cornerRadius), style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(metrics.cornerRadius), style: .continuous)
                .strokeBorder(Color.black.opacity(0.16), lineWidth: 1)
                .blendMode(.multiply)
        }
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(metrics.cornerRadius), style: .continuous)
                .strokeBorder(Color.black.opacity(0.30), lineWidth: 2)
                .shadow(color: .black.opacity(0.46), radius: 7, x: 0, y: 3)
                .blur(radius: 1.5)
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(metrics.cornerRadius), style: .continuous))
                .blendMode(.multiply)
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
                    .regular.tint(Color.black.opacity(resultsLayoutMetrics.insetBackingTintOpacity)),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
        }
    }

    private func resultScrollView<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        let metrics = resultsLayoutMetrics

        return ScrollView(.vertical, showsIndicators: metrics.scrollIndicatorsAreVisible) {
            LazyVStack(spacing: CGFloat(metrics.rowSpacing)) {
                content()
            }
            .scrollTargetLayout()
            .frame(maxWidth: .infinity)
            .animation(resultUpdateAnimation, value: resultListIdentity)
        }
        .contentMargins(.leading, CGFloat(metrics.rowHorizontalInset), for: .scrollContent)
        .contentMargins(.trailing, CGFloat(metrics.rowTrailingInset), for: .scrollContent)
        .contentMargins(.vertical, CGFloat(metrics.rowVerticalInset), for: .scrollContent)
        .contentMargins(.vertical, CGFloat(metrics.scrollbarVerticalInset), for: .scrollIndicators)
        .scrollPosition(id: $scrollTargetID, anchor: scrollTargetAnchor)
        .scrollIndicators(metrics.scrollIndicatorsAreVisible ? .automatic : .hidden)
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
        let interactionState = LauncherRowInteractionState(
            isSelected: index == model.selectedIndex,
            isHovered: hoveredRowID == rowID
        )
        let actionState = LauncherRowActionInteractionState(
            isHovered: hoveredRowActionID == rowID,
            isActive: activatingRowActionID == rowID,
            isEnabled: interactionState.revealsAuxiliaryAction || activatingRowActionID == rowID
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
                activateExclude(item, rowID: rowID)
            } label: {
                rowActionIcon(symbol: "eye.slash", filledSymbol: "eye.slash.fill", state: actionState)
            }
            .buttonStyle(.glass(.regular.tint(.accentColor.opacity(actionState.tintOpacity))))
            .foregroundStyle(.secondary)
            .help("Hide from results")
            .glassEffectTransition(.materialize)
            .launcherRowActionDepth(actionState)
            .opacity(actionState.isEnabled ? 1 : 0)
            .allowsHitTesting(actionState.isEnabled && activatingRowActionID != rowID)
            .animation(rowSelectionAnimation, value: interactionState.revealsAuxiliaryAction)
            .animation(rowSelectionAnimation, value: actionState)
            .onHover { isHovered in
                updateHoveredRowAction(rowID, isHovered: isHovered)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            rowPanel(rowID: rowID, interactionState: interactionState)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .id(rowID)
        .onHover { isHovered in
            updateHoveredRow(rowID, isHovered: isHovered)
        }
        .animation(rowSelectionAnimation, value: interactionState)
        .onDisappear {
            clearHoveredRow(rowID)
            clearRowAction(rowID)
        }
    }

    private func toolRow(item: ToolItem, index: Int) -> some View {
        let rowID = ResultRowID.tool(item)
        let interactionState = LauncherRowInteractionState(
            isSelected: index == model.selectedIndex,
            isHovered: hoveredRowID == rowID
        )
        let actionState = LauncherRowActionInteractionState(
            isHovered: hoveredRowActionID == rowID,
            isActive: activatingRowActionID == rowID,
            isEnabled: toolActionConfiguration(for: item) != nil
        )

        return HStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: toolSymbol(for: item.kind))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(toolColor(for: item.kind))
                    .frame(width: toolIconSize(for: item.kind), height: toolIconSize(for: item.kind))

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(toolTitleFont(for: item.kind))
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.system(size: item.kind == .calculation ? 13 : 12))
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

            if let actionConfiguration = toolActionConfiguration(for: item) {
                Button {
                    activateToolAction(item, rowID: rowID)
                } label: {
                    rowActionIcon(
                        symbol: actionConfiguration.symbol,
                        filledSymbol: actionConfiguration.filledSymbol,
                        state: actionState
                    )
                }
                .buttonStyle(.glass(.regular.tint(.accentColor.opacity(actionState.tintOpacity))))
                .foregroundStyle(.secondary)
                .help(actionConfiguration.help)
                .glassEffectTransition(.materialize)
                .launcherRowActionDepth(actionState)
                .allowsHitTesting(activatingRowActionID != rowID)
                .animation(rowSelectionAnimation, value: actionState)
                .onHover { isHovered in
                    updateHoveredRowAction(rowID, isHovered: isHovered)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, toolRowVerticalPadding(for: item.kind))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            rowPanel(rowID: rowID, interactionState: interactionState)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .id(rowID)
        .onHover { isHovered in
            updateHoveredRow(rowID, isHovered: isHovered)
        }
        .animation(rowSelectionAnimation, value: interactionState)
        .onDisappear {
            clearHoveredRow(rowID)
            clearRowAction(rowID)
        }
    }

    private func rowActionIcon(
        symbol: String,
        filledSymbol: String,
        state: LauncherRowActionInteractionState
    ) -> some View {
        ZStack {
            Image(systemName: symbol)
                .frame(width: 16, height: 16)

            Image(systemName: filledSymbol)
                .frame(width: 16, height: 16)
                .opacity(state.fillSymbolOpacity)
        }
        .padding(5)
        .opacity(state.symbolOpacity)
    }

    @ViewBuilder
    private func rowPanel(rowID: ResultRowID, interactionState: LauncherRowInteractionState) -> some View {
        GlassEffectContainer(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(
                        .regular.tint(Color(nsColor: .windowBackgroundColor).opacity(interactionState.baseTintOpacity)).interactive(false),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .glassEffectID(rowID.glassEffectID, in: rowGlassNamespace)
                    .glassEffectTransition(.matchedGeometry)

                if interactionState.usesHoverSurface {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(
                            .regular.tint(Color.primary.opacity(interactionState.hoverTintOpacity)).interactive(),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .glassEffectTransition(.materialize)
                }

                if interactionState.isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(
                            .regular.tint(.accentColor.opacity(interactionState.selectionTintOpacity)).interactive(),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .glassEffectID(RowGlassEffectID.selection, in: selectionGlassNamespace)
                        .glassEffectTransition(.matchedGeometry)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(rowBorderColor(interactionState), lineWidth: interactionState.isSelected ? 1.25 : 1)
            }
            .shadow(color: .black.opacity(interactionState.shadowOpacity), radius: interactionState.shadowRadius, x: 0, y: interactionState.shadowY)
            .animation(rowSelectionAnimation, value: interactionState)
        }
    }

    private func rowBorderColor(_ interactionState: LauncherRowInteractionState) -> Color {
        if interactionState.isSelected {
            return .accentColor.opacity(interactionState.borderOpacity)
        }
        return Color.white.opacity(interactionState.borderOpacity)
    }

    private func updateHoveredRow(_ rowID: ResultRowID, isHovered: Bool) {
        withAnimation(rowSelectionAnimation) {
            if isHovered {
                hoveredRowID = rowID
            } else {
                clearHoveredRow(rowID)
            }
        }
    }

    private func clearHoveredRow(_ rowID: ResultRowID) {
        guard hoveredRowID == rowID else { return }
        hoveredRowID = nil
    }

    private func updateHoveredRowAction(_ rowID: ResultRowID, isHovered: Bool) {
        withAnimation(rowSelectionAnimation) {
            if isHovered {
                hoveredRowActionID = rowID
            } else if hoveredRowActionID == rowID {
                hoveredRowActionID = nil
            }
        }
    }

    private func clearRowAction(_ rowID: ResultRowID) {
        if hoveredRowActionID == rowID {
            hoveredRowActionID = nil
        }
        if activatingRowActionID == rowID {
            activatingRowActionID = nil
        }
    }

    private func activateExclude(_ item: LaunchItem, rowID: ResultRowID) {
        guard activatingRowActionID != rowID else { return }

        withAnimation(rowSelectionAnimation) {
            activatingRowActionID = rowID
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            model.exclude(item)
            withAnimation(rowSelectionAnimation) {
                clearHoveredRow(rowID)
                clearRowAction(rowID)
            }
        }
    }

    private func activateToolAction(_ item: ToolItem, rowID: ResultRowID) {
        guard activatingRowActionID != rowID else { return }

        withAnimation(rowSelectionAnimation) {
            activatingRowActionID = rowID
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            model.activateToolAction(item)
            withAnimation(rowSelectionAnimation) {
                clearRowAction(rowID)
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

        let targetAnchor = scrollAnchor(for: request.anchor)
        if request.anchor == .top, scrollTargetID == rowID {
            scrollTargetID = nil
            scrollTargetAnchor = targetAnchor
            Task { @MainActor in
                await Task.yield()
                guard handledSelectionScrollRequestID == request.id else { return }
                withAnimation(selectionScrollAnimation) {
                    scrollTargetAnchor = targetAnchor
                    scrollTargetID = rowID
                }
            }
            return
        }

        withAnimation(selectionScrollAnimation) {
            scrollTargetAnchor = targetAnchor
            scrollTargetID = rowID
        }
    }

    private func scrollAnchor(for anchor: SelectionScrollAnchor) -> UnitPoint? {
        switch anchor {
        case .nearest:
            return nil
        case .top:
            return UnitPoint(x: 0.5, y: resultsLayoutMetrics.topSelectionAnchorY)
        case .bottom:
            return UnitPoint(x: 0.5, y: resultsLayoutMetrics.bottomSelectionAnchorY)
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
                    .regular.tint(Color(nsColor: .windowBackgroundColor).opacity(model.resultCount == 0 ? 0.025 : resultsLayoutMetrics.mainPanelTintOpacity)),
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
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

    private func toolIconSize(for kind: ToolItem.Kind) -> CGFloat {
        switch kind {
        case .calculation:
            return 36
        case .calculationHistory, .dictionary, .message:
            return 34
        }
    }

    private func toolTitleFont(for kind: ToolItem.Kind) -> Font {
        switch kind {
        case .calculation:
            return .system(size: 24, weight: .semibold, design: .rounded)
        case .calculationHistory, .dictionary, .message:
            return .system(size: 17, weight: .semibold)
        }
    }

    private func toolRowVerticalPadding(for kind: ToolItem.Kind) -> CGFloat {
        switch kind {
        case .calculation:
            return 9
        case .calculationHistory, .dictionary, .message:
            return 8
        }
    }

    private func toolActionConfiguration(for item: ToolItem) -> RowActionConfiguration? {
        switch item.kind {
        case .calculation, .calculationHistory:
            guard item.copyText != nil else { return nil }
            return RowActionConfiguration(
                symbol: "doc.on.doc",
                filledSymbol: "doc.on.doc.fill",
                help: "Copy result"
            )
        case .dictionary:
            return RowActionConfiguration(
                symbol: "book",
                filledSymbol: "book.fill",
                help: "Open in Dictionary"
            )
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
private struct RowActionConfiguration {
    let symbol: String
    let filledSymbol: String
    let help: String
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
private extension View {
    func launcherHeaderControlDepth(_ state: LauncherHeaderControlInteractionState) -> some View {
        self
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(state.borderOpacity), lineWidth: 1)
            }
            .shadow(color: .black.opacity(state.depthShadowOpacity), radius: state.depthShadowRadius, x: 0, y: state.depthShadowY)
    }

    func launcherRowActionDepth(_ state: LauncherRowActionInteractionState) -> some View {
        self
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(state.borderOpacity), lineWidth: 1)
            }
            .shadow(color: .black.opacity(state.depthShadowOpacity), radius: state.depthShadowRadius, x: 0, y: state.depthShadowY)
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
