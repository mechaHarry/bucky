import AppKit
import Foundation

@MainActor
final class CountdownStone: StoneProvider {
    static let refreshIntervalNanoseconds: UInt64 = 50_000_000

    private let store: CountdownStore
    private let now: () -> Date

    init(store: CountdownStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    var definition: StoneDefinition {
        StoneDefinition(
            id: .countdowns,
            shortcutNumber: 5,
            presentation: StonePresentation(
                title: "Countdowns",
                placeholder: "Manage Countdowns",
                systemImage: "timer"
            ),
            surface: .sharedResults,
            updatePolicy: .immediate,
            tint: StoneTint(
                activeHex: 0x34C759,
                panelHex: 0x1E7A3A,
                iconHex: 0x0B5D2A,
                darkModeIconHex: 0x8FF0A8
            ),
            refreshIntervalNanoseconds: Self.refreshIntervalNanoseconds,
            animatesResultUpdates: false
        )
    }

    func snapshot(for query: String) -> StoneResultSnapshot {
        .loaded(rows: Self.rows(for: store.countdowns, now: now()))
    }

    func updateSnapshot(for query: String) async -> StoneResultSnapshot {
        snapshot(for: query)
    }

    func cancel() {}

    func activation(for row: StoneResultRow) -> StoneActivation {
        row.primaryActivation
    }

    func perform(_ activation: StoneActivation, for row: StoneResultRow) -> StoneProviderActivationResult {
        guard case let .providerAction(action) = activation else { return .unhandled }

        if action == "add" {
            guard let draft = presentEditor() else { return .handled(shouldRefresh: false, resetSelection: false, shouldHide: false) }
            _ = store.add(name: draft.name, targetDate: draft.targetDate)
            return .handled(shouldRefresh: true, resetSelection: true, shouldHide: false)
        }

        if let id = id(from: action, prefix: "edit:") {
            guard let countdown = store.countdowns.first(where: { $0.id == id }),
                  let draft = presentEditor(for: countdown) else {
                return .handled(shouldRefresh: false, resetSelection: false, shouldHide: false)
            }
            _ = store.update(id: id, name: draft.name, targetDate: draft.targetDate)
            return .handled(shouldRefresh: true, resetSelection: false, shouldHide: false)
        }

        if let id = id(from: action, prefix: "delete:") {
            guard confirmDeletion() else {
                return .handled(shouldRefresh: false, resetSelection: false, shouldHide: false)
            }
            _ = store.remove(id: id)
            return .handled(shouldRefresh: true, resetSelection: true, shouldHide: false)
        }

        return .unhandled
    }

    static func rows(for countdowns: [Countdown], now: Date) -> [StoneResultRow] {
        let addRow = StoneResultRow(
            id: .tool(kind: .message, key: "countdown:add"),
            display: "Add countdown",
            subtitle: "Create a named target",
            copyText: nil,
            kind: .message,
            primaryActivation: .providerAction("add"),
            accessoryActivation: .providerAction("add"),
            iconSystemImage: "plus.circle",
            accessoryPresentation: .init(systemImage: "plus", help: "Add countdown")
        )

        let countdownRows = countdowns.map { countdown in
            StoneResultRow(
                id: .tool(kind: .message, key: "countdown:\(countdown.id.uuidString)"),
                display: countdown.name,
                subtitle: CountdownRemaining(until: countdown.targetDate, now: now).displayString,
                copyText: nil,
                kind: .message,
                primaryActivation: .providerAction("edit:\(countdown.id.uuidString)"),
                accessoryActivation: .providerAction("delete:\(countdown.id.uuidString)"),
                iconSystemImage: "timer",
                accessoryText: "Target \(targetDateFormatter.string(from: countdown.targetDate))",
                accessoryPresentation: .init(systemImage: "trash", help: "Delete countdown")
            )
        }

        return [addRow] + countdownRows
    }

    private func presentEditor(for countdown: Countdown? = nil) -> (name: String, targetDate: Date)? {
        let alert = NSAlert()
        alert.messageText = countdown == nil ? "Add Countdown" : "Edit Countdown"
        alert.informativeText = "Choose a name and target date."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(string: countdown?.name ?? "")
        nameField.placeholderString = "Countdown name"
        nameField.setAccessibilityLabel("Countdown name")
        nameField.isEditable = true
        nameField.isSelectable = true

        let datePicker = NSDatePicker()
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerMode = .single
        datePicker.datePickerElements = [.yearMonthDay, .hourMinuteSecond]
        datePicker.dateValue = countdown?.targetDate ?? now().addingTimeInterval(3_600)
        datePicker.isEnabled = true
        datePicker.setAccessibilityLabel("Target date")

        let nameLabel = NSTextField(labelWithString: "Name")
        nameLabel.setAccessibilityLabel("Name field label")
        nameLabel.alignment = .right

        let dateLabel = NSTextField(labelWithString: "Target")
        dateLabel.setAccessibilityLabel("Target field label")
        dateLabel.alignment = .right

        // NSAlert measures accessory views before laying out its window. Explicit
        // frames keep the form measurable and leave the date picker's text field
        // and stepper with enough room to receive mouse and keyboard input.
        let formWidth: CGFloat = 460
        let formHeight: CGFloat = 84
        let labelWidth: CGFloat = 72
        let controlLeading: CGFloat = 88
        let rowHeight: CGFloat = 28
        let form = NSView(frame: NSRect(x: 0, y: 0, width: formWidth, height: formHeight))
        let controlWidth = formWidth - controlLeading
        nameLabel.frame = NSRect(x: 0, y: formHeight - rowHeight, width: labelWidth, height: rowHeight)
        nameField.frame = NSRect(x: controlLeading, y: formHeight - rowHeight, width: controlWidth, height: rowHeight)
        dateLabel.frame = NSRect(x: 0, y: 0, width: labelWidth, height: rowHeight)
        datePicker.frame = NSRect(x: controlLeading, y: 0, width: controlWidth, height: rowHeight)
        form.addSubview(nameLabel)
        form.addSubview(nameField)
        form.addSubview(dateLabel)
        form.addSubview(datePicker)

        alert.accessoryView = form
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let name = nameField.stringValue
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !name.isEmpty else {
            showValidationError("Enter a countdown name.")
            return nil
        }
        guard datePicker.dateValue > now() else {
            showValidationError("Choose a target date in the future.")
            return nil
        }

        return (String(name.prefix(200)), datePicker.dateValue)
    }

    private func confirmDeletion() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Delete countdown?"
        alert.informativeText = "This countdown will be removed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showValidationError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Countdown not saved"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func id(from action: String, prefix: String) -> UUID? {
        guard action.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(action.dropFirst(prefix.count)))
    }

    private static let targetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
