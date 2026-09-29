// @copyright André Trettin

#if os(visionOS)
import AudioRPG
import AVFoundation
import CoreRPG
import Combine
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
        
        let immersionTask = Task { [weak self] in
            for await immersionStyle in coordinator.groupImmersionStyle {
                guard let self,
                      !Task.isCancelled,
                      self.sessionLifecycle.isCurrent(sessionId: sessionId),
                      self.groupSession?.id == sessionId
                else { return }
                self.gameModel?.shareState.groupImmersionActive = immersionStyle != nil
            }
        }
        tasks[UUID()] = immersionTask
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

    func applyShareState() {
        guard let coordinator = systemCoordinator else { return }
        var configuration = SystemCoordinator.Configuration()
        configuration.supportsGroupImmersiveSpace = true
        switch gameModel?.shareState.mode ?? .window {
        case .tabletop:
            // Deliberately no `spatialTemplatePreference` override here (was
            // `.surround.contentExtent(1)`, then `.contentExtent(100)` before
            // that — see git history). `spatialTemplatePreference` only
            // controls where the system arranges participants' spatial
            // Personas, but forcing `.surround` for the volumetric table
            // window made the *table itself* appear ~1.5 m above the floor
            // for every participant instead of at the same table height it
            // renders at without SharePlay — `GameRenderer`'s own
            // `placeTable(volumeBounds:)` never changes between the two, so
            // the difference was this override fighting `TabletopGame
            // .coordinateWithSession(_:)` (`setup(tabletopGame:)` below),
            // which is TabletopKit's own documented hook for coordinating a
            // table with a group session. Apple's TabletopKit SharePlay
            // sample sets no `spatialTemplatePreference` at all and relies
            // on `coordinateWithSession` alone — leaving this unset here
            // does the same, and still lets TabletopKit seat participants
            // around the table on its own.
            break
        case .window, .immersive:
            configuration.spatialTemplatePreference = .sideBySide
        }
        coordinator.configuration = configuration
    }
}

#endif
