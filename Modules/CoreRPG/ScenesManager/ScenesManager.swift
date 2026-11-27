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
/// - Window and immersive space lifecycle (the Space viewer)
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
/// ## Example Usage
/// ```swift
/// // Basic setup in your app
/// @Environment(ScenesManager.self) var scenesManager
///
/// // Open and dismiss a window
/// scenesManager.openWindow(.settings)
/// scenesManager.dismissWindow(.settings)
///
/// // Show an item in the immersive Space viewer (visionOS)
/// await scenesManager.toggleSpaceViewer(selection: selection)
/// ```
@MainActor @Observable public final class ScenesManager {
#if !os(tvOS)
    // The environment actions are not state a view reads: tracking them invalidated every view
    // that reads the manager each time they were set. See CODE_AUDIT_29 §8.5.
    @ObservationIgnored private var openWindow: OpenWindowAction?
    @ObservationIgnored private var dismissWindow: DismissWindowAction?

    /// Asks SwiftUI to open or raise the window with this id. Set with the actions; tests set it
    /// directly.
    @ObservationIgnored var windowOpener: (@MainActor (String) -> Void)?
    /// The time source of the `.opening` timeout; tests replace it.
    @ObservationIgnored var now: @MainActor () -> ContinuousClock.Instant = { .now }
    /// When each scene was last asked to open.
    @ObservationIgnored private var openingSince: [SceneId: ContinuousClock.Instant] = [:]
    /// How long a scene may stay `.opening`. A scene that was never activated (the system
    /// refused the request, the app was in the background) would otherwise keep every later
    /// open call ignored. See CODE_AUDIT_28 §5.14.
    static let openingTimeout: Duration = .seconds(3)
#endif

#if os(macOS)
    @ObservationIgnored private var openSettings: OpenSettingsAction?
#endif
    
#if os(visionOS)
    @ObservationIgnored private var openImmersiveSpace: OpenImmersiveSpaceAction?
    @ObservationIgnored private var dismissImmersiveSpace: DismissImmersiveSpaceAction?
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
        // Not set once like the other platforms: the launch window closes itself after opening
        // the table, and the table window (`GameTableGameHost`) sets the actions of a live scene
        // again. Re-setting is cheap since the actions are not observed. See CODE_AUDIT_29 §8.5.
        self.openWindow = openWindow
        self.dismissWindow = dismissWindow
        windowOpener = { openWindow(id: $0) }
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
        windowOpener = { openWindow(id: $0) }
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
    /// The dictionary only maps a scene to its box and is filled on first
    /// use, also from a getter that a view body calls, so it is not observed
    /// itself; the boxes are.
    @ObservationIgnored private var sceneStateBoxes: [SceneId: SceneStateBox] = [:]

    private func sceneStateBox(for scene: SceneId) -> SceneStateBox {
        if let box = sceneStateBoxes[scene] {
            return box
        }
        let box = SceneStateBox()
        sceneStateBoxes[scene] = box
        return box
    }

    /// Writes a scene's state without the side effects of `setSceneState`,
    /// and without notifying observers when nothing changes.
    private func storeSceneState(_ state: SceneState, for scene: SceneId) {
        let box = sceneStateBox(for: scene)
        guard box.state != state else { return }
        box.state = state
    }
    
    /// The windows of each scene that are currently on screen, by tracker token. The viewer scenes
    /// are multi-instance (`openWindow(_:selection:)` opens a further window when one is open), so
    /// the scene is `.opened` while at least one window is active and only `.closed` when the last
    /// one is gone. See CODE_AUDIT_26 §5.12.
    @ObservationIgnored private var activeWindows: [SceneId: Set<UUID>] = [:]

    /// A window of `scene` became active.
    public func windowBecameActive(_ token: UUID, for scene: SceneId) {
        activeWindows[scene, default: []].insert(token)
        setSceneState(.opened, for: scene)
    }

    /// A window of `scene` went away (disappeared or moved to the background).
    /// - Returns: `true` when it was the last window, so the scene is now `.closed`.
    @discardableResult
    public func windowEnded(_ token: UUID, for scene: SceneId) -> Bool {
        activeWindows[scene]?.remove(token)
        if activeWindows[scene]?.isEmpty ?? true {
            activeWindows[scene] = nil
            setSceneState(.closed, for: scene)
            return true
        }
        // Another window is still open: a state set to `.closing` by an earlier dismissal of the
        // scene no longer describes it.
        storeSceneState(.opened, for: scene)
        return false
    }

    /// The number of windows of `scene` that are active.
    public func activeWindowCount(for scene: SceneId) -> Int {
        activeWindows[scene]?.count ?? 0
    }

    /// Gets the current state of a window.
    ///
    /// - Parameter scene: The scene identifier to check
    /// - Returns: The current `SceneState` of the scene, or `.closed` if not tracked
    public func getSceneState(for scene: SceneId) -> SceneState {
        sceneStateBox(for: scene).state
    }
    
    /// Sets the state of a window.
    ///
    /// - Parameters:
    ///   - state: The new window state to set
    ///   - scene: The scene identifier to update
    public func setSceneState(_ state: SceneState, for scene: SceneId) {
        storeSceneState(state, for: scene)
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
        guard let windowOpener else { return }

        switch getSceneState(for: scene) {
        case .closed, .closing:
            Logger.scenesManager.info("Opening window for scene \(scene.rawValue) with state opening")
            requestOpen(scene, with: windowOpener)
        case .opening:
            // Only a second call in the same turn is ignored; a scene that has been opening for
            // too long never came up and is asked again.
            if let since = openingSince[scene], now() - since < Self.openingTimeout {
                Logger.scenesManager.info("Window for scene \(scene.rawValue) is already opening")
            } else {
                Logger.scenesManager.info("Window for scene \(scene.rawValue) did not open in time, asking again")
                requestOpen(scene, with: windowOpener)
            }
        case .opened:
            // The window may be behind others: asking SwiftUI again brings it to the front.
            Logger.scenesManager.info("Raising window for scene \(scene.rawValue)")
            windowOpener(scene.rawValue)
        }
#endif
    }

#if !os(tvOS)
    private func requestOpen(_ scene: SceneId, with opener: @MainActor (String) -> Void) {
        storeSceneState(.opening, for: scene)
        openingSince[scene] = now()
        opener(scene.rawValue)
    }
#endif

    /// Opens a window with the specified scene identifier.
    ///
    /// - Parameter scene: The scene identifier for the window to open
    /// - Note: This method checks the current window state and handles transitions appropriately
    @MainActor
    public func openWindow(_ scene: SceneId, selection: WindowItemSelection) {
#if !os(tvOS)
        guard let openWindow = openWindow else { return }
        
        // Check if we can open this window
        switch getSceneState(for: scene) {
        case .closed, .closing:
            Logger.scenesManager.info("Opening window for scene \(scene.rawValue) with state opening")
            storeSceneState(.opening, for: scene)
            openWindow(id: scene.rawValue, value: selection)
        case .opening, .opened:
            Logger.scenesManager.info("Window for scene \(scene.rawValue) is already open or opening")
            // open new one:
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
        storeSceneState(.closing, for: scene)
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
            storeSceneState(.closing, for: .spaceViewer)
            immersiveSpaceState = .inTransition
            await dismissImmersiveSpace()
        case .closed:
            storeSceneState(.opening, for: .spaceViewer)
            immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: SceneId.spaceViewer.rawValue, value: selection ?? ItemSelection(itemId: UUID(), entryId: nil)) {
            case .opened:
                currentSpaceViewerItemId = selection?.itemId
            case .userCancelled, .error:
                Logger.scenesManager.error("Failed to open the Space viewer immersive space (SceneId.spaceViewer).")
                immersiveSpaceState = .closed
                storeSceneState(.closed, for: .spaceViewer)
                currentSpaceViewerItemId = nil
            @unknown default:
                immersiveSpaceState = .closed
                storeSceneState(.closed, for: .spaceViewer)
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
        let state = getSceneState(for: .spaceViewer)
        guard state == .opened || state == .opening else { return }
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

/// The state of one scene, observable on its own.
///
/// All states used to live in one observed dictionary, so a change to any
/// scene invalidated every view that had read the state of any other —
/// opening one window re-rendered every window button of the app.
@MainActor @Observable
private final class SceneStateBox {
    var state: ScenesManager.SceneState = .closed
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
