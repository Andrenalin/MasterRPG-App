// @copyright André Trettin

import CoreRPG
import Foundation

/// Everything `GameToolBar` needs from whatever is currently rendering the
/// map — the 2D canvas (`MapEditorSession`) or GameRPG's 3D table
/// (`GameTableModel`) — so the exact same toolbar component, buttons, and
/// button actions work unmodified for both. Public because the 3D table
/// lives in a separate module and conforms to this from there.
@MainActor
public protocol GameToolBarSession: AnyObject, Observable {
    var currentMapId: UUID? { get }
    /// The room the game master currently has zoomed/focused — where a newly
    /// added monster pin should land.
    var focusedRoomId: UUID? { get }

    /// Whether toolbar-driven edits (pointer moves, added pins) are pushed to
    /// every connected client as they happen, versus staying local until the
    /// next explicit push. "Refresh Shared Map" always sends regardless.
    var isStreaming: Bool { get set }
    /// Whether the shared pointer is currently active/visible.
    var isPointing: Bool { get set }

    var displayMode: MapDisplayMode { get set }

    var pinScale: CGFloat { get set }
    var hexScale: Double { get set }
    /// Applies `hexScale` to the map: the hex grid is rebuilt for it. Called once when the
    /// scale slider is released, not for every value on the way. See CODE_AUDIT_21 §5.19.
    func commitHexScale()
    var isHexMap: Bool { get }
    var canReshare: Bool { get }
    func resetReshare()
    /// Toggles the hex overlay grid, generating or clearing its entries.
    func toggleHexMap()

    /// Pushes whatever the toolbar just changed (a pointer move, an added
    /// pin) to every connected client.
    func sendMapUpdates()
}

public extension MapDisplayMode {
    /// Cycles master → player → reader → master, matching the shared
    /// toolbar's display-mode button.
    func toggled() -> MapDisplayMode {
        switch self {
        case .master: .player
        case .player: .reader
        case .reader: .master
        }
    }

    /// SF Symbol for the shared toolbar's display-mode button.
    var toolBarIcon: String {
        switch self {
        case .master: "rectangle.3.offgrid.fill"
        case .player: "rectangle.lefthalf.inset.filled"
        case .reader: "rectangle.3.offgrid"
        }
    }
}

extension MapEditorSession: GameToolBarSession {
    var currentMapId: UUID? { mapId }

    var focusedRoomId: UUID? {
        focusId ?? entries.entries.first(where: \.focused)?.id
    }

    func toggleHexMap() {
        route(.toggleHexGrid)
    }

    func commitHexScale() {
        hexScaleCommit &+= 1
    }

    func sendMapUpdates() {
        actions.sendMapUpdates?()
    }
}
