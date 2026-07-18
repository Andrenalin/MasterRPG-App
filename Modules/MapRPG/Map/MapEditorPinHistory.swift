// @copyright André Trettin

import Observation

/// Working-copy history for pin mutations. Pin gestures update only their
/// stable node while interacting, then record one array snapshot at commit.
/// Keeping this history beside the editor session avoids replacing every pin
/// during a drag and keeps Save/Cancel semantics unchanged.
@MainActor @Observable
final class MapEditorPinHistory {
    init(pins: [MapPinModel]) {
        current = pins
    }

    private(set) var current: [MapPinModel]
    private var undoStack: [[MapPinModel]] = []
    private var redoStack: [[MapPinModel]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func reset(to pins: [MapPinModel]) {
        current = pins
        undoStack.removeAll(keepingCapacity: true)
        redoStack.removeAll(keepingCapacity: true)
    }

    @discardableResult
    func record(_ pins: [MapPinModel]) -> Bool {
        guard pins != current else { return false }
        undoStack.append(current)
        current = pins
        redoStack.removeAll(keepingCapacity: true)
        return true
    }

    func undo() -> [MapPinModel]? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        current = previous
        return previous
    }

    func redo() -> [MapPinModel]? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        current = next
        return next
    }
}
