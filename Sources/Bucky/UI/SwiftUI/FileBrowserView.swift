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

            if case let .quickLook(url) = model.focusState {
                QuickLookPreviewSurface(url: url, entry: model.entry(for: url))
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
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
                        FileIconView(url: url)
                            .frame(width: 18, height: 18)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .help(url.path)
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
                                isMarked: model.selectedURLs.contains(entry.url)
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

            FileIconView(url: entry.url)
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
private struct QuickLookPreviewSurface: View {
    let url: URL
    let entry: FileBrowserEntry?

    var body: some View {
        VStack(spacing: 14) {
            FileIconView(url: url)
                .frame(width: 96, height: 96)

            Text(url.lastPathComponent)
                .font(.headline)
                .lineLimit(1)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                metadataRow("Kind", entry?.kind.displayName ?? "Unknown")
                metadataRow("Size", formattedSize)
                metadataRow("Created", formattedDate(entry?.createdAt))
                metadataRow("Modified", formattedDate(entry?.modifiedAt))
            }
            .font(.caption)

            FadeMarqueeText(text: url.path, font: .caption)
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
private struct FileIconView: View {
    let url: URL
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
            icon = MacFileServices().icon(for: url)
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
