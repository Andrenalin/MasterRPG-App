// @copyright André Trettin

import SwiftUI

/// Shows CloudKit sync status to user during restore/sync operations
public struct CloudKitSyncStatusView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.appTheme) private var theme
    
    let syncState: CloudKitSyncState
    let lastSync: Date?

    public init(syncState: CloudKitSyncState, lastSync: Date?) {
        self.syncState = syncState
        self.lastSync = lastSync
    }

    public var body: some View {
        Group {
            switch syncState {
            case .notStarted:
                EmptyView()

            case .inProgress:
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Syncing with iCloud", bundle: .module)
                            .font(.headline)
                        Text("Restoring your data...", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

            case .succeeded:
                SyncedBadgeView(lastSync: lastSync)

            case .failed(let error):
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sync Issue", bundle: .module)
                            .font(.headline)
                        Text(verbatim: error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding()
            }
        }
        .backgroundStyle(theme.backgroundGradient)
        .animation(accessibilityReduceMotion ? nil : .easeInOut, value: syncState)
    }
}

#Preview("Syncing") {
    VStack(alignment: .leading) {
        
        
        CloudKitSyncStatusView(syncState: .inProgress, lastSync: nil)
            .padding()
        
        CloudKitSyncStatusView(syncState: .succeeded, lastSync: Date())
            .padding()
        CloudKitSyncStatusView(syncState: .failed("Network connection lost"), lastSync: nil)
            .padding()
        
    }
    .preferredColorScheme(.dark)
}

/// The "Synced" badge, shown for a minute after the last sync and gone after that: it hides itself
/// when the minute is over instead of staying until something else re-renders the view.
/// See CODE_AUDIT_26 §5.74.
private struct SyncedBadgeView: View {
    let lastSync: Date?

    private static let visibleDuration: Duration = .seconds(60)

    @State private var isExpired = false

    var body: some View {
        if let lastSync, !isExpired, Date.now.timeIntervalSince(lastSync) < 60 {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Synced with iCloud", bundle: .module)
                    .font(.headline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .transition(.scale.combined(with: .opacity))
            .task(id: lastSync) {
                let remaining = max(0, 60 - Date.now.timeIntervalSince(lastSync))
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
                withAnimation { isExpired = true }
            }
        }
    }
}
