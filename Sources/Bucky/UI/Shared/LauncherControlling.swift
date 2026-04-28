protocol LauncherControlling: AnyObject {
    func toggle()
    func show()
    func reindex()
    func refreshAfterExclusionsChanged()
    func refreshAfterInclusionsChanged()
    func refreshAfterSettingsChanged()
}
