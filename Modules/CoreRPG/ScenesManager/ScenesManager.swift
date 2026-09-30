//
//  ScenesManager.swift
//  ScenesManager
//
//  Created by Tom Krikorian and Tina Debove Nigro
//

import Foundation
import SwiftUI
import OSLog

/// A manager class that handles window and immersive space scenes in a visionOS app.
///
/// The `ScenesManager` provides centralized control over:
/// - Scene visibility tracking
/// - Window state management (opening, opened, closing, closed)
/// - Window and immersive space lifecycle
/// - Event suppression and handling
///
/// ## Scene States
/// Windows can transition through different states:
/// ```swift
/// // Check scene state
/// let state = scenesManager.getSceneState(for: .settings)
/// switch state {
/// case .opening:  // Scene is being opened
/// case .opened:   // Scene is active
/// case .closing:  // Scene is being dismissed
/// case .closed:   // Scene is not visible
/// }
/// ```
///
/// ## Scene Events
/// The manager supports suppressing different types of scene events:
/// - Opening events: Prevents windows from being opened
/// - Dismissal events: Prevents windows from being dismissed
///
/// ## Example Usage
/// ```swift
/// // Basic setup in your app
/// @Environment(\.scenesManager) var scenesManager
///
/// // Open a window
/// scenesManager.openWindow(.settings)
///
/// // Toggle immersive space
/// await scenesManager.toggleImmersiveSpace()
///
/// // Suppress both open and dismiss events
/// scenesManager.suppressEvents(for: .settings)
///
/// // Suppress specific events
/// scenesManager.suppressEvents([.openEvent, .dismissEvent], for: .settings)
///
/// // Remove suppression
/// scenesManager.unsuppressEvents(for: .settings)
/// ```
@MainActor @Observable public final class ScenesManager {
#if !os(tvOS)
    private var openWindow: OpenWindowAction?
    private var dismissWindow: DismissWindowAction?
#endif

#if os(macOS)
    private var openSettings: OpenSettingsAction?
#endif
    
#if os(visionOS)
    private var openImmersiveSpace: OpenImmersiveSpaceAction?
    private var dismissImmersiveSpace: DismissImmersiveSpaceAction?
    private var pendingSpaceViewerSelection: ItemSelection?

    /// Represents the current state of the immersive space.
    public enum ImmersiveSpaceState {
        /// The immersive space is not visible
        case closed
        /// The immersive space is currently transitioning between states
        case inTransition
        /// The immersive space is visible
        case open
    }
    
    /// The current state of the immersive space.
    public var immersiveSpaceState = ImmersiveSpaceState.closed
#endif
    
    /// Creates a new scenes manager instance.
    ///
    /// - Returns: A new `ScenesManager` instance configured for use in a visionOS app.
    public init() { }
    
#if !os(tvOS)
#if os(visionOS)
    /// Configures the environment actions used by the scenes manager.
    ///
    /// - Parameters:
    ///   - openWindow: The SwiftUI action to open windows
    ///   - dismissWindow: The SwiftUI action to dismiss windows
    ///   - openImmersiveSpace: The SwiftUI action to open immersive spaces
    ///   - dismissImmersiveSpace: The SwiftUI action to dismiss immersive spaces
    ///
    /// - Note: Call this method early in your app's lifecycle, typically in the main app scene.
    public func setActions(
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction,
        openImmersiveSpace: OpenImmersiveSpaceAction,
        dismissImmersiveSpace: DismissImmersiveSpaceAction
    ) {
        self.openWindow = openWindow
        self.dismissWindow = dismissWindow
        self.openImmersiveSpace = openImmersiveSpace
        self.dismissImmersiveSpace = dismissImmersiveSpace
    }
    
#else
    
    public func setActions(
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction
    ) {
        guard self.openWindow == nil else { return }
        self.openWindow = openWindow
        self.dismissWindow = dismissWindow
    }
    
    
#endif
#endif

#if os(macOS)
    /// Configures the SwiftUI action that presents the app's Settings scene.
    public func setOpenSettingsAction(_ openSettings: OpenSettingsAction) {
        self.openSettings = openSettings
    }

    /// Presents or brings forward the app's Settings scene.
    public func openSettingsWindow() {
        guard let openSettings else { return }
        openSettings()
    }
#endif
    
    /// Represents the current state of a window
    public enum SceneState {
        /// The window is in the process of opening
        case opening
        /// The window is open and active
        case opened
        /// The window is in the process of closing.
        case closing
        /// The window is closed but still being tracked
        case closed
    }
    
    /// Currently tracked scene states, automatically updated by scene trackers.
    private var sceneStates: [SceneId: SceneState] = [:]
    
    /// Gets the current state of a window.
    ///
    /// - Parameter scene: The scene identifier to check
    /// - Returns: The current `SceneState` of the scene, or `.closed` if not tracked
    public func getSceneState(for scene: SceneId) -> SceneState {
        sceneStates[scene] ?? .closed
    }
    
    /// Sets the state of a window.
    ///
    /// - Parameters:
    ///   - state: The new window state to set
    ///   - scene: The scene identifier to update
    public func setSceneState(_ state: SceneState, for scene: SceneId) {
        sceneStates[scene] = state
#if os(visionOS)
        guard scene == .spaceViewer else { return }
        switch state {
        case .opened, .opening:
            pendingSpaceViewerSelection = nil
        case .closed:
            resumePendingSpaceViewerIfNeeded()
        case .closing:
            break
        }
#endif
    }
    
    /// Opens a window with the specified scene identifier.
    ///
    /// - Parameter scene: The scene identifier for the window to open
    /// - Note: This method checks the current window state and handles transitions appropriately
    @MainActor
    public func openWindow(_ scene: SceneId) {
#if !os(tvOS)
        guard let openWindow = openWindow else { return }
        
        // Check if we can open this window
        if let state = sceneStates[scene] {
            switch state {
            case .closed, .closing:
                Logger.scenesManager.info("Opening window for scene \(scene.rawValue) with state opening")
                sceneStates[scene] = .opening
                openWindow(id: scene.rawValue)
            case .opening, .opened:
                Logger.scenesManager.info("Window for scene \(scene.rawValue) is already open or opening")
            }
        } else {
            Logger.scenesManager.info("First time tracking window for scene \(scene.rawValue) with state opening")
            sceneStates[scene] = .opening
            openWindow(id: scene.rawValue)
        }
#endif
    }

    /// Opens a window with the specified scene identifier.
    ///
    /// - Parameter scene: The scene identifier for the window to open
    /// - Note: This method checks the current window state and handles transitions appropriately
    @MainActor
    public func openWindow(_ scene: SceneId, selection: WindowItemSelection) {
#if !os(tvOS)
        guard let openWindow = openWindow else { return }
        
        // Check if we can open this window
        if let state = sceneStates[scene] {
            switch state {
            case .closed, .closing:
                Logger.scenesManager.info("Opening window for scene \(scene.rawValue) with state opening")
                sceneStates[scene] = .opening
                openWindow(id: scene.rawValue, value: selection)
            case .opening, .opened:
                Logger.scenesManager.info("Window for scene \(scene.rawValue) is already open or opening")
                // open new one:
                openWindow(id: scene.rawValue, value: selection)
            }
        } else {
            Logger.scenesManager.info("First time tracking window for scene \(scene.rawValue) with state opening")
            sceneStates[scene] = .opening
            openWindow(id: scene.rawValue, value: selection)
        }
#endif
    }

    
    /// Dismisses a window with the specified scene identifier.
    ///
    /// - Parameter scene: The scene identifier for the window to dismiss
    /// - Note: This method updates the window state to `.closing` before dismissal
    @MainActor
    public func dismissWindow(_ scene: SceneId, closed: Bool = false) {
#if !os(tvOS)
        guard let dismissWindow = dismissWindow else { return }
        Logger.scenesManager.info("Dismissing window for scene \(scene.rawValue) with state closing")
        sceneStates[scene] = .closing
        if closed {
            setSceneState(.closed, for: scene)
        } else {
            dismissWindow(id: scene.rawValue)
        }
#endif
    }
    
    
    @MainActor
    public func openWindow(for module: NetworkModules) -> Bool {
        let sceneId = module.sceneId
#if !os(tvOS)
        if getSceneState(for: sceneId) != .opened {
            openWindow(sceneId)
            return true
        }
#endif
        return false
    }

#if os(visionOS)
    /// Updates the global immersive-space lifecycle and resumes a Space reveal
    /// that arrived while the previous immersive space was closing.
    public func setImmersiveSpaceState(_ state: ImmersiveSpaceState) {
        immersiveSpaceState = state
        if state == .closed {
            resumePendingSpaceViewerIfNeeded()
        }
    }

    /// Opens the spaceViewer immersive space with the given item selection.
    @MainActor
    public func toggleSpaceViewer(selection: ItemSelection?) async {
        guard let dismissImmersiveSpace = dismissImmersiveSpace,
              let openImmersiveSpace = openImmersiveSpace else { return }

        switch immersiveSpaceState {
        case .open:
            pendingSpaceViewerSelection = nil
            currentSpaceViewerItemId = nil
            sceneStates[SceneId.spaceViewer] = .closing
            immersiveSpaceState = .inTransition
            await dismissImmersiveSpace()
        case .closed:
            sceneStates[SceneId.spaceViewer] = .opening
            immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: SceneId.spaceViewer.rawValue, value: selection ?? ItemSelection(itemId: UUID(), entryId: nil)) {
            case .opened:
                currentSpaceViewerItemId = selection?.itemId
            case .userCancelled, .error:
                Logger.scenesManager.error("Failed to open the Space viewer immersive space (SceneId.spaceViewer).")
                immersiveSpaceState = .closed
                sceneStates[SceneId.spaceViewer] = .closed
                currentSpaceViewerItemId = nil
            @unknown default:
                immersiveSpaceState = .closed
                sceneStates[SceneId.spaceViewer] = .closed
                currentSpaceViewerItemId = nil
            }
        case .inTransition:
            break
        }
    }

    /// The item currently displayed in the space-viewer immersive space, if
    /// any. Tracked separately from the `ImmersiveSpace`'s own `selection`
    /// value: SwiftUI hands that to the scene's content closure only on the
    /// *first* `openImmersiveSpace` call for a given scene id — a later call
    /// while it's already open doesn't redeliver a new value, so it can't be
    /// used to swap the displayed item. `WindowVisionList` reads this
    /// property instead (ahead of that frozen `selection`) to pick which item
    /// `SpaceViewer` shows, so updating it while already open — as
    /// `openSpaceViewer` does below — replaces the displayed object by
    /// changing the view identity SwiftUI recreates on.
    public private(set) var currentSpaceViewerItemId: UUID?

    /// Opens the spaceViewer immersive space with the given item selection.
    ///
    /// If the space is already open showing a *different* item, replaces it
    /// (see `currentSpaceViewerItemId`) rather than no-oping. If it's already
    /// open showing the *same* item, treats the call as a toggle and closes
    /// it — matches pressing an item's "view in space" control a second time.
    @MainActor
    public func openSpaceViewer(selection: ItemSelection) async {
        let state = getSceneState(for: .spaceViewer)
        if state == .opened {
            if currentSpaceViewerItemId == selection.itemId {
                await userDismissedSpaceViewer(itemId: selection.itemId)
            } else {
                explicitlyDismissedSpaceItemId = nil
                currentSpaceViewerItemId = selection.itemId
            }
            return
        }
        if state == .opening {
            pendingSpaceViewerSelection = selection
            return
        }
        guard state == .closed, immersiveSpaceState == .closed else {
            pendingSpaceViewerSelection = selection
            return
        }
        pendingSpaceViewerSelection = nil
        await toggleSpaceViewer(selection: selection)
    }

    /// Shows `selection` in the spaceViewer immersive space without ever
    /// closing it — opens the space, or replaces the displayed item, but is a
    /// no-op when that item is already shown.
    ///
    /// For programmatic callers (a GM reveal, SharePlay group immersion).
    /// `openSpaceViewer` treats a repeat call for the shown item as the user
    /// pressing "view in space" again and closes it, so a repeated reveal or a
    /// group-immersion re-activation closed the space without anyone asking.
    @MainActor
    public func showSpaceViewer(selection: ItemSelection) async {
        guard getSceneState(for: .spaceViewer) != .opened
                || currentSpaceViewerItemId != selection.itemId else { return }
        await openSpaceViewer(selection: selection)
    }

    /// Dismisses the spaceViewer immersive space if it is open or opening.
    @MainActor
    public func dismissSpaceViewer() async {
        pendingSpaceViewerSelection = nil
        guard let state = sceneStates[SceneId.spaceViewer], state == .opened || state == .opening else { return }
        await toggleSpaceViewer(selection: nil)
    }

    /// The item id a player explicitly dismissed via the space viewer's own
    /// close button, if any. `GameRootViewer`'s reveal-resync auto-open
    /// (`onChange(of: currentItemId)`) checks this so a resync of the *same*
    /// still-revealed item — a reconnect, another player joining, the GM's
    /// state re-broadcasting — doesn't pop the space back open on top of an
    /// explicit local dismiss. Cleared once the GM's reveal moves on (a
    /// different item, or un-revealing entirely), so a genuinely new reveal —
    /// even of the same item, after the GM clears and re-reveals it — still
    /// opens normally.
    public private(set) var explicitlyDismissedSpaceItemId: UUID?

    /// Dismisses the space viewer and marks `itemId` as explicitly dismissed
    /// by this player — see `explicitlyDismissedSpaceItemId`. Only the
    /// person tapping the in-space close button should call this.
    /// SharePlay/system-driven dismissals (e.g. the whole group leaving
    /// immersion together) should keep calling `dismissSpaceViewer()` plain:
    /// those aren't the player opting out of the GM's reveal.
    @MainActor
    public func userDismissedSpaceViewer(itemId: UUID) async {
        explicitlyDismissedSpaceItemId = itemId
        await dismissSpaceViewer()
    }

    /// Clears a prior explicit dismiss — call when the GM's reveal moves off
    /// the dismissed item (un-revealed, or a different item revealed), so a
    /// later re-reveal of that same item isn't permanently suppressed.
    public func clearExplicitlyDismissedSpaceItem() {
        explicitlyDismissedSpaceItemId = nil
    }

    private func resumePendingSpaceViewerIfNeeded() {
        guard pendingSpaceViewerSelection != nil else { return }
        Task { @MainActor [weak self] in
            guard let self, let selection = self.pendingSpaceViewerSelection else { return }
            await self.openSpaceViewer(selection: selection)
        }
    }
#endif
}

public extension ScenesManager.SceneState {
    /// Whether this state should read as "presented" to menu items that offer to open/close
    /// the scene — `.opening` counts as presented so the menu doesn't flicker to "open" and
    /// back while a window is still animating in.
    var isPresentedInGameMenu: Bool {
        switch self {
        case .opening, .opened:
            true
        case .closing, .closed:
            false
        }
    }
}
