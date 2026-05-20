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
    private let hotKeyChangeHandler: (HotKeyConfiguration) -> Bool
    private let inclusionsChangedHandler: () -> Void
    private let exclusionsChangedHandler: () -> Void
    private let settingsChangedHandler: () -> Void

    init(
        settingsStore: SettingsStore,
        inclusionStore: InclusionStore,
        exclusionStore: ExclusionStore,
        hotKeyChangeHandler: @escaping (HotKeyConfiguration) -> Bool,
        inclusionsChangedHandler: @escaping () -> Void,
        exclusionsChangedHandler: @escaping () -> Void,
        settingsChangedHandler: @escaping () -> Void
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

    var body: some View {
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

            fileBrowserStartDirectoryRow

            customActionsSection

            pathSection(
                title: "Included apps",
                paths: model.inclusionPaths,
                selection: $model.selectedInclusionPath,
                emptyText: "No extra included apps",
                primaryActionTitle: "Add",
                primaryActionSystemImage: "plus",
                primaryAction: model.requestIncludedAppPicker,
                removeAction: model.removeSelectedInclusion,
                removeDisabled: model.selectedInclusionPath == nil
            )

            pathSection(
                title: "Hidden apps",
                paths: model.exclusionPaths,
                selection: $model.selectedExclusionPath,
                emptyText: "No hidden apps",
                primaryActionTitle: nil,
                primaryActionSystemImage: nil,
                primaryAction: nil,
                removeAction: model.removeSelectedExclusion,
                removeDisabled: model.selectedExclusionPath == nil
            )
        }
        .padding(20)
        .frame(width: 620, height: 790, alignment: .topLeading)
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

    private func pathSection(
        title: String,
        paths: [String],
        selection: Binding<String?>,
        emptyText: String,
        primaryActionTitle: String?,
        primaryActionSystemImage: String?,
        primaryAction: (() -> Void)?,
        removeAction: @escaping () -> Void,
        removeDisabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            List(selection: selection) {
                if paths.isEmpty {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(paths, id: \.self) { path in
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .tag(Optional(path))
                    }
                }
            }
            .frame(height: 150)

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
}
