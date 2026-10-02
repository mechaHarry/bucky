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
    func flushPersistence(completion: @escaping () -> Void)
}

extension LauncherControlling {
    func flushPersistence(completion: @escaping () -> Void) { completion() }
}
