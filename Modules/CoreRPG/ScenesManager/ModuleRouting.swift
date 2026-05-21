// @copyright André Trettin

import Foundation
import SwiftUI

/// Ensures the window that owns `module`'s UI is on screen, and returns its `SceneId`.
///
/// Routes are window-scoped: each window has its own root `Navigator`, and performing a route
/// on a Navigator whose stack hasn't mounted yet drops the route on the floor. Callers must
/// therefore always pair the returned `SceneId` with `appModel.navigator(for: sceneId)` —
/// looking up the navigator before the window opens would yield the wrong (or stale) one.
///
/// Behavior by platform:
/// - macOS / visionOS: opens the owning window via `ScenesManager` if it's not `.opened`.
/// - iOS / iPadOS / tvOS: no-op — the single window always owns every module.
///
/// - Returns: The `SceneId` of the window that hosts `module`.

@MainActor
public func openWindowForModule(
    scenesManager: ScenesManager,
    module: NetworkModules
) -> SceneId {
    let sceneId = module.sceneId
#if os(macOS) || os(visionOS)
    if scenesManager.getSceneState(for: sceneId) != .opened {
        scenesManager.openWindow(sceneId)
    }
#endif
    return sceneId
}
