// @copyright André Trettin

import SwiftUI

/// A player of the running game and whether they confirmed receiving a shared item.
public struct PlayerReportStatus: Identifiable, Equatable, Sendable {
    public init(id: UUID, name: String, reported: Bool) {
        self.id = id
        self.name = name
        self.reported = reported
    }

    public let id: UUID
    public let name: String
    public let reported: Bool
}

public extension [SharingControlModel] {
    /// The players a share lists — visible, name-sorted — each flagged by `isReported`.
    func playerReportStatuses(isReported: (UUID) -> Bool) -> [PlayerReportStatus] {
        visibleSortedByName
            .map { PlayerReportStatus(id: $0.id, name: $0.name, reported: isReported($0.id)) }
    }
}

/// The players a share was sent to: confirmed names bold, pending ones secondary, and a
/// checkmark once everyone confirmed. On a player device, which lists no players, it shows
/// the download of the item's file instead (`transfer`). Shows nothing without either.
public struct PlayerReportRow: View {
    public init(statuses: [PlayerReportStatus], transfer: ItemTransferStatus? = nil) {
        self.statuses = statuses
        self.transfer = transfer
    }

    let statuses: [PlayerReportStatus]
    let transfer: ItemTransferStatus?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    /// Insets of the player report capsule, scaling with Dynamic Type. See CODE_AUDIT_20 §8.7.
    @ScaledMetric(relativeTo: .caption) private var reportHorizontalInset: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var reportVerticalInset: CGFloat = 3

    public var body: some View {
        if !statuses.isEmpty || transfer != nil {
            HStack(spacing: 4) {
                if statuses.isEmpty, let transfer {
                    TransferStatusText(transfer: transfer)
                } else {
                    Text(attributedNames)
                    if statuses.allSatisfy(\.reported) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .font(.caption)
            // Drawn over the photo or text below it: the glass of the round module buttons
            // (`GameWindowButtonAppearance`) keeps it legible, without `.interactive()` since
            // the row is a caption, not a control. See CODE_AUDIT_19 §8.1.
            .padding(.horizontal, reportHorizontalInset)
            .padding(.vertical, reportVerticalInset)
#if os(visionOS)
            .background(.regularMaterial, in: .capsule)
#else
            .glassEffect(.regular, in: .capsule)
#endif
            .animation(accessibilityReduceMotion ? nil : .default, value: statuses.map(\.reported))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

/// The download of an item's file on a player device: `Started`, `Loading 10s` while it
/// runs, `4.2s · 1.3 MB/s` when it arrived, `Failed` when it did not.
struct TransferStatusText: View {
    let transfer: ItemTransferStatus

    var body: some View {
        switch transfer.state {
        case .loading where transfer.duration == .zero:
            Text("Started", bundle: .module)
                .foregroundStyle(.secondary)
        case .loading:
            Text("Loading \(transfer.duration.formatted(ItemTransferStatus.durationStyle))", bundle: .module)
                .foregroundStyle(.secondary)
        case .done:
            Text(verbatim: ItemTransferStatus.summary(duration: transfer.duration, byteCount: transfer.byteCount))
        case .failed:
            Text("Failed", bundle: .module)
                .foregroundStyle(.red)
        }
    }
}

private extension PlayerReportRow {
    func attributedName(for status: PlayerReportStatus) -> AttributedString {
        var playerName = status.name
        if let firstName = status.name.split(separator: " ").first {
            playerName = String(firstName)
        }

        var name = AttributedString(playerName)
        if status.reported {
            name.font = .caption.bold()
        } else {
            name.foregroundColor = .secondary
        }
        return name
    }

    var attributedNames: AttributedString {
        statuses.enumerated().reduce(into: AttributedString()) { line, entry in
            let (index, status) = entry
            if index > 0 {
                line += AttributedString(", ")
            }
            line += attributedName(for: status)
        }
    }

    var accessibilityLabel: Text {
        if statuses.isEmpty, let transfer {
            return switch transfer.state {
            case .loading where transfer.duration == .zero:
                Text("Download started", bundle: .module)
            case .loading:
                Text("Downloading for \(transfer.duration.formatted(ItemTransferStatus.durationStyle))", bundle: .module)
            case .done:
                Text("Downloaded: \(ItemTransferStatus.summary(duration: transfer.duration, byteCount: transfer.byteCount))", bundle: .module)
            case .failed:
                Text("Download failed", bundle: .module)
            }
        }
        let reportedNames = statuses.filter(\.reported).map(\.name).joined(separator: ", ")
        let missingNames = statuses.filter { !$0.reported }.map(\.name).joined(separator: ", ")
        if missingNames.isEmpty {
            return Text("All players confirmed: \(reportedNames)", bundle: .module)
        }
        if reportedNames.isEmpty {
            return Text("Waiting on: \(missingNames)", bundle: .module)
        }
        return Text("Confirmed: \(reportedNames). Waiting on: \(missingNames)", bundle: .module)
    }
}

#Preview("Player download") {
    VStack(alignment: .leading) {
        PlayerReportRow(statuses: [], transfer: .init(state: .loading))
        PlayerReportRow(statuses: [], transfer: .init(state: .loading, duration: .seconds(10)))
        PlayerReportRow(statuses: [], transfer: .init(state: .done, duration: .milliseconds(4200), byteCount: 5_460_000))
        PlayerReportRow(statuses: [], transfer: .init(state: .failed, duration: .seconds(180)))
    }
    .padding()
}

#Preview {
    PlayerReportRow(statuses: [
        PlayerReportStatus(id: .fixture2, name: "Arin Doof", reported: true),
        PlayerReportStatus(id: .fixture3, name: "Zara Mega", reported: false)
    ])
    .padding()
}
