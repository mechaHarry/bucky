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
    @State private var selectedPane: SettingsPane = .general
    @State private var isSidebarCollapsed = false

    var body: some View {
        ZStack(alignment: .leading) {
            SettingsInputSurface()

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            settingsSidebar
                .frame(width: isSidebarCollapsed ? 74 : 210)
                .padding(.leading, 12)
                .padding(.vertical, 12)
        }
        .padding(12)
        .frame(width: LauncherWindowFramePolicy.visualContentSize.width, height: LauncherWindowFramePolicy.visualContentSize.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.18), value: isSidebarCollapsed)
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

                Button {
                    isSidebarCollapsed.toggle()
                } label: {
                    Image(systemName: isSidebarCollapsed ? "sidebar.left" : "sidebar.leading")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: isSidebarCollapsed ? .center : .trailing)
                .help(isSidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
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

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    paneHeader

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
                .padding(.leading, isSidebarCollapsed ? 116 : 252)
                .padding(.trailing, 28)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
        VStack(alignment: .leading, spacing: 18) {
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
            }
            .contentShape(Rectangle())
            .frame(height: 164)
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
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 18, height: 18)

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
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 30, height: 30)

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
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(typeTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
