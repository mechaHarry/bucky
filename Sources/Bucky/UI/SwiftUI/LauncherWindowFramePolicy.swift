import CoreGraphics

struct LauncherWindowFramePolicy {
    static let defaultSize = CGSize(width: 760, height: 460)
    static let minimumSize = CGSize(width: 520, height: 340)
    static let defaultVisibleInset: CGFloat = 120

    static func frame(
        mode: LauncherMode,
        fileFocusState: FileBrowserFocusState?,
        visibleFrame: CGRect
    ) -> CGRect {
        let size = windowSize(mode: mode, fileFocusState: fileFocusState, visibleFrame: visibleFrame)
        return CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func windowSize(
        mode: LauncherMode,
        fileFocusState: FileBrowserFocusState?,
        visibleFrame: CGRect
    ) -> CGSize {
        defaultWindowSize(visibleFrame: visibleFrame)
    }

    private static func defaultWindowSize(visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: min(defaultSize.width, max(minimumSize.width, visibleFrame.width - defaultVisibleInset)),
            height: min(defaultSize.height, max(minimumSize.height, visibleFrame.height - defaultVisibleInset))
        )
    }
}

struct LauncherWindowDragPolicy {
    static let isMovableByWindowBackground = false
}

struct FileBrowserPreviewWindowFramePolicy {
    static func frame(for mode: FileBrowserPreviewMode, visibleFrame: CGRect) -> CGRect {
        let size = FileBrowserPreviewLayoutPolicy.surfaceSize(
            for: mode,
            availableSize: visibleFrame.size
        )
        return CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY,
            width: size.width,
            height: visibleFrame.height
        )
    }
}

struct LauncherWindowRepositionPolicy {
    static func shouldReposition(after command: LauncherCommand) -> Bool {
        if case .switchMode = command {
            return true
        }

        return false
    }
}

struct LauncherWindowFocusRestorationPolicy {
    static func shouldRestoreAfterAppActivation(
        mode: LauncherMode,
        isPinned: Bool,
        isPresented: Bool,
        isVisible: Bool,
        isKeyWindow: Bool
    ) -> Bool {
        isPresented && isVisible && !isKeyWindow && (mode == .files || isPinned)
    }
}
