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
        XCTAssertTrue(source.contains(".frame(width: isSidebarCollapsed ? 102 : 210)"))
        XCTAssertTrue(source.contains("SettingsSidebarRow("))
        XCTAssertTrue(source.contains("if !isCollapsed"))
        XCTAssertTrue(source.contains("Image(systemName: pane.systemImage)"))
        XCTAssertTrue(source.contains("SidebarBackCollapseControls("))
        XCTAssertTrue(source.contains("Image(systemName: isCollapsed ? \"sidebar.left\" : \"sidebar.leading\")"))
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
        XCTAssertTrue(launcherView.contains("SettingsView(model: settingsModel, onBack:"))
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
        XCTAssertFalse(settingsView.contains(".frame(width: LauncherWindowFramePolicy.visualContentSize.width"))
        XCTAssertFalse(settingsView.contains("height: LauncherWindowFramePolicy.visualContentSize.height"))
        XCTAssertTrue(settingsView.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"))
    }

    func testSettingsSurfaceUsesLauncherPaneInsetWithoutSwiftUIShadow() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertFalse(source.contains(".padding(10)\n        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"))
        XCTAssertFalse(source.contains(".frame(width: LauncherWindowFramePolicy.visualContentSize.width"))
        XCTAssertFalse(source.contains("func settingsPaneShadow()"))
        XCTAssertFalse(source.contains(".settingsPaneShadow()"))
        XCTAssertFalse(source.contains(".shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 8)"))
    }

    func testSettingsWindowHasNoTitlebar() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
        let panel = try source(named: "Sources/Bucky/UI/Shared/BuckyPanelWindow.swift")

        XCTAssertTrue(launcher.contains("BuckyPanelWindow("))
        XCTAssertTrue(launcher.contains("styleMask: [.borderless, .resizable]"))
        XCTAssertTrue(launcher.contains("window.isOpaque = false"))
        XCTAssertTrue(launcher.contains("window.backgroundColor = .clear"))
        XCTAssertTrue(launcher.contains("window.hasShadow = true"))
        XCTAssertTrue(launcher.contains("hostingView.layer?.backgroundColor = NSColor.clear.cgColor"))
        XCTAssertTrue(launcher.contains("hostingView.layer?.cornerRadius = LauncherVisualStyle.windowCornerRadius"))
        XCTAssertTrue(launcher.contains("hostingView.layer?.cornerCurve = .continuous"))
        XCTAssertTrue(launcher.contains("hostingView.layer?.masksToBounds = true"))
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
        XCTAssertTrue(launcher.contains("private func showLauncherFromPanel()"))
        XCTAssertTrue(launcher.contains("if model.isShowingSettings || model.isShowingHelp {\n            showLauncherFromPanel()"))
        XCTAssertTrue(launcher.contains("case .settings:\n                toggleSettings()"))
        XCTAssertFalse(launcher.contains("openSettingsAction: @escaping () -> Void"))
    }

    func testCommandSlashShowsHelpInsideLauncher() throws {
        let launcher = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherWindowController.swift")
        let launcherView = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")
        let model = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherModel.swift")
        let utilities = try source(named: "Sources/Bucky/UI/Shared/Utilities.swift")

        XCTAssertTrue(model.contains("@Published var isShowingHelp = false"))
        XCTAssertTrue(model.contains("func showHelp()"))
        XCTAssertTrue(model.contains("func hideHelp()"))
        XCTAssertTrue(utilities.contains("var isCommandSlash: Bool"))
        XCTAssertTrue(launcher.contains("private func showHelp()"))
        XCTAssertTrue(launcher.contains("private func toggleHelp()"))
        XCTAssertTrue(launcher.contains("if event.isCommandSlash"))
        XCTAssertTrue(launcher.contains("return self.handleLauncherCommand(.help) ? nil : event"))
        XCTAssertTrue(launcherView.contains("HelpView(globalHotKeyTitle: settingsModel.hotKeyTitle, onBack:"))
        XCTAssertTrue(launcherView.contains("if model.isShowingSettings"))
        XCTAssertTrue(launcherView.contains("else if model.isShowingHelp"))
        XCTAssertTrue(launcherView.contains(".animation(settingsModeAnimation, value: model.isShowingHelp)"))
    }

    func testHelpPaneListsGlobalAndModeHotkeys() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertTrue(source.contains("struct HelpView: View"))
        XCTAssertTrue(source.contains("case global"))
        XCTAssertTrue(source.contains("case mode(LauncherMode)"))
        XCTAssertTrue(source.contains("HelpShortcutCatalog.content(for: selectedPane, globalHotKeyTitle: globalHotKeyTitle)"))
        XCTAssertTrue(source.contains("Section(\"Hotkeys\")"))
        XCTAssertTrue(source.contains("Section(\"Others\")"))
        XCTAssertTrue(source.contains("Command+/"))
        XCTAssertTrue(source.contains("Command+Left"))
        XCTAssertTrue(source.contains("Command+Right"))
        XCTAssertTrue(source.contains("Command+\\(mode.rawValue)"))
        XCTAssertTrue(source.contains("mode.shortTitle"))
        XCTAssertFalse(source.contains("case .agenda"))
        XCTAssertFalse(source.contains("Agenda"))
    }

    func testFilesHelpDistinguishesSelectionFromHoldToPreview() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertTrue(source.contains("HelpShortcut(title: \"Select item\", keys: \"Space\""))
        XCTAssertTrue(source.contains("HelpShortcut(title: \"Range select\", keys: \"Shift+Space\""))
        XCTAssertTrue(source.contains("HelpShortcut(title: \"Preview selected file\", keys: \"Hold Space\""))
        XCTAssertFalse(source.contains("HelpShortcut(title: \"Preview\", keys: \"Space\""))
    }

    func testSettingsAndHelpSidebarsUseBackCollapseControls() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertTrue(source.contains("let onBack: () -> Void"))
        XCTAssertTrue(source.contains("SidebarBackCollapseControls("))
        XCTAssertTrue(source.contains("Back to Bucky"))
        XCTAssertTrue(source.contains("Image(systemName: \"chevron.left\")"))
        XCTAssertTrue(source.contains(".frame(width: isSidebarCollapsed ? 102 : 210)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, minHeight: 34, alignment: isCollapsed ? .center : .leading)"))
        XCTAssertTrue(source.contains("HStack(spacing: 8)"))
        XCTAssertTrue(source.contains("isCollapsed ? 19 : 15"))
    }

    func testBackToBuckyControlHasDedicatedHoverAndPressTreatment() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertTrue(source.contains("private struct SidebarBackButtonStyle: ButtonStyle"))
        XCTAssertTrue(source.contains("configuration.isPressed"))
        XCTAssertTrue(source.contains("@State private var isBackHovered = false"))
        XCTAssertTrue(source.contains(".onHover { isBackHovered = $0 }"))
        XCTAssertTrue(source.contains(".buttonStyle(SidebarBackButtonStyle(isHovered: isBackHovered))"))
        XCTAssertTrue(source.contains(".scaleEffect(configuration.isPressed ? 0.96 : isHovered ? 1.015 : 1)"))
        XCTAssertTrue(source.contains(".animation(.snappy(duration: 0.12), value: configuration.isPressed)"))
        XCTAssertTrue(source.contains(".strokeBorder(Color.accentColor.opacity(isHovered ? 0.55 : 0.32), lineWidth: 1.15)"))
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
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)\n            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))"))
        XCTAssertFalse(source.contains(".frame(height: 164)"))
    }

    func testAppsPaneListBoxesAreBoundedToVisiblePaneHeight() throws {
        let source = try source(named: "Sources/Bucky/UI/SwiftUI/SettingsView.swift")

        XCTAssertTrue(source.contains("if selectedPane == .apps"))
        XCTAssertTrue(source.contains("boundedSettingsPaneContent"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"))
        XCTAssertTrue(source.contains(".padding(.leading, isSidebarCollapsed ? 116 : 252)\n                    .padding(.trailing, 28)\n                    .padding(.vertical, 28)\n                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)"))
        XCTAssertTrue(source.contains(".frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)"))
        XCTAssertTrue(source.contains("scrollingSettingsPaneContent"))
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
        XCTAssertTrue(source.contains(".animation(settingsModeAnimation, value: model.isShowingHelp)"))
        XCTAssertFalse(source.contains(".animation(resultUpdateAnimation, value: model.isShowingSettings)"))
    }

    func testSettingsSurfaceFillsResizableLauncherWindowWithoutShadowPadding() throws {
        let launcherView = try source(named: "Sources/Bucky/UI/SwiftUI/LiquidGlassLauncherView.swift")
        let settingsSurface = launcherView.components(separatedBy: "private var settingsSurface: some View").last ?? ""

        XCTAssertTrue(settingsSurface.contains("SettingsView(model: settingsModel, onBack:"))
        XCTAssertTrue(settingsSurface.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"))
        XCTAssertFalse(settingsSurface.contains(".padding(LauncherWindowFramePolicy.shadowBleed)"))
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
