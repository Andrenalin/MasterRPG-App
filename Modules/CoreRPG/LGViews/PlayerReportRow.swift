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
/// checkmark once everyone confirmed. Shows nothing without players.
public struct PlayerReportRow: View {
    public init(statuses: [PlayerReportStatus]) {
        self.statuses = statuses
    }

    let statuses: [PlayerReportStatus]

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    /// Insets of the player report capsule, scaling with Dynamic Type. See CODE_AUDIT_20 §8.7.
    @ScaledMetric(relativeTo: .caption) private var reportHorizontalInset: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var reportVerticalInset: CGFloat = 3

    public var body: some View {
        if !statuses.isEmpty {
            HStack(spacing: 4) {
                Text(attributedNames)
                if statuses.allSatisfy(\.reported) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .font(.caption)
            // Drawn over the photo or text below it: a material background keeps it legible.
            // See CODE_AUDIT_19 §8.1.
            .padding(.horizontal, reportHorizontalInset)
            .padding(.vertical, reportVerticalInset)
            .background(.regularMaterial, in: .capsule)
            .animation(accessibilityReduceMotion ? nil : .default, value: statuses.map(\.reported))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
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

#Preview {
    PlayerReportRow(statuses: [
        PlayerReportStatus(id: .fixture2, name: "Arin Doof", reported: true),
        PlayerReportStatus(id: .fixture3, name: "Zara Mega", reported: false)
    ])
    .padding()
}
