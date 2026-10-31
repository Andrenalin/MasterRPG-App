// @copyright André Trettin

import Foundation
import Observation

/// The state of the sync sheet: scan, show what differs, apply what the user left selected.
@MainActor @Observable
final class CloudFolderScanModel {
    enum Phase: Equatable {
        case scanning
        case found(CloudScanPlan)
        case nothingFound
        case unavailable
        /// The module folder cannot be read, so nothing can be compared.
        case unreachable
        case syncing
        case synced(added: Int, folders: Int, moved: Int, trashed: Int)
        case busy
    }

    private(set) var phase: Phase = .scanning {
        didSet { refreshSelectedPlan() }
    }

    /// What the user took out. Additions and moves are selected by default, so only the exceptions
    /// are kept; removals start deselected, so trashing an item is always the user's own choice.
    /// See CODE_AUDIT_22 §5.2.
    private(set) var deselected: Set<UUID> = [] {
        didSet { refreshSelectedPlan() }
    }

    /// The plan as it will be applied: without the deselected entries, and with the new folders
    /// only the selected ones need. Kept up to date when the selection changes, so the sheet does not
    /// restrict the plan again on every evaluation of its body.
    private(set) var selectedPlan: CloudScanPlan?

    private func refreshSelectedPlan() {
        guard case .found(let plan) = phase else {
            selectedPlan = nil
            return
        }
        selectedPlan = plan.restricted(toDeselected: deselected)
    }

    func scan(with controller: CloudScanController) async {
        guard controller.isAvailable else {
            phase = .unavailable
            return
        }
        phase = .scanning
        deselected = []
        guard let result = await controller.scan() else { return }
        switch result {
        case .unreachable:
            phase = .unreachable
        case .plan(let plan):
            deselected = Set(plan.removals.map(\.id))
            phase = plan.isEmpty ? .nothingFound : .found(plan)
        }
    }

    func isSelected(_ id: UUID) -> Bool {
        !deselected.contains(id)
    }

    func toggle(_ id: UUID) {
        if !deselected.insert(id).inserted {
            deselected.remove(id)
        }
    }

    /// Selects or deselects every entry of one section.
    func setSelected(_ isSelected: Bool, for ids: [UUID]) {
        if isSelected {
            deselected.subtract(ids)
        } else {
            deselected.formUnion(ids)
        }
    }

    func areAllSelected(_ ids: [UUID]) -> Bool {
        ids.allSatisfy { !deselected.contains($0) }
    }

    /// Whether Sync has anything to apply.
    var hasSelection: Bool {
        guard let plan = selectedPlan else { return false }
        return !(plan.items.isEmpty && plan.moves.isEmpty && plan.removals.isEmpty)
    }

    func sync(with controller: CloudScanController) async {
        guard let plan = selectedPlan, hasSelection else { return }
        phase = .syncing
        switch await controller.apply(plan) {
        case .synced(let added, let folders, let moved, let trashed):
            phase = .synced(added: added, folders: folders, moved: moved, trashed: trashed)
        case .busy:
            phase = .busy
        case .unreachable:
            phase = .unreachable
        }
    }
}
