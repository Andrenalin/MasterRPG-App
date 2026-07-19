// @copyright André Trettin

import Observation

/// Owns the search query for a presentation while the currently displayed
/// sheet continues to own its filtered result tree.
///
/// Game windows keep one context alive while Adventure and Character sheets
/// attach their result model as they are presented. This keeps the search
/// field outside those sheets without duplicating their filtering logic.
@MainActor @Observable
public final class SheetSearchContext {
    public init(query: String = "") {
        self.query = query
    }

    public var query: String {
        didSet {
            guard query != oldValue else { return }
            activeResultModel?.searchText = query
        }
    }

    @ObservationIgnored private weak var activeResultModel: SheetRootModel?

    public func attachResults(_ model: SheetRootModel) {
        activeResultModel = model
        model.searchText = query
    }

    public func detachResults(_ model: SheetRootModel) {
        guard activeResultModel === model else { return }
        activeResultModel = nil
    }
}
