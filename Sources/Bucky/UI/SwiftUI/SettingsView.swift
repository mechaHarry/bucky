import ServiceManagement
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var hotKeyTitle = ""
    @Published var launchAtStartup = false
    @Published var animationTiming: LauncherAnimationTiming = .defaultValue
    @Published var inclusionPaths: [String] = []
    @Published var exclusionPaths: [String] = []
    @Published var selectedInclusionPath: String?
    @Published var selectedExclusionPath: String?
    @Published var isRecordingHotKey = false
    @Published var errorMessage: String?

    var startHotKeyRecordingAction: (() -> Void)?
    var presentIncludedAppPickerAction: (() -> Void)?

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
        inclusionPaths = inclusionStore.sortedPaths()
        exclusionPaths = exclusionStore.sortedPaths()
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
        .frame(width: 560, height: 650, alignment: .topLeading)
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
