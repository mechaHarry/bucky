import XCTest

final class SettingsViewLayoutTests: XCTestCase {
    func testSettingsUsesPersistentGlassSplitLayout() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertTrue(source.contains("GlassEffectContainer"))
        XCTAssertTrue(source.contains("ZStack(alignment: .leading)"))
        XCTAssertTrue(source.contains(".fill(Color.clear)"))
        XCTAssertTrue(source.contains(".glassEffect("))
        XCTAssertTrue(source.contains(".tint(Color.white.opacity(0.05))"))
        XCTAssertTrue(source.contains("SettingsGlassBackdrop()"))
        XCTAssertTrue(source.contains("ZStack {\n            settingsGlassBackdrop"))
        XCTAssertTrue(source.contains("settingsSidebar"))
        XCTAssertTrue(source.contains("detailPane"))
        XCTAssertTrue(source.contains(".padding(.leading, isSidebarCollapsed ? 116 : 252)"))
        XCTAssertFalse(source.contains("settingsTitleBar"))
        XCTAssertFalse(source.contains("HStack(spacing: 12) {\n                    settingsSidebar"))
        XCTAssertFalse(source.contains(".background(.regularMaterial)"))
        XCTAssertFalse(source.contains(".background(.thinMaterial"))
        XCTAssertFalse(source.contains("NavigationSplitView"))
        XCTAssertFalse(source.contains(".listStyle(.sidebar)"))
        XCTAssertFalse(source.contains("SettingsGlassPane"))
    }

    func testSettingsGlassDoesNotWrapForegroundContent() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertFalse(source.contains("var body: some View {\n        GlassEffectContainer {\n            ZStack(alignment: .leading)"))
        XCTAssertTrue(source.contains("private struct SettingsGlassBackdrop: View"))
        XCTAssertTrue(source.contains("var body: some View {\n        GlassEffectContainer {\n            glassShape"))
        XCTAssertTrue(source.contains(".allowsHitTesting(false)"))
    }

    func testSettingsSidebarShrinksButNeverDisappears() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertTrue(source.contains("@State private var isSidebarCollapsed = false"))
        XCTAssertTrue(source.contains(".frame(width: isSidebarCollapsed ? 74 : 210)"))
        XCTAssertTrue(source.contains("SettingsSidebarRow("))
        XCTAssertTrue(source.contains("if !isCollapsed"))
        XCTAssertTrue(source.contains("Image(systemName: pane.systemImage)"))
        XCTAssertTrue(source.contains("Image(systemName: isSidebarCollapsed ? \"sidebar.left\" : \"sidebar.leading\")"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, alignment: isSidebarCollapsed ? .center : .trailing)"))
        XCTAssertTrue(source.contains("Color(nsColor: .controlBackgroundColor).opacity(0.34)"))
        XCTAssertTrue(source.contains("Color(nsColor: .separatorColor).opacity(0.45)"))
        XCTAssertTrue(source.contains(".strokeBorder("))
    }

    func testSettingsTransparentRegionsRemainInteractive() throws {
        let settingsView = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")
        let launcherWindow = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
        let panel = try source(named: "Sources/Bucky/UI/Shared/BuckyPanelWindow.swift")

        XCTAssertTrue(settingsView.contains("SettingsInputSurface()"))
        XCTAssertTrue(settingsView.contains("private struct SettingsInputSurface: View"))
        XCTAssertTrue(settingsView.contains("Color.white.opacity(0.001)"))
        XCTAssertTrue(launcherWindow.contains("BuckyPanelHostingView(rootView: LiquidGlassLauncherView("))
        XCTAssertFalse(panel.contains("private final class"))
        XCTAssertTrue(panel.contains("final class BuckyPanelHostingView<Content: View>: NSHostingView<Content>"))
        XCTAssertTrue(panel.contains("override func hitTest(_ point: NSPoint) -> NSView?"))
        XCTAssertTrue(panel.contains("return bounds.contains(point) ? self : nil"))
        XCTAssertTrue(panel.contains("override func acceptsFirstMouse(for event: NSEvent?) -> Bool"))
        XCTAssertTrue(panel.contains("return true"))
        XCTAssertTrue(settingsView.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(settingsView.contains(".contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))"))
        XCTAssertTrue(settingsView.contains(".contentShape(Rectangle())\n            .frame(maxWidth: .infinity, maxHeight: .infinity)"))
    }

    func testSettingsIsHostedInsideLauncherWindowNotSeparatePanel() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
        let launcherView = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")
        let appDelegate = try source(named: "Sources/Bucky/App/AppDelegate.swift")
        let launcherProtocol = try source(named: "Sources/Bucky/UI/Shared/LauncherControlling.swift")

        XCTAssertTrue(launcherProtocol.contains("func showSettings()"))
        XCTAssertTrue(launcher.contains("private var settingsModel: SettingsViewModel!"))
        XCTAssertTrue(launcherView.contains("@ObservedObject var settingsModel: SettingsViewModel"))
        XCTAssertTrue(launcherView.contains("if model.isShowingSettings"))
        XCTAssertTrue(launcherView.contains("SettingsView(model: settingsModel)"))
        XCTAssertTrue(appDelegate.contains("settingsAction: { [weak launcherController] in launcherController?.showSettings() }"))
        XCTAssertTrue(appDelegate.contains("self?.launcherController?.toggle()"))
        XCTAssertFalse(appDelegate.contains("SettingsWindowController"))
        XCTAssertFalse(appDelegate.contains("settingsWindowController"))
    }

    func testSettingsSidebarOwnsDedicatedCategories() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertTrue(source.contains("case general"))
        XCTAssertTrue(source.contains("case files"))
        XCTAssertTrue(source.contains("case apps"))
        XCTAssertTrue(source.contains("case actions"))
        XCTAssertTrue(source.contains("ForEach(SettingsPane.allCases)"))
        XCTAssertTrue(source.contains("switch selectedPane"))
    }

    func testSettingsWindowMatchesSplitPaneSize() throws {
        let framePolicy = try source(named: "Sources/Bucky/UI/SwiftUI/LauncherWindowFramePolicy.swift")
        let settingsView = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertFalse(framePolicy.contains("settingsVisualContentSize"))
        XCTAssertFalse(framePolicy.contains("settingsSize"))
        XCTAssertFalse(framePolicy.contains("settingsWindowSize"))
        XCTAssertTrue(settingsView.contains(".frame(width: LauncherWindowFramePolicy.visualContentSize.width, height: LauncherWindowFramePolicy.visualContentSize.height"))
    }

    func testSettingsSurfaceUsesLauncherPaneInsetAndShadow() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertTrue(source.contains(".padding(10)\n        .frame(width: LauncherWindowFramePolicy.visualContentSize.width"))
        XCTAssertFalse(source.contains(".padding(12)\n        .frame(width: LauncherWindowFramePolicy.visualContentSize.width"))
        XCTAssertTrue(source.contains("private extension View {\n    func settingsPaneShadow() -> some View"))
        XCTAssertTrue(source.contains("shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 8)"))
        XCTAssertTrue(source.contains(".settingsPaneShadow()"))
    }

    func testSettingsWindowHasNoTitlebar() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
        let panel = try source(named: "Sources/Bucky/UI/Shared/BuckyPanelWindow.swift")

        XCTAssertTrue(launcher.contains("BuckyPanelWindow("))
        XCTAssertTrue(launcher.contains("styleMask: [.borderless, .resizable]"))
        XCTAssertTrue(launcher.contains("window.isOpaque = false"))
        XCTAssertTrue(launcher.contains("window.backgroundColor = .clear"))
        XCTAssertTrue(launcher.contains("hostingView.layer?.backgroundColor = NSColor.clear.cgColor"))
        XCTAssertTrue(launcher.contains("window.isMovableByWindowBackground = LauncherWindowDragPolicy.isMovableByWindowBackground"))
        XCTAssertTrue(panel.contains("override var canBecomeKey: Bool { true }"))
        XCTAssertTrue(panel.contains("override func performKeyEquivalent(with event: NSEvent) -> Bool"))
        XCTAssertTrue(launcher.contains("event.isCommandComma"))
        XCTAssertTrue(launcher.contains("window.keyEquivalentHandler = { [weak self] event in"))
        XCTAssertFalse(launcher.contains(".fullSizeContentView"))
        XCTAssertFalse(launcher.contains("window.titleVisibility"))
        XCTAssertFalse(launcher.contains("window.titlebarAppearsTransparent"))
    }

    func testSettingsAndLauncherSharePanelWindowArchitecture() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
        let panel = try source(named: "Sources/Bucky/UI/Shared/BuckyPanelWindow.swift")

        XCTAssertTrue(launcher.contains("window = BuckyPanelWindow("))
        XCTAssertTrue(launcher.contains("BuckyPanelHostingView(rootView: LiquidGlassLauncherView("))
        XCTAssertTrue(launcher.contains("settingsModel: settingsModel"))
        XCTAssertTrue(panel.contains("var keyEquivalentHandler: ((NSEvent) -> Bool)?"))
        XCTAssertTrue(panel.contains("var cancelHandler: (() -> Bool)?"))
        XCTAssertFalse(launcher.contains("private final class LiquidGlassWindow"))
    }

    func testCommandCommaTogglesSettingsInsideLauncher() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
        let model = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift")

        XCTAssertTrue(model.contains("@Published var isShowingSettings = false"))
        XCTAssertTrue(model.contains("func showSettings()"))
        XCTAssertTrue(model.contains("func hideSettings()"))
        XCTAssertTrue(launcher.contains("model.openSettingsAction = { [weak self] in self?.toggleSettings() }"))
        XCTAssertTrue(launcher.contains("private func toggleSettings()"))
        XCTAssertTrue(launcher.contains("private func showLauncherFromSettings()"))
        XCTAssertTrue(launcher.contains("if model.isShowingSettings {\n            showLauncherFromSettings()"))
        XCTAssertTrue(launcher.contains("case .settings:\n                toggleSettings()"))
        XCTAssertFalse(launcher.contains("openSettingsAction: @escaping () -> Void"))
    }

    func testAppsPaneUsesLauncherStyleRows() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertTrue(source.contains("SettingsAppPathRow"))
        XCTAssertTrue(source.contains("Image(nsImage: icon)"))
        XCTAssertTrue(source.contains("NSWorkspace.shared.icon(forFile: path)"))
        XCTAssertTrue(source.contains("FadeMarqueeText("))
        XCTAssertTrue(source.contains("typeTitle: \"Included\""))
        XCTAssertTrue(source.contains("typeTitle: \"Hidden\""))
        XCTAssertFalse(source.contains("Text(path)\n                            .lineLimit(1)\n                            .truncationMode(.middle)"))
    }

    func testAppsPanePlacesIncludedAndHiddenListsSideBySide() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertTrue(source.contains("private var appsPane: some View {\n        HStack(alignment: .top, spacing: 14)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, alignment: .topLeading)"))
        XCTAssertFalse(source.contains("private var appsPane: some View {\n        VStack(alignment: .leading, spacing: 18)"))
    }

    func testAppsPaneListBoxesExpandWithinSettingsContent() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertTrue(source.contains("settingsPaneContent"))
        XCTAssertTrue(source.contains(".id(selectedPane)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)\n            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))"))
        XCTAssertFalse(source.contains(".frame(height: 164)"))
    }

    func testSettingsPaneChangesUseSoftMaterializeTransition() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertTrue(source.contains("private var settingsPaneSwitchAnimation: Animation"))
        XCTAssertTrue(source.contains("private var settingsPaneTransition: AnyTransition"))
        XCTAssertTrue(source.contains(".opacity.combined(with: .scale(scale: 0.985))"))
        XCTAssertTrue(source.contains(".transition(settingsPaneTransition)"))
        XCTAssertTrue(source.contains(".animation(settingsPaneSwitchAnimation, value: selectedPane)"))
    }

    func testSettingsModeUsesDedicatedSoftTransition() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")

        XCTAssertTrue(source.contains("private var settingsModeAnimation: Animation"))
        XCTAssertTrue(source.contains("private var settingsModeTransition: AnyTransition"))
        XCTAssertTrue(source.contains(".transition(settingsModeTransition)"))
        XCTAssertTrue(source.contains(".animation(settingsModeAnimation, value: model.isShowingSettings)"))
        XCTAssertFalse(source.contains(".animation(resultUpdateAnimation, value: model.isShowingSettings)"))
    }

    func testSettingsAppRowsConstrainTextWithinRowWidth() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")
        let rowSource = source.components(separatedBy: "private struct SettingsAppPathRow: View").last ?? ""

        XCTAssertTrue(source.contains(".frame(width: 30, height: 30)\n                .layoutPriority(2)"))
        XCTAssertTrue(source.contains(".frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)\n            .layoutPriority(1)\n            .clipped()"))
        XCTAssertTrue(source.contains(".frame(width: 42, alignment: .trailing)\n                .layoutPriority(0)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, alignment: .leading)\n        .clipped()"))
        XCTAssertTrue(source.contains(".padding(8)\n                .frame(maxWidth: .infinity, alignment: .topLeading)"))
        XCTAssertFalse(rowSource.contains(".truncationMode(.middle)"))
    }

    private func source(named path: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
