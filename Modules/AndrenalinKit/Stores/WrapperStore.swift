// @copyright André Trettin

import Combine
import SwiftUI

public final class WrapperStore<Store>: ObservableObject {
    public init(store: Store) {
        self.store = store
    }

    public let store: Store
}

@propertyWrapper
public final class NotObserving<Wrapped: ObservableObject>: ObservableObject {
    public var wrappedValue: Wrapped

    public init(wrappedValue: Wrapped) {
        self.wrappedValue = wrappedValue
    }
}
