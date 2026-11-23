// @copyright André Trettin

#if os(visionOS)
import AudioRPG
import AVFoundation
import CoreRPG
import Foundation
import os.log
import SwiftUI

import GroupActivities
import TabletopKit

// MARK: - visionOS spatial template configuration

extension RPGSharePlayController {
    func configureSystemCoordinator(for session: GroupSession<RPGActivity>) async {
        let sessionId = session.id
        guard !Task.isCancelled,
              sessionLifecycle.isCurrent(sessionId: sessionId),
              groupSession?.id == sessionId
        else { return }
        guard let coordinator = await Self.systemCoordinator(of: SystemCoordinatorLookup(session: session))?.coordinator,
              !Task.isCancelled,
              sessionLifecycle.isCurrent(sessionId: sessionId),
              groupSession?.id == sessionId
        else { return }
        systemCoordinator = coordinator
        applyShareState()
        observeLocalParticipantSeat(of: coordinator, sessionId: sessionId)
    }

    /// Follows whether the system itself turns the shared volume toward this participant's seat.
    /// That takes a shared spatial context: this participant has a seat of TabletopKit's spatial
    /// template *and* another spatial Persona shares the space. Alone (the only Vision Pro among
    /// iPad and Mac players — their FaceTime tiles are not spatial), the volume stays as it
    /// opened, so the table turns itself toward the claimed seat instead.
    private func observeLocalParticipantSeat(of coordinator: SystemCoordinator, sessionId: UUID) {
        let localTask = Task { @MainActor [weak self] in
            for await _ in coordinator.localParticipantStates {
                guard let self, !Task.isCancelled,
                      self.sessionLifecycle.isCurrent(sessionId: sessionId),
                      self.groupSession?.id == sessionId
                else { return }
                self.updateLocalSeatPlacement(of: coordinator)
            }
        }
        trackSessionTask(localTask, key: Self.localParticipantSeatTaskKey)
        let remoteTask = Task { @MainActor [weak self] in
            for await _ in Observations({ coordinator.remoteParticipantStates }) {
                guard let self, !Task.isCancelled,
                      self.sessionLifecycle.isCurrent(sessionId: sessionId),
                      self.groupSession?.id == sessionId
                else { return }
                self.updateLocalSeatPlacement(of: coordinator)
            }
        }
        trackSessionTask(remoteTask, key: Self.remoteParticipantSeatTaskKey)
    }

    private func updateLocalSeatPlacement(of coordinator: SystemCoordinator) {
        let local = coordinator.localParticipantState
        let remoteSpatialCount = coordinator.remoteParticipantStates.values.count(where: \.isSpatial)
        let placed = local.isSpatial && local.seat != nil && remoteSpatialCount > 0
        Logger.sharePlay.debug("Local participant spatial: \(local.isSpatial, privacy: .public), system seat: \(local.seat != nil, privacy: .public), other spatial participants: \(remoteSpatialCount, privacy: .public) -> table turned by system: \(placed, privacy: .public)")
        isLocalSeatPlacedBySystem = placed
        gameModel?.gameTableModel?.isLocalSeatPlacedBySystem = placed
    }

    /// `systemCoordinator` is a nonisolated async getter on the non-Sendable `GroupSession`, so
    /// reading it from the main actor "sends" the session. The unchecked crossing is scoped to
    /// this one read-only lookup instead of a module-wide `@preconcurrency import`, which hid
    /// every other GroupActivities diagnostic in this file. The coordinator itself is only used
    /// on the main actor afterwards. See CODE_AUDIT_19 §3.10.
    private struct SystemCoordinatorLookup: @unchecked Sendable {
        var session: GroupSession<RPGActivity>?
        var coordinator: SystemCoordinator?
    }

    @concurrent
    private nonisolated static func systemCoordinator(of lookup: SystemCoordinatorLookup) async -> SystemCoordinatorLookup? {
        guard let coordinator = await lookup.session?.systemCoordinator else { return nil }
        return SystemCoordinatorLookup(session: nil, coordinator: coordinator)
    }

    /// Applies the presentation mode to the group session's `SystemCoordinator`.
    ///
    /// The configuration is *modified*, never replaced by a fresh `Configuration()`: in
    /// `.tabletop` mode `TabletopGame.coordinateWithSession(_:)` configures the coordinator itself
    /// (a spatial template whose seats are the table's seats, so the system turns the shared
    /// table toward the seat the local player claims — neither of Apple's TabletopKit samples
    /// touches the coordinator at all). Assigning a new `Configuration()` reset
    /// `spatialTemplatePreference` to `.none`, which removed that template: the seat was still
    /// claimed (and shown) correctly, but the table never rotated toward it and every player
    /// kept looking at the master's seat. `applyShareState()` also runs after
    /// `coordinateWithSession` (the coordinator lookup in `configureSystemCoordinator` is async,
    /// and each presentation mode change calls it again).
    ///
    /// Only the window and immersive presentations override the preference (`.sideBySide`); the
    /// previous value is kept and restored when the table is presented again.
    func applyShareState() {
        guard let coordinator = systemCoordinator else { return }
        var configuration = coordinator.configuration
        configuration.supportsGroupImmersiveSpace = true
        switch gameModel?.shareState.mode ?? .window {
        case .tabletop:
            // Deliberately no `spatialTemplatePreference` override for the volumetric table (was
            // `.surround.contentExtent(1)`, then `.contentExtent(100)` — see git history): forcing
            // `.surround` made the table itself appear ~1.5 m above the floor, because it fought
            // `TabletopGame.coordinateWithSession(_:)`. Only undo our own window override.
            if let preference = spatialTemplatePreferenceBeforeWindowOverride {
                configuration.spatialTemplatePreference = preference
                spatialTemplatePreferenceBeforeWindowOverride = nil
            }
        case .window, .immersive:
            if spatialTemplatePreferenceBeforeWindowOverride == nil {
                spatialTemplatePreferenceBeforeWindowOverride = configuration.spatialTemplatePreference
            }
            configuration.spatialTemplatePreference = .sideBySide
        }
        coordinator.configuration = configuration
        Logger.sharePlay.debug("System coordinator configured for \(self.gameModel?.shareState.mode.rawValue ?? "window", privacy: .public): \(String(describing: configuration.spatialTemplatePreference), privacy: .public)")
    }
}

extension RPGSharePlayController {
    static let localParticipantSeatTaskKey = UUID()
    static let remoteParticipantSeatTaskKey = UUID()
}

#endif
