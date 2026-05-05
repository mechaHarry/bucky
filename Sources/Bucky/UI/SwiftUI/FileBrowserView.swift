import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct FileBrowserView: View {
    @ObservedObject var model: FileBrowserModel
    @State private var transferGlow = false

    var body: some View {
        ZStack(alignment: .trailing) {
            browsePane

            if model.focusState == .previewActions {
                actionOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if case .transferPending = model.focusState {
                actionOverlay
                    .offset(x: 214)
                    .opacity(0.34)
                    .blur(radius: 2.5)
                    .allowsHitTesting(false)
                transferHint
                    .transition(.opacity)
            }

            if case let .quickLook(preview) = model.focusState {
                QuickLookPreviewSurface(model: model, preview: preview, entry: model.entry(for: preview.url))
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            focusedOverlay

            if let statusMessage = model.statusMessage {
                statusOverlay(statusMessage)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            transferGlow = isTransferPending
        }
        .onChange(of: isTransferPending) { _, isPending in
            transferGlow = isPending
        }
        .animation(.easeInOut(duration: 0.18), value: model.focusState)
    }

    private var browsePane: some View {
        HStack(spacing: 10) {
            pinnedRail
                .frame(width: 150)

            directoryColumns
        }
        .padding(10)
        .overlay {
            if isTransferPending {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(transferGlow ? 0.70 : 0.25), lineWidth: 1.5)
                    .shadow(color: Color.accentColor.opacity(transferGlow ? 0.52 : 0.18), radius: 16)
                    .padding(8)
                    .animation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true), value: transferGlow)
            }
        }
    }

    private var pinnedRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pinned", systemImage: "pin")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            if model.pinnedDirectories.isEmpty {
                placeholder("Pinned folders will appear here")
            } else {
                ForEach(model.pinnedDirectories, id: \.self) { url in
                    HStack(spacing: 8) {
                        FadeMarqueeText(text: url.lastPathComponent, font: .system(size: 13, weight: .medium))
                        FileIconView(url: url, model: model)
                            .frame(width: 18, height: 18)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .help(url.path)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture {
                        model.openPinnedDirectory(url)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 1)
        }
    }

    private var directoryColumns: some View {
        let snapshots = model.directorySnapshots.isEmpty
            ? [FileBrowserDirectorySnapshot(directory: model.currentDirectory, entries: model.entries)]
            : model.directorySnapshots

        return HStack(spacing: 10) {
            ForEach(snapshots, id: \.directory) { snapshot in
                fileListColumn(snapshot)
            }
        }
    }

    private func fileListColumn(_ snapshot: FileBrowserDirectorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title(for: snapshot.directory))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text("\(snapshot.entries.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if snapshot.entries.isEmpty {
                placeholder(snapshot.directory == model.currentDirectory ? "No readable files" : "No preview data")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(snapshot.entries.enumerated()), id: \.element.url) { index, entry in
                            FileBrowserRow(
                                entry: entry,
                                isSelected: isSelected(entry, at: index, in: snapshot),
                                isMarked: model.selectedURLs.contains(entry.url),
                                model: model
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 1)
        }
    }

    private var actionOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Actions")
                    .font(.headline)
                selectionSummary
            }

            Divider()
                .opacity(0.42)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(model.focusableActions.enumerated()), id: \.element) { index, action in
                    ActionRow(
                        action: action,
                        isFocused: index == model.focusedActionIndex
                    )
                }
            }
        }
        .padding(16)
        .frame(width: 286)
        .glassEffect(.regular.interactive(false), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 14)
        .padding(18)
    }

    @ViewBuilder
    private var selectionSummary: some View {
        let urls = model.activeSelectionURLs

        if urls.count <= 1, let url = urls.first {
            FadeMarqueeText(text: url.path, font: .caption)
                .foregroundStyle(.secondary)
                .frame(height: 16)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(selectionGroups, id: \.parent) { group in
                    HStack(spacing: 8) {
                        Text("\(group.count)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 28, alignment: .trailing)
                        FadeMarqueeText(text: group.parent.path, font: .caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 16)
                }
            }
        }
    }

    private var transferHint: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text("Destination staged")
                .font(.callout.weight(.semibold))
            Text("Return confirms here. Escape cancels.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(false), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.accentColor.opacity(0.36), lineWidth: 1)
        }
        .shadow(color: Color.accentColor.opacity(0.24), radius: 18)
        .padding(.trailing, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    @ViewBuilder
    private var focusedOverlay: some View {
        switch model.focusState {
        case .renaming:
            RenameOverlay(model: model)
                .transition(.scale(scale: 0.97).combined(with: .opacity))
        case let .confirming(.transfer(transfer, destination)):
            ConfirmationOverlay(
                title: "Confirm \(transfer.displayName)",
                message: "Return \(transfer.confirmationVerb) the staged items into \(displayName(for: destination)). Escape returns to destination selection."
            )
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        case let .confirming(.trash(urls, step)):
            ConfirmationOverlay(
                title: step == 1 ? "Move to Trash?" : "Confirm Trash",
                message: step == 1
                    ? "Return continues. \(urls.count) item\(urls.count == 1 ? "" : "s") will be moved to Trash, never permanently deleted."
                    : "Return moves the selected item\(urls.count == 1 ? "" : "s") to Trash. Escape cancels."
            )
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        case let .confirming(.conflict(_, _, conflicts)):
            ConflictOverlay(conflicts: conflicts, focusedResolution: model.focusedConflictResolution)
                .transition(.scale(scale: 0.97).combined(with: .opacity))
        default:
            EmptyView()
        }
    }

    private func statusOverlay(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
            Text(message)
                .font(.caption.weight(.medium))
                .lineLimit(2)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(false), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.red.opacity(0.34), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 18)
    }

    private var selectionGroups: [(parent: URL, count: Int)] {
        let grouped = Dictionary(grouping: model.activeSelectionURLs) { url in
            url.deletingLastPathComponent()
        }
        return grouped
            .map { (parent: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in lhs.parent.path.localizedStandardCompare(rhs.parent.path) == .orderedAscending }
    }

    private var isTransferPending: Bool {
        if case .transferPending = model.focusState {
            return true
        }
        return false
    }

    private func isSelected(_ entry: FileBrowserEntry, at index: Int, in snapshot: FileBrowserDirectorySnapshot) -> Bool {
        if snapshot.directory == model.currentDirectory {
            return index == model.selectedIndex
        }
        return entry.url == model.currentDirectory
    }

    private func title(for directory: URL) -> String {
        let title = directory.lastPathComponent
        return title.isEmpty ? "/" : title
    }

    private func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

@available(macOS 26.0, *)
private struct FileBrowserRow: View {
    let entry: FileBrowserEntry
    let isSelected: Bool
    let isMarked: Bool
    @ObservedObject var model: FileBrowserModel

    var body: some View {
        HStack(spacing: 10) {
            FadeMarqueeText(text: entry.name, font: .system(size: 14, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if isMarked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            FileIconView(url: entry.url, model: model)
                .frame(width: 23, height: 23)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
        .background(rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(rowRim, lineWidth: isSelected ? 1.15 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var rowFill: Color {
        if isSelected {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.26)
        }
        if isMarked {
            return Color.accentColor.opacity(0.12)
        }
        return Color(nsColor: .windowBackgroundColor).opacity(0.12)
    }

    private var rowRim: Color {
        if isSelected {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.45)
        }
        if isMarked {
            return Color.accentColor.opacity(0.28)
        }
        return Color(nsColor: .separatorColor).opacity(0.16)
    }
}

@available(macOS 26.0, *)
private struct ActionRow: View {
    let action: FileBrowserAction
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(isFocused ? .primary : .secondary)

            Text(action.displayName)
                .font(.system(size: 14, weight: .medium))

            Spacer(minLength: 8)

            if isFocused {
                Image(systemName: "return")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isFocused ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.24) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.38) : .clear, lineWidth: 1)
        }
    }
}

@available(macOS 26.0, *)
private struct RenameOverlay: View {
    @ObservedObject var model: FileBrowserModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: state?.mode == .batch ? "textformat.123" : "pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state?.mode == .batch ? "Batch Rename" : "Rename")
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Name", text: Binding(
                get: { state?.proposedName ?? "" },
                set: { model.setRenameText($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit {
                model.handle(.open)
            }

            Text("Return confirms. Escape cancels.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 340)
        .glassEffect(.regular.interactive(false), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.26), radius: 28, x: 0, y: 16)
        .onAppear {
            isFocused = true
        }
    }

    private var state: FileBrowserRenameState? {
        model.renameState
    }

    private var subtitle: String {
        guard let state else { return "" }
        switch state.mode {
        case .single:
            return state.urls.first?.lastPathComponent ?? ""
        case .batch:
            return "\(state.urls.count) items, numbered suffixes"
        }
    }
}

@available(macOS 26.0, *)
private struct ConfirmationOverlay: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Return confirms. Escape cancels.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 340)
        .glassEffect(.regular.interactive(false), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.26), radius: 28, x: 0, y: 16)
    }
}

@available(macOS 26.0, *)
private struct ConflictOverlay: View {
    let conflicts: [FileBrowserConflict]
    let focusedResolution: FileBrowserConflictResolution

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name Conflict")
                    .font(.headline)
                Text(conflictSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(spacing: 5) {
                ForEach(FileBrowserConflictResolution.allCases, id: \.self) { resolution in
                    ConflictResolutionRow(
                        resolution: resolution,
                        isFocused: resolution == focusedResolution
                    )
                }
            }

            Text("Up and Down choose. Return applies.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 340)
        .glassEffect(.regular.interactive(false), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.26), radius: 28, x: 0, y: 16)
    }

    private var conflictSummary: String {
        guard let first = conflicts.first else {
            return "A destination already contains an item with the same name."
        }
        let extraCount = conflicts.count - 1
        let suffix = extraCount > 0 ? " and \(extraCount) more" : ""
        return "\(first.destination.lastPathComponent)\(suffix)"
    }
}

@available(macOS 26.0, *)
private struct ConflictResolutionRow: View {
    let resolution: FileBrowserConflictResolution
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: resolution.symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(isFocused ? .primary : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(resolution.displayName)
                    .font(.system(size: 14, weight: .medium))
                Text(resolution.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isFocused {
                Image(systemName: "return")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isFocused ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.24) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.38) : .clear, lineWidth: 1)
        }
    }
}

@available(macOS 26.0, *)
private struct QuickLookPreviewSurface: View {
    @ObservedObject var model: FileBrowserModel
    let preview: FileBrowserPreview
    let entry: FileBrowserEntry?
    @State private var nativePreviewFailed = false

    var body: some View {
        if preview.mode == .nativeThumbnail && !nativePreviewFailed {
            nativePreview
        } else {
            metadataFallback
        }
    }

    private var nativePreview: some View {
        VStack(spacing: 14) {
            NativeQuickLookThumbnailView(url: preview.url, model: model, didFail: $nativePreviewFailed)
                .frame(width: 360, height: 210)

            Text(preview.url.lastPathComponent)
                .font(.headline)
                .lineLimit(1)

            FadeMarqueeText(text: preview.url.path, font: .caption)
                .foregroundStyle(.secondary)
                .frame(height: 16)
        }
        .padding(24)
        .frame(width: 420, height: 300)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.30), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 34, x: 0, y: 18)
    }

    private var metadataFallback: some View {
        VStack(spacing: 14) {
            FileIconView(url: preview.url, model: model)
                .frame(width: 96, height: 96)

            Text(preview.url.lastPathComponent)
                .font(.headline)
                .lineLimit(1)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                metadataRow("Kind", entry?.kind.displayName ?? "Unknown")
                metadataRow("Size", formattedSize)
                metadataRow("Created", formattedDate(entry?.createdAt))
                metadataRow("Modified", formattedDate(entry?.modifiedAt))
            }
            .font(.caption)

            FadeMarqueeText(text: preview.url.path, font: .caption)
                .foregroundStyle(.secondary)
                .frame(height: 16)
        }
        .padding(24)
        .frame(width: 420, height: 300)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.30), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 34, x: 0, y: 18)
    }

    private var formattedSize: String {
        guard let size = entry?.size else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return Self.dateFormatter.string(from: date)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

@available(macOS 26.0, *)
private struct NativeQuickLookThumbnailView: NSViewRepresentable {
    let url: URL
    @ObservedObject var model: FileBrowserModel
    @Binding var didFail: Bool

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        context.coordinator.loadThumbnail(for: url, model: model, into: imageView, didFail: $didFail)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var representedURL: URL?

        @MainActor
        func loadThumbnail(
            for url: URL,
            model: FileBrowserModel,
            into imageView: NSImageView,
            didFail: Binding<Bool>
        ) {
            guard representedURL != url else { return }
            representedURL = url
            imageView.image = nil
            didFail.wrappedValue = false

            let scale = NSScreen.main?.backingScaleFactor ?? 2
            model.loadPreviewThumbnail(for: url, size: CGSize(width: 720, height: 420), scale: scale) { image in
                guard self.representedURL == url else { return }
                if let image {
                    imageView.image = image
                } else {
                    didFail.wrappedValue = true
                }
            }
        }
    }
}

@available(macOS 26.0, *)
private struct FileIconView: View {
    let url: URL
    @ObservedObject var model: FileBrowserModel
    @State private var icon: NSImage?

    var body: some View {
        ZStack {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            icon = model.icon(for: url)
        }
    }
}

private extension FileBrowserAction {
    var displayName: String {
        switch self {
        case .open:
            return "Open"
        case .rename:
            return "Rename"
        case .batchRename:
            return "Batch Rename"
        case .revealInFinder:
            return "Reveal in Finder"
        case .copyPath:
            return "Copy Path"
        case .copyPaths:
            return "Copy Paths"
        case .copy:
            return "Copy"
        case .move:
            return "Move"
        case .moveToTrash:
            return "Move to Trash"
        }
    }

    var symbol: String {
        switch self {
        case .open:
            return "arrow.up.right.square"
        case .rename, .batchRename:
            return "pencil"
        case .revealInFinder:
            return "finder"
        case .copyPath, .copyPaths:
            return "doc.on.doc"
        case .copy:
            return "plus.square.on.square"
        case .move:
            return "arrow.right.square"
        case .moveToTrash:
            return "trash"
        }
    }
}

private extension FileBrowserTransfer {
    var displayName: String {
        switch self {
        case .copy:
            return "Copy"
        case .move:
            return "Move"
        }
    }

    var confirmationVerb: String {
        switch self {
        case .copy:
            return "copies"
        case .move:
            return "moves"
        }
    }
}

private extension FileBrowserConflictResolution {
    var displayName: String {
        switch self {
        case .keepBoth:
            return "Keep Both"
        case .replace:
            return "Replace"
        case .cancel:
            return "Cancel"
        }
    }

    var detail: String {
        switch self {
        case .keepBoth:
            return "Create a numbered copy"
        case .replace:
            return "Overwrite the destination item"
        case .cancel:
            return "Leave files unchanged"
        }
    }

    var symbol: String {
        switch self {
        case .keepBoth:
            return "plus.square.on.square"
        case .replace:
            return "arrow.triangle.2.circlepath"
        case .cancel:
            return "xmark.circle"
        }
    }
}

private extension FileBrowserEntry.Kind {
    var displayName: String {
        switch self {
        case .file:
            return "File"
        case .directory:
            return "Directory"
        case .package:
            return "Package"
        case .symbolicLink:
            return "Alias"
        case .other:
            return "Other"
        }
    }
}
