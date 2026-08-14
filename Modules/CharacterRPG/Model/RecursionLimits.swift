// @copyright André Trettin

/// Shared depth guards against circular value-group/link references
/// (e.g. a nested value entry that links back to an ancestor).
///
/// Used by `GameController.gameEntry` and `LinkController.calculate`, which both walk
/// entry → linked-value chains that could otherwise recurse indefinitely on malformed data.
enum RecursionLimits {
    static let maxValueLinkDepth = 10
}
