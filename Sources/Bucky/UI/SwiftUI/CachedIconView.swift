import SwiftUI

/// Shared SwiftUI loading lifecycle: disappearing rows cancel their waiter, not other rows' work.
@available(macOS 26.0, *)
struct CachedIconView: View {
    let url: URL
    let cache: IconCache
    let fallbackSymbol: String
    var isActive = true
    var loadDelayNanoseconds: UInt64 = 0
    @State private var icon: NSImage?

    var body: some View {
        ZStack {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: LoadIdentity(url: url, isActive: isActive)) {
            guard isActive else { icon = nil; return }
            let cachedIcon = await cache.cachedIcon(for: url)
            guard !Task.isCancelled else { return }
            icon = cachedIcon
            if icon == nil {
                if loadDelayNanoseconds > 0 {
                    do { try await Task.sleep(nanoseconds: loadDelayNanoseconds) } catch { return }
                    guard !Task.isCancelled else { return }
                }
                let loadedIcon = await cache.icon(for: url)
                guard !Task.isCancelled else { return }
                icon = loadedIcon
            }
        }
        .onDisappear { icon = nil }
    }

    private struct LoadIdentity: Equatable {
        let url: URL
        let isActive: Bool
    }
}
