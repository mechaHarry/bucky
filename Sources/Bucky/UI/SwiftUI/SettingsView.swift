import AppKit
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var hotKeyTitle = ""
    @Published var launchAtStartup = false
    @Published var animationTiming: LauncherAnimationTiming = .defaultValue
    @Published var fileBrowserStartDirectoryText = ""
    @Published var inclusionPaths: [String] = []
    @Published var exclusionPaths: [String] = []
    @Published var customActions: [CustomAction] = []
    @Published var selectedCustomActionID: UUID?
    @Published var customActionName = ""
    @Published var customActionCommand = ""
    @Published var selectedInclusionPath: String?
    @Published var selectedExclusionPath: String?
    @Published var isRecordingHotKey = false
    @Published var errorMessage: String?

    var startHotKeyRecordingAction: (() -> Void)?
    var presentIncludedAppPickerAction: (() -> Void)?
    var presentFileBrowserStartDirectoryPickerAction: (() -> Void)?

    private let settingsStore: SettingsStore
    private let inclusionStore: InclusionStore
    private let exclusionStore: ExclusionStore
    private let hotKeyChangeHandler: @MainActor (HotKeyConfiguration) -> Bool
    private let inclusionsChangedHandler: @MainActor () -> Void
    private let exclusionsChangedHandler: @MainActor () -> Void
    private let settingsChangedHandler: @MainActor () -> Void

    init(
        settingsStore: SettingsStore,
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        hotKeyChangeHandler: @escaping @MainActor (HotKeyConfiguration) -> Bool,
        inclusionsChangedHandler: @escaping @MainActor () -> Void,
        exclusionsChangedHandler: @escaping @MainActor () -> Void,
        settingsChangedHandler: @escaping @MainActor () -> Void
    ) {
        self.settingsStore = settingsStore
        self.inclusionStore = inclusionStore
        self.exclusionStore = exclusionStore
        self.hotKeyChangeHandler = hotKeyChangeHandler
        self.inclusionsChangedHandler = inclusionsChangedHandler
        self.exclusionsChangedHandler = exclusionsChangedHandler
        self.settingsChangedHandler = settingsChangedHandler
    }

    var hotKeyButtonTitle: String {
        isRecordingHotKey ? "Press shortcut" : hotKeyTitle
    }

    func refresh() {
        settingsStore.load()
        inclusionStore.load()
        exclusionStore.load()
        hotKeyTitle = settingsStore.settings.hotKey.displayName
        launchAtStartup = settingsStore.settings.launchAtStartup
        animationTiming = settingsStore.settings.animationTiming
        fileBrowserStartDirectoryText = settingsStore.settings.fileBrowserStartDirectory?.path ?? "~/"
        customActions = settingsStore.settings.customActions
        inclusionPaths = inclusionStore.sortedPaths()
        exclusionPaths = exclusionStore.sortedPaths()
        selectedCustomActionID = customActions.contains(where: { $0.id == selectedCustomActionID }) ? selectedCustomActionID : nil
        selectedInclusionPath = inclusionPaths.contains(selectedInclusionPath ?? "") ? selectedInclusionPath : nil
        selectedExclusionPath = exclusionPaths.contains(selectedExclusionPath ?? "") ? selectedExclusionPath : nil
    }

    func beginHotKeyRecording() {
        isRecordingHotKey = true
        startHotKeyRecordingAction?()
    }

    func cancelHotKeyRecording() {
        isRecordingHotKey = false
    }

    func commitHotKey(_ hotKey: HotKeyConfiguration) {
        if hotKeyChangeHandler(hotKey) {
            settingsStore.updateHotKey(hotKey)
            hotKeyTitle = hotKey.displayName
        } else {
            hotKeyTitle = settingsStore.settings.hotKey.displayName
        }

        isRecordingHotKey = false
    }

    func setLaunchAtStartup(_ enabled: Bool) {
        do {
            try LaunchAtStartupController.setEnabled(enabled)
            settingsStore.updateLaunchAtStartup(enabled)
            launchAtStartup = enabled
        } catch {
            launchAtStartup = settingsStore.settings.launchAtStartup
            errorMessage = "Could not update launch at startup: \(error.localizedDescription)"
        }
    }

    func setAnimationTiming(_ timing: LauncherAnimationTiming) {
        settingsStore.updateAnimationTiming(timing)
        animationTiming = timing
        settingsChangedHandler()
    }

    func requestFileBrowserStartDirectoryPicker() {
        presentFileBrowserStartDirectoryPickerAction?()
    }

    func setFileBrowserStartDirectory(_ directory: URL?) {
        settingsStore.updateFileBrowserStartDirectory(directory)
        fileBrowserStartDirectoryText = directory?.path ?? "~/"
        settingsChangedHandler()
    }

    func selectCustomAction(_ id: UUID?) {
        selectedCustomActionID = id
        guard let id,
              let action = customActions.first(where: { $0.id == id }) else {
            customActionName = ""
            customActionCommand = ""
            return
        }

        customActionName = action.name
        customActionCommand = action.command
    }

    func saveCustomAction() {
        let name = customActionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = customActionCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !command.isEmpty else {
            errorMessage = "Custom actions need both a name and a command."
            return
        }

        if let selectedCustomActionID,
           let index = customActions.firstIndex(where: { $0.id == selectedCustomActionID }) {
            customActions[index].name = name
            customActions[index].command = command
        } else {
            customActions.append(CustomAction(name: name, command: command))
        }

        settingsStore.updateCustomActions(customActions)
        selectedCustomActionID = nil
        customActionName = ""
        customActionCommand = ""
        settingsChangedHandler()
    }

    func removeSelectedCustomAction() {
        guard let selectedCustomActionID else { return }
        customActions.removeAll { $0.id == selectedCustomActionID }
        settingsStore.updateCustomActions(customActions)
        self.selectedCustomActionID = nil
        customActionName = ""
        customActionCommand = ""
        settingsChangedHandler()
    }

    func requestIncludedAppPicker() {
        presentIncludedAppPickerAction?()
    }

    func addIncludedApps(_ urls: [URL]) {
        for url in urls {
            inclusionStore.add(path: url.path)
        }

        inclusionPaths = inclusionStore.sortedPaths()
        inclusionsChangedHandler()
    }

    func removeSelectedInclusion() {
        guard let selectedInclusionPath else { return }
        inclusionStore.remove(path: selectedInclusionPath)
        self.selectedInclusionPath = nil
        inclusionPaths = inclusionStore.sortedPaths()
        inclusionsChangedHandler()
    }

    func removeSelectedExclusion() {
        guard let selectedExclusionPath else { return }
        exclusionStore.remove(path: selectedExclusionPath)
        self.selectedExclusionPath = nil
        exclusionPaths = exclusionStore.sortedPaths()
        exclusionsChangedHandler()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    let onBack: () -> Void
    @State private var selectedPane: SettingsPane = .general
    @State private var isSidebarCollapsed = false

    private var settingsPaneSwitchAnimation: Animation {
        .smooth(duration: 0.16)
    }

    private var settingsPaneTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.985))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            SettingsInputSurface()

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            settingsSidebar
                .frame(width: isSidebarCollapsed ? 102 : 210)
                .padding(.leading, 10)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.18), value: isSidebarCollapsed)
        .animation(settingsPaneSwitchAnimation, value: selectedPane)
        .alert(
            "Bucky Settings",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var settingsSidebar: some View {
        ZStack {
            settingsGlassBackdrop

            VStack(spacing: 10) {
                VStack(spacing: 6) {
                    ForEach(SettingsPane.allCases) { pane in
                        SettingsSidebarRow(
                            pane: pane,
                            isSelected: selectedPane == pane,
                            isCollapsed: isSidebarCollapsed
                        ) {
                            selectedPane = pane
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Spacer(minLength: 0)

                SidebarBackCollapseControls(
                    isCollapsed: isSidebarCollapsed,
                    backTitle: "Back to Bucky",
                    onBack: onBack,
                    onToggleCollapse: {
                        isSidebarCollapsed.toggle()
                    }
                )
            }
            .padding(.horizontal, isSidebarCollapsed ? 10 : 12)
            .padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var detailPane: some View {
        ZStack {
            settingsGlassBackdrop

            GeometryReader { proxy in
                if selectedPane == .apps {
                    VStack(alignment: .leading, spacing: 18) {
                        paneHeader

                        boundedSettingsPaneContent
                            .id(selectedPane)
                            .transition(settingsPaneTransition)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .padding(.leading, isSidebarCollapsed ? 116 : 252)
                    .padding(.trailing, 28)
                    .padding(.vertical, 28)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            paneHeader

                            scrollingSettingsPaneContent
                                .id(selectedPane)
                                .transition(settingsPaneTransition)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .padding(.leading, isSidebarCollapsed ? 116 : 252)
                        .padding(.trailing, 28)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var settingsPaneContent: some View {
        switch selectedPane {
        case .general:
            generalPane
        case .files:
            filesPane
        case .apps:
            appsPane
        case .actions:
            actionsPane
        }
    }

    private var boundedSettingsPaneContent: some View {
        settingsPaneContent
    }

    private var scrollingSettingsPaneContent: some View {
        settingsPaneContent
    }

    private var settingsGlassBackdrop: some View {
        SettingsGlassBackdrop()
    }
}

private struct SettingsGlassBackdrop: View {
    var body: some View {
        GlassEffectContainer {
            glassShape
                .fill(Color.clear)
                .glassEffect(
                    .regular
                        .tint(Color.white.opacity(0.05))
                        .interactive(false),
                    in: glassShape
                )
        }
        .allowsHitTesting(false)
    }

    private var glassShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }
}

private struct SettingsInputSurface: View {
    var body: some View {
        Color.white.opacity(0.001)
            .contentShape(Rectangle())
    }
}

@available(macOS 26.0, *)
struct HelpView: View {
    let globalHotKeyTitle: String
    let onBack: () -> Void
    @State private var selectedPane: HelpPane = .global
    @State private var isSidebarCollapsed = false

    private var helpPaneSwitchAnimation: Animation {
        .smooth(duration: 0.16)
    }

    private var helpPaneTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.985))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            SettingsInputSurface()

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            helpSidebar
                .frame(width: isSidebarCollapsed ? 102 : 210)
                .padding(.leading, 10)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.18), value: isSidebarCollapsed)
        .animation(helpPaneSwitchAnimation, value: selectedPane)
    }

    private var helpSidebar: some View {
        ZStack {
            SettingsGlassBackdrop()

            VStack(spacing: 10) {
                VStack(spacing: 6) {
                    ForEach(HelpPane.allCases) { pane in
                        HelpSidebarRow(
                            pane: pane,
                            isSelected: selectedPane == pane,
                            isCollapsed: isSidebarCollapsed
                        ) {
                            selectedPane = pane
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Spacer(minLength: 0)

                SidebarBackCollapseControls(
                    isCollapsed: isSidebarCollapsed,
                    backTitle: "Back to Bucky",
                    onBack: onBack,
                    onToggleCollapse: {
                        isSidebarCollapsed.toggle()
                    }
                )
            }
            .padding(.horizontal, isSidebarCollapsed ? 10 : 12)
            .padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var detailPane: some View {
        ZStack {
            SettingsGlassBackdrop()

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        paneHeader

                        shortcutsList
                            .id(selectedPane)
                            .transition(helpPaneTransition)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding(.leading, isSidebarCollapsed ? 144 : 252)
                    .padding(.trailing, 28)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(selectedPane.title, systemImage: selectedPane.systemImage)
                .font(.system(size: 22, weight: .semibold))

            Text(selectedPane.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var shortcutsList: some View {
        let content = HelpShortcutCatalog.content(for: selectedPane, globalHotKeyTitle: globalHotKeyTitle)

        VStack(alignment: .leading, spacing: 10) {
            if !content.shortcuts.isEmpty {
                Section("Hotkeys") {
                    ForEach(content.shortcuts) { shortcut in
                        HelpShortcutRow(shortcut: shortcut)
                    }
                }
            }

            if !content.explanations.isEmpty {
                Section("Others") {
                    ForEach(content.explanations) { explanation in
                        HelpExplanationRow(explanation: explanation)
                    }
                }
            }
        }
    }
}

@available(macOS 26.0, *)
private struct SidebarBackCollapseControls: View {
    let isCollapsed: Bool
    let backTitle: String
    let onBack: () -> Void
    let onToggleCollapse: () -> Void
    @State private var isBackHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .frame(width: 16, height: 16)

                    if !isCollapsed {
                        Text(backTitle)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: isCollapsed ? 15 : 14, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 34, alignment: isCollapsed ? .center : .leading)
                .padding(.horizontal, isCollapsed ? 0 : 10)
            }
            .buttonStyle(SidebarBackButtonStyle(isHovered: isBackHovered))
            .onHover { isBackHovered = $0 }
            .help(backTitle)

            Button(action: onToggleCollapse) {
                Image(systemName: isCollapsed ? "sidebar.left" : "sidebar.leading")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
        }
    }
}

@available(macOS 26.0, *)
private struct SidebarBackButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Color.accentColor : Color.secondary)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.18 : isHovered ? 0.12 : 0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isHovered ? 0.55 : 0.32), lineWidth: 1.15)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : isHovered ? 1.015 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
            .animation(.snappy(duration: 0.14), value: isHovered)
    }
}

private extension SettingsView {
    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(selectedPane.title, systemImage: selectedPane.systemImage)
                .font(.system(size: 22, weight: .semibold))

            Text(selectedPane.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            hotKeyRow

            Toggle(
                "Launch on startup",
                isOn: Binding(
                    get: { model.launchAtStartup },
                    set: { model.setLaunchAtStartup($0) }
                )
            )

            animationTimingRow
        }
    }

    private var filesPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            fileBrowserStartDirectoryRow
        }
    }

    private var appsPane: some View {
        HStack(alignment: .top, spacing: 14) {
            appPathSection(
                title: "Included apps",
                paths: model.inclusionPaths,
                selection: $model.selectedInclusionPath,
                emptyText: "No extra included apps",
                typeTitle: "Included",
                primaryActionTitle: "Add",
                primaryActionSystemImage: "plus",
                primaryAction: model.requestIncludedAppPicker,
                removeAction: model.removeSelectedInclusion,
                removeDisabled: model.selectedInclusionPath == nil
            )

            appPathSection(
                title: "Hidden apps",
                paths: model.exclusionPaths,
                selection: $model.selectedExclusionPath,
                emptyText: "No hidden apps",
                typeTitle: "Hidden",
                primaryActionTitle: nil,
                primaryActionSystemImage: nil,
                primaryAction: nil,
                removeAction: model.removeSelectedExclusion,
                removeDisabled: model.selectedExclusionPath == nil
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func appPathSection(
        title: String,
        paths: [String],
        selection: Binding<String?>,
        emptyText: String,
        typeTitle: String,
        primaryActionTitle: String?,
        primaryActionSystemImage: String?,
        primaryAction: (() -> Void)?,
        removeAction: @escaping () -> Void,
        removeDisabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            ScrollView {
                LazyVStack(spacing: 8) {
                    if paths.isEmpty {
                        Text(emptyText)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
                    } else {
                        ForEach(paths, id: \.self) { path in
                            SettingsAppPathRow(
                                path: path,
                                typeTitle: typeTitle,
                                isSelected: selection.wrappedValue == path
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onTapGesture {
                                selection.wrappedValue = path
                            }
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 8) {
                if let primaryActionTitle,
                   let primaryActionSystemImage,
                   let primaryAction {
                    Button {
                        primaryAction()
                    } label: {
                        Label(primaryActionTitle, systemImage: primaryActionSystemImage)
                    }
                }

                Button(role: .destructive) {
                    removeAction()
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(removeDisabled)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var actionsPane: some View {
        customActionsSection
    }

    private var animationTimingRow: some View {
        HStack(spacing: 12) {
            Text("Animation timing")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Picker(
                "",
                selection: Binding(
                    get: { model.animationTiming },
                    set: { model.setAnimationTiming($0) }
                )
            ) {
                ForEach(LauncherAnimationTiming.allCases) { timing in
                    Text(timing.displayName).tag(timing)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }

    private var hotKeyRow: some View {
        HStack(spacing: 12) {
            Text("Hotkey")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button(model.hotKeyButtonTitle) {
                model.beginHotKeyRecording()
            }
            .frame(minWidth: 160)
        }
    }

    private var fileBrowserStartDirectoryRow: some View {
        HStack(spacing: 12) {
            Text("Files start folder")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Text(model.fileBrowserStartDirectoryText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 230, alignment: .trailing)

            Button {
                model.setFileBrowserStartDirectory(nil)
            } label: {
                Label("Home", systemImage: "house")
            }

            Button {
                model.requestFileBrowserStartDirectoryPicker()
            } label: {
                Label("Choose", systemImage: "folder")
            }
        }
    }

    private var customActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom actions")
                .font(.system(size: 13, weight: .semibold))

            List(selection: $model.selectedCustomActionID) {
                if model.customActions.isEmpty {
                    Text("No custom actions")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.customActions) { action in
                        HStack(spacing: 8) {
                            Text(action.name)
                                .lineLimit(1)
                            Spacer()
                            Text(action.command)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .tag(Optional(action.id))
                    }
                }
            }
            .frame(height: 110)
            .onChange(of: model.selectedCustomActionID) { _, id in
                model.selectCustomAction(id)
            }

            HStack(spacing: 8) {
                TextField("Name", text: $model.customActionName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                TextField("Shell command or script path", text: $model.customActionCommand)
                    .textFieldStyle(.roundedBorder)

                Button {
                    model.saveCustomAction()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }

                Button(role: .destructive) {
                    model.removeSelectedCustomAction()
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(model.selectedCustomActionID == nil)
            }
        }
    }

}

@available(macOS 26.0, *)
private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: isCollapsed ? 19 : 15, weight: .semibold))
                    .frame(width: isCollapsed ? 28 : 18, height: isCollapsed ? 28 : 18)

                if !isCollapsed {
                    Text(pane.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: isCollapsed ? .center : .leading)
            .padding(.horizontal, isCollapsed ? 0 : 10)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.34))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.62) : Color(nsColor: .separatorColor).opacity(0.45),
                    lineWidth: isSelected ? 1.35 : 1.15
                )
        }
        .help(pane.title)
        .accessibilityLabel(pane.title)
    }
}

@available(macOS 26.0, *)
private struct SettingsAppPathRow: View {
    let path: String
    let typeTitle: String
    let isSelected: Bool

    private var displayName: String {
        let url = URL(fileURLWithPath: path)
        let bundle = Bundle(url: url)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        return displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent
    }

    private var icon: NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 30, height: 30)
                .layoutPriority(2)

            VStack(alignment: .leading, spacing: 3) {
                FadeMarqueeText(
                    text: displayName,
                    font: .system(size: 13, weight: .medium)
                )

                FadeMarqueeText(
                    text: path,
                    font: .system(size: 11)
                )
                .foregroundStyle(.secondary)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .clipped()

            Text(typeTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 42, alignment: .trailing)
                .layoutPriority(0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor).opacity(0.42))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.42) : Color(nsColor: .separatorColor).opacity(0.20), lineWidth: 1)
        }
        .accessibilityLabel("\(displayName), \(path), \(typeTitle)")
    }
}

@available(macOS 26.0, *)
private struct HelpSidebarRow: View {
    let pane: HelpPane
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: isCollapsed ? 19 : 15, weight: .semibold))
                    .frame(width: isCollapsed ? 28 : 18, height: isCollapsed ? 28 : 18)

                if !isCollapsed {
                    Text(pane.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: isCollapsed ? .center : .leading)
            .padding(.horizontal, isCollapsed ? 0 : 10)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.34))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.62) : Color(nsColor: .separatorColor).opacity(0.45),
                    lineWidth: isSelected ? 1.35 : 1.15
                )
        }
        .help(pane.title)
        .accessibilityLabel(pane.title)
    }
}

@available(macOS 26.0, *)
private struct HelpShortcutRow: View {
    let shortcut: HelpShortcut

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(shortcut.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(shortcut.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            Text(shortcut.keys)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.34))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 1)
        }
    }
}

@available(macOS 26.0, *)
private struct HelpExplanationRow: View {
    let explanation: HelpExplanation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(explanation.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)

            Text(explanation.detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.24))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
        }
    }
}

private struct HelpShortcut: Identifiable, Equatable {
    let title: String
    let keys: String
    let detail: String

    var id: String {
        "\(title)-\(keys)"
    }
}

private struct HelpExplanation: Identifiable, Equatable {
    let title: String
    let detail: String

    var id: String {
        title
    }
}

private struct HelpPageContent: Equatable {
    let shortcuts: [HelpShortcut]
    let explanations: [HelpExplanation]
}

private enum HelpShortcutCatalog {
    static func content(for pane: HelpPane, globalHotKeyTitle: String) -> HelpPageContent {
        switch pane {
        case .global:
            return HelpPageContent(
                shortcuts: [
                    HelpShortcut(title: "Open Bucky", keys: globalHotKeyTitle.isEmpty ? "Option+Space" : globalHotKeyTitle, detail: "Show or hide the launcher with the configured global shortcut."),
                    HelpShortcut(title: "Open Settings", keys: "Command+,", detail: "Open Bucky settings inside the glass panel."),
                    HelpShortcut(title: "Open Help", keys: "Command+/", detail: "Open this hotkey reference."),
                    HelpShortcut(title: "Previous mode", keys: "Command+Left", detail: "Cycle to the previous launcher mode with wraparound."),
                    HelpShortcut(title: "Next mode", keys: "Command+Right", detail: "Cycle to the next launcher mode with wraparound.")
                ],
                explanations: [
                    HelpExplanation(title: "Search text", detail: "Typing in launcher mode updates the active mode filter when that mode accepts text input.")
                ]
            )
        case let .mode(mode):
            return content(for: mode)
        }
    }

    private static func content(for mode: LauncherMode) -> HelpPageContent {
        let openMode = HelpShortcut(title: "Open \(mode.shortTitle)", keys: "Command+\(mode.rawValue)", detail: "Switch directly to \(mode.shortTitle).")
        switch mode {
        case .applications:
            return HelpPageContent(
                shortcuts: [
                    openMode,
                    HelpShortcut(title: "Reindex apps", keys: "Command+R", detail: "Refresh the application and custom action index."),
                    HelpShortcut(title: "Open definition", keys: "Return", detail: "Open the selected dictionary term in Dictionary."),
                    HelpShortcut(title: "Preview definition", keys: "Hold Space", detail: "Hold Space to preview the selected dictionary term."),
                    HelpShortcut(title: "Dictionary query", keys: "? word", detail: "Start a dictionary lookup from Apps."),
                    HelpShortcut(title: "Calculator query", keys: "= expression", detail: "Start a calculation from Apps.")
                ],
                explanations: [
                    HelpExplanation(title: "Calculate", detail: "Start the Apps search with = to show calculator results and calculation history."),
                    HelpExplanation(title: "Copy result", detail: "Press Return on the selected calculation result to copy it."),
                    HelpExplanation(title: "Clear history", detail: "Use the clear-history affordance to remove calculation history."),
                    HelpExplanation(title: "Hide result", detail: "Use the row hide affordance to remove a launch item from app search results."),
                    HelpExplanation(title: "History", detail: "Ordinary text filters indexed applications; a bare ? restores Dictionary history."),
                    HelpExplanation(title: "Remove dictionary history", detail: "Use the row remove affordance to delete a saved dictionary lookup.")
                ]
            )
        case .files:
            return HelpPageContent(
                shortcuts: [
                    openMode,
                    HelpShortcut(title: "Move selection", keys: "Arrow keys", detail: "Navigate file rows and directories."),
                    HelpShortcut(title: "Select item", keys: "Space", detail: "Select or deselect the focused file row."),
                    HelpShortcut(title: "Range select", keys: "Shift+Space", detail: "Extend selection across file rows."),
                    HelpShortcut(title: "Preview selected file", keys: "Hold Space", detail: "Hold Space to show the native preview, then release to dismiss it."),
                    HelpShortcut(title: "History", keys: "Command+[ / ]", detail: "Move backward or forward through visited directories.")
                ],
                explanations: [
                    HelpExplanation(title: "Directory entry", detail: "Use the right and left arrow navigation flow to enter and leave directories.")
                ]
            )
        }
    }
}

private enum HelpPane: Hashable, Identifiable {
    case global
    case mode(LauncherMode)

    static let allCases: [HelpPane] = [.global] + LauncherMode.ordered.map { .mode($0) }

    var id: String {
        switch self {
        case .global:
            return "global"
        case let .mode(mode):
            return "mode-\(mode.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .global:
            return "Global"
        case let .mode(mode):
            return mode.shortTitle
        }
    }

    var subtitle: String {
        switch self {
        case .global:
            return "Hotkeys that work across the open Bucky panel."
        case let .mode(mode):
            return "Hotkeys for \(mode.shortTitle)."
        }
    }

    var systemImage: String {
        switch self {
        case .global:
            return "globe"
        case let .mode(mode):
            return mode.helpSystemImage
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case files
    case apps
    case actions

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .files:
            return "Files"
        case .apps:
            return "Apps"
        case .actions:
            return "Actions"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Keyboard, startup, and animation preferences."
        case .files:
            return "Choose where file browsing starts."
        case .apps:
            return "Manage launcher app inclusions and hidden apps."
        case .actions:
            return "Expose named shell commands in app search."
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .files:
            return "folder"
        case .apps:
            return "square.grid.2x2"
        case .actions:
            return "terminal"
        }
    }
}
