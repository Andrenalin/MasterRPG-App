// @copyright André Trettin

#if os(visionOS)

import ARKit
import Combine
import os.log
import SwiftUI

/// A model that contains up-to-date hand coordinate information.
@MainActor @Observable
public final class DiceHandTrackingGestureModel {
    public init(diceRoot: DiceRootModel) {
        self.root = diceRoot
    }

    let root: DiceRootModel
    let session = ARKitSession()
    var handTracking = HandTrackingProvider()
    var latestHandTracking: HandsUpdates = .init(left: nil, right: nil)
    /// Set when the user revokes Hand Tracking permission mid-session (e.g. via Control
    /// Center or Settings). `DiceSpace` observes this to pause the hand-gesture flow and
    /// prompt the user to re-grant access. See CODE_AUDIT §5.21.
    var handTrackingAuthorizationRevoked = false

    struct HandsUpdates {
        var left: HandAnchor?
        var right: HandAnchor?
    }

    func start() async {
        do {
            if HandTrackingProvider.isSupported {
                #if DEBUG
                print("ARKitSession starting.")
                #endif
                try await session.run([handTracking])
            }
            let planeData = PlaneDetectionProvider(alignments: [.horizontal])
            if PlaneDetectionProvider.isSupported {
                try await session.run([planeData])
                for await update in planeData.anchorUpdates {
                    guard update.anchor.surfaceClassification == .table else { continue }
                    #if DEBUG
                    print(update.description)
                    #endif
                    switch update.event {
                    case .added, .updated:
                        root.diceSpaceModel.updatePlane(update.anchor)
                    case .removed:
                        root.diceSpaceModel.removePlane(update.anchor)
                    }
                }
            }
        } catch {
            Logger.diceSpace.error("ARKitSession error: \(error.localizedDescription, privacy: .public)")
        }
    }

    func publishHandTrackingUpdates() async {
        for await update in handTracking.anchorUpdates {
            switch update.event {
            case .updated:
                let anchor = update.anchor

                // Publish updates only if the hand and the relevant joints are tracked.
                guard anchor.isTracked else { continue }

                // Update left hand info.
                if anchor.chirality == .left {
                    latestHandTracking.left = anchor
                } else if anchor.chirality == .right { // Update right hand info.
                    latestHandTracking.right = anchor
                }
            default:
                break
            }
        }
    }

    func monitorSessionEvents() async {
        for await event in session.events {
            switch event {
            case .authorizationChanged(let type, let status):
                if type == .handTracking && status != .allowed {
                    // Actually stop tracking work rather than let the session keep running
                    // against now-revoked permission; `DiceSpace` observes the flag below to
                    // pause the hand-gesture flow and prompt the user to re-grant access in
                    // Settings. See CODE_AUDIT §5.21.
                    session.stop()
                    handTrackingAuthorizationRevoked = true
                }
            default:
                #if DEBUG
                print("Session event \(event)")
                #endif
            }
        }
    }

}

#endif
