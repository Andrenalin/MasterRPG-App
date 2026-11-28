// @copyright André Trettin

import Observation

/// An undo and a redo stack of steps. A step describes a change on its own (for an item edit:
/// the values before and after it), so moving between the stacks never rewrites a step: undo
/// moves the step to the redo stack and redo moves it back. A whole-item snapshot with a
/// current `value` (the earlier design) reverted every later change on undo.
/// See CODE_AUDIT_Edit_Save §5.2, §5.6.
@MainActor @Observable
public final class UndoManaged<Step> {
    private struct Entry {
        let step: Step
        let title: String
    }

    private var undoStack: [Entry] = []
    private var redoStack: [Entry] = []

    public init() {}

    /// The number of undo steps kept. Older ones are dropped.
    public static var maxDepth: Int { 100 }

    /// Records a new step. The redo stack is dropped: it continued a history that no longer is.
    public func record(_ step: Step, title: String) {
        undoStack.append(Entry(step: step, title: title))
        // Every step holds copies of the edited models; keep only the newest ones.
        // See CODE_AUDIT §7.5.
        if undoStack.count > Self.maxDepth {
            undoStack.removeFirst(undoStack.count - Self.maxDepth)
        }
        redoStack.removeAll()
    }

    /// Replaces the newest undo step, for a step that grows while one user action runs.
    public func replaceLast(with step: Step) {
        guard let last = undoStack.popLast() else { return }
        undoStack.append(Entry(step: step, title: last.title))
    }

    /// Moves the newest undo step to the redo stack and returns it for the caller to revert.
    public func undo() -> Step? {
        guard let entry = undoStack.popLast() else { return nil }
        redoStack.append(entry)
        if redoStack.count > Self.maxDepth {
            redoStack.removeFirst(redoStack.count - Self.maxDepth)
        }
        return entry.step
    }

    /// Moves the newest redo step back to the undo stack and returns it for the caller to apply.
    public func redo() -> Step? {
        guard let entry = redoStack.popLast() else { return nil }
        undoStack.append(entry)
        return entry.step
    }

    /// Drops every step.
    public func removeAll() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Drops the steps `shouldRemove` names, from both stacks.
    public func removeAll(where shouldRemove: (Step) -> Bool) {
        undoStack.removeAll { shouldRemove($0.step) }
        redoStack.removeAll { shouldRemove($0.step) }
    }

    /// Rewrites every step, dropping those `transform` maps to `nil`.
    public func compactMapSteps(_ transform: (Step) -> Step?) {
        undoStack = undoStack.compactMap { entry in transform(entry.step).map { Entry(step: $0, title: entry.title) } }
        redoStack = redoStack.compactMap { entry in transform(entry.step).map { Entry(step: $0, title: entry.title) } }
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// The step the next `undo()` returns.
    public var nextUndoStep: Step? { undoStack.last?.step }

    /// The step the next `redo()` returns.
    public var nextRedoStep: Step? { redoStack.last?.step }

    public var undoTitles: [String] { undoStack.map(\.title) }
    public var redoTitles: [String] { redoStack.map(\.title) }

    public var undoDepth: Int { undoStack.count }
}
