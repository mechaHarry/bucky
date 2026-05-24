import SwiftUI

@available(macOS 26.0, *)
struct AgendaView: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    @State private var draftReminder = AgendaReminder(name: "")

    private var selectedNote: AgendaNoteReference? {
        let notes = model.filteredAgendaNotes
        guard notes.indices.contains(model.agendaSelectedNoteIndex) else { return nil }
        return notes[model.agendaSelectedNoteIndex]
    }

    private var selectedReminder: AgendaReminder? {
        let reminders = model.filteredAgendaReminders
        guard reminders.indices.contains(model.agendaSelectedReminderIndex) else { return nil }
        return reminders[model.agendaSelectedReminderIndex]
    }

    var body: some View {
        ZStack {
            columnsPane
                .opacity(model.openedAgendaNote == nil ? 1 : 0)
                .allowsHitTesting(model.openedAgendaNote == nil)

            if model.openedAgendaNote != nil {
                openedNotePane
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .padding(12)
        .animation(.smooth(duration: 0.16), value: model.openedAgendaNote?.id)
        .onAppear {
            loadSelectedReminder()
        }
        .onChange(of: model.agendaSelectedReminderIndex) {
            loadSelectedReminder()
        }
        .onChange(of: model.filteredAgendaReminders) {
            loadSelectedReminder()
        }
    }

    @ViewBuilder
    private var columnsPane: some View {
        HStack(spacing: 12) {
            AgendaColumn(title: "Notes", isActive: model.agendaSelectionColumn == .notes) {
                ForEach(Array(model.filteredAgendaNotes.enumerated()), id: \.element.id) { index, note in
                    AgendaRow(
                        title: note.title,
                        subtitle: note.subtitle,
                        isSelected: model.agendaSelectionColumn == .notes && model.agendaSelectedNoteIndex == index
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture {
                        model.agendaSelectionColumn = .notes
                        model.agendaSelectedNoteIndex = index
                    }
                }
            }

            AgendaColumn(title: "Reminders", isActive: model.agendaSelectionColumn == .reminders) {
                ForEach(Array(model.filteredAgendaReminders.enumerated()), id: \.element.id) { index, reminder in
                    AgendaRow(
                        title: reminder.name,
                        subtitle: reminder.subtitle,
                        isSelected: model.agendaSelectionColumn == .reminders && model.agendaSelectedReminderIndex == index
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture {
                        model.agendaSelectionColumn = .reminders
                        model.agendaSelectedReminderIndex = index
                        loadReminderDraft(reminder)
                    }
                }
            }

            detailPane
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.agendaSelectionColumn {
            case .notes:
                if let note = selectedNote {
                    Text(note.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    AgendaPlaceholder(text: "Press Return to open")
                } else {
                    AgendaPlaceholder(text: "No notes")
                }
            case .reminders:
                if selectedReminder != nil {
                    reminderEditor
                } else {
                    AgendaPlaceholder(text: "No reminders")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.26))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
        }
    }

    private var openedNotePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note = model.openedAgendaNote {
                Text(note.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }

            TextEditor(text: $model.agendaOpenNoteText)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.26))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
        }
    }

    private var reminderEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $draftReminder.name)
            TextField("Date", text: $draftReminder.date)
            TextField("Time", text: $draftReminder.time)
            TextField("URL", text: $draftReminder.urlString)
            TextEditor(text: $draftReminder.details)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
        }
        .textFieldStyle(.roundedBorder)
        .onChange(of: draftReminder) {
            model.updateAgendaReminder(draftReminder)
        }
    }

    private func loadSelectedReminder() {
        guard let selectedReminder else {
            draftReminder = AgendaReminder(name: "")
            return
        }
        loadReminderDraft(selectedReminder)
    }

    private func loadReminderDraft(_ reminder: AgendaReminder) {
        guard draftReminder.id != reminder.id else { return }
        draftReminder = reminder
    }
}

@available(macOS 26.0, *)
private struct AgendaColumn<Content: View>: View {
    let title: String
    let isActive: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

            ScrollView {
                LazyVStack(spacing: 6) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        }
        .padding(10)
        .frame(width: 190, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isActive ? 0.34 : 0.22))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.48) : Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 1)
        }
    }
}

@available(macOS 26.0, *)
private struct AgendaRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.isEmpty ? "Untitled" : title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        }
    }
}

@available(macOS 26.0, *)
private struct AgendaPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
