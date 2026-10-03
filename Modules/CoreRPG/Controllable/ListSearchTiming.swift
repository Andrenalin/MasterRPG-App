// @copyright André Trettin

import Foundation

/// Shared named durations for `FolderListControllable`'s search/refresh pacing — a plain
/// namespace rather than protocol-extension `static` members, since those aren't reachable
/// through a protocol's own metatype (`any FolderListControllable.Type`), only through a
/// concrete conformer. Also reused directly by `GameRPG`'s `SearchGlobalController`, which
/// needs the same typing-debounce value without duplicating it. See CODE_AUDIT §9.14.
public enum ListSearchTiming {
    /// Applies while typing a non-empty query — long enough that a fast typist's keystrokes
    /// collapse into one search instead of one-per-keystroke.
    public static let typingDebounce: Duration = .milliseconds(300)

    /// Short coalescing window for every non-debounced search/refresh trigger — just long
    /// enough that a burst of near-simultaneous triggers settles into a single call rather
    /// than one per trigger.
    public static let coalesceWindow: Duration = .milliseconds(50)

    /// Gives the list one render pass to finish laying out a newly-added row before
    /// selecting it, rather than selecting an id the list hasn't rendered yet.
    public static let selectionRestoreRenderDelay: Duration = .milliseconds(50)

}
