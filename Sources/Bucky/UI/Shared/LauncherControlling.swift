import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

protocol LauncherControlling: AnyObject {
    func toggle()
    func show()
    func reindex()
    func refreshAfterExclusionsChanged()
    func refreshAfterInclusionsChanged()
    func refreshAfterSettingsChanged()
}

extension LauncherWindowController: LauncherControlling {}
