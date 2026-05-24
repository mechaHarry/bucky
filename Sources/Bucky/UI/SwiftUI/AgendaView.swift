import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct AgendaView: View {
    @ObservedObject var model: LiquidGlassLauncherModel
    @State private var noteSearchText = ""
    @State private var noteSearchRequest = 0
    @State private var noteSearchBackwards = false
    @State private var isShowingNoteSearch = false
    @FocusState private var isNoteEditorFocused: Bool

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
        .onChange(of: model.openedAgendaNote?.id) {
            if model.openedAgendaNote != nil {
                DispatchQueue.main.async {
                    isNoteEditorFocused = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    }
                }
            }
        }
    }

    private var openedNotePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note = model.openedAgendaNote {
                Text(note.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }

            if isShowingNoteSearch {
                HStack(spacing: 8) {
                    TextField("Search", text: $noteSearchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            searchNote(backwards: false)
                        }

                    Button("Prev") {
                        searchNote(backwards: true)
                    }

                    Button("Next") {
                        searchNote(backwards: false)
                    }
                }
            }

            AgendaNoteEditor(
                text: $model.agendaOpenNoteText,
                isFocused: isNoteEditorFocused,
                searchText: noteSearchText,
                searchRequest: noteSearchRequest,
                searchBackwards: noteSearchBackwards,
                onBeginSearch: {
                    isShowingNoteSearch = true
                }
            )
            .focused($isNoteEditorFocused)
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

    private func searchNote(backwards: Bool) {
        noteSearchBackwards = backwards
        noteSearchRequest += 1
    }
}

@available(macOS 26.0, *)
private struct AgendaNoteEditor: NSViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let searchText: String
    let searchRequest: Int
    let searchBackwards: Bool
    let onBeginSearch: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = VimTextView()
        textView.string = text
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.onBeginSearch = onBeginSearch
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? VimTextView else { return }
        textView.onBeginSearch = onBeginSearch
        if textView.string != text {
            textView.string = text
        }
        if context.coordinator.lastSearchRequest != searchRequest {
            context.coordinator.lastSearchRequest = searchRequest
            textView.find(searchText, backwards: searchBackwards)
        }
        if isFocused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: VimTextView?
        var lastSearchRequest = 0

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private final class VimTextView: NSTextView {
    var onBeginSearch: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.isEmpty, event.charactersIgnoringModifiers == "/" {
            onBeginSearch?()
            return
        }

        if flags.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "h":
                moveLeft(nil)
                return
            case "j":
                moveDown(nil)
                return
            case "k":
                moveUp(nil)
                return
            case "l":
                moveRight(nil)
                return
            default:
                break
            }
        }

        super.keyDown(with: event)
    }

    func find(_ query: String, backwards: Bool) {
        guard !query.isEmpty else { return }
        let source = string as NSString
        let selectedRange = selectedRange()
        let options: NSString.CompareOptions = backwards ? [.caseInsensitive, .backwards] : [.caseInsensitive]
        let range: NSRange
        if backwards {
            range = NSRange(location: 0, length: selectedRange.location)
        } else {
            let start = selectedRange.location + selectedRange.length
            range = NSRange(location: start, length: max(source.length - start, 0))
        }

        var match = source.range(of: query, options: options, range: range)
        if match.location == NSNotFound {
            match = source.range(
                of: query,
                options: options,
                range: NSRange(location: 0, length: source.length)
            )
        }
        guard match.location != NSNotFound else { return }
        setSelectedRange(match)
        scrollRangeToVisible(match)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
