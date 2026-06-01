// @copyright André Trettin

import SwiftUI

/// Shows CloudKit sync status to user during restore/sync operations
public struct CloudKitSyncStatusView: View {
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
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Restoring your data...", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            case .succeeded:
                if let lastSync = lastSync, Date().timeIntervalSince(lastSync) < 60 {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Synced with iCloud", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
                }

            case .failed(let error):
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sync Issue", bundle: .module)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .animation(.easeInOut, value: syncState)
    }
}

#Preview("Syncing") {
    CloudKitSyncStatusView(syncState: .inProgress, lastSync: nil)
        .padding()
}

#Preview("Succeeded") {
    CloudKitSyncStatusView(syncState: .succeeded, lastSync: Date())
        .padding()
}

#Preview("Failed") {
    CloudKitSyncStatusView(syncState: .failed("Network connection lost"), lastSync: nil)
        .padding()
}
