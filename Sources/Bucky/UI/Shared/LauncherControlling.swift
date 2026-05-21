@MainActor
protocol LauncherControlling: AnyObject {
    func toggle()
    func show()
    func hide()
    func showSettings()
    func reindex()
    func refreshAfterExclusionsChanged()
    func refreshAfterInclusionsChanged()
    func refreshAfterSettingsChanged()
}
