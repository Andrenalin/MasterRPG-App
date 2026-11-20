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

    /// The number of undo steps kept. Older ones are dropped.
    public static var maxDepth: Int { 100 }

    public func updateValue(_ value: T) {
        self.value = value
    }

    public func previousValue(_ prevValue: T, title: String) {
        undoStack.append(prevValue)
        undoTitles.append(title)
        // Every entry is a full copy of the edited model; keep only the newest ones.
        // See CODE_AUDIT §7.5.
        if undoStack.count > Self.maxDepth {
            let overflow = undoStack.count - Self.maxDepth
            undoStack.removeFirst(overflow)
            undoTitles.removeFirst(min(overflow, undoTitles.count))
        }
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

    /// The value the next `undo()` restores.
    public var nextUndoValue: T? {
        undoStack.last
    }

    /// The value the next `redo()` restores.
    public var nextRedoValue: T? {
        redoStack.last
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    public var undoDepth: Int {
        undoTitles.count
    }
}
