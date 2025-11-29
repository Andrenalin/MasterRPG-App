// @copyright André Trettin

import Observation

@MainActor @Observable
public final class UndoManaged<T> {

    private(set) var value: T
    private var undoStack: [T] = []
    private var redoStack: [T] = []
    private(set) var undoTitles: [String] = []
    private(set) var redoTitles: [String] = []

    public init(initialValue: T) {
        self.value = initialValue
    }

    public func resetValue(_ value: T) {
        self.value = value
        undoStack.removeAll()
        redoStack.removeAll()
        undoTitles.removeAll()
        redoTitles.removeAll()
    }

    public func updateValue(_ value: T) {
        self.value = value
    }

    public func previousValue(_ prevValue: T, title: String) {
        undoStack.append(prevValue)
        undoTitles.append(title)
        guard !redoStack.isEmpty else { return }
        redoStack.removeAll()
    }

    public func undo() {
        if let newValue = undoStack.popLast() {
            let oldValue = value
            value = newValue
            redoStack.append(oldValue)
            if let title = undoTitles.popLast() {
                redoTitles.append(title)
            }
        }
    }

    public func redo() {
        if let newValue = redoStack.popLast() {
            let oldValue = value
            value = newValue
            undoStack.append(oldValue)
            if let title = redoTitles.popLast() {
                undoTitles.append(title)
            }
        }
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }
}
