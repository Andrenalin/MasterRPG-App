// @copyright André Trettin

import SwiftUI

private struct SupporterTierEnvironmentKey: EnvironmentKey {
    static let defaultValue: SupporterTier = .none
}

public extension EnvironmentValues {
    var supporterTier: SupporterTier {
        get { self[SupporterTierEnvironmentKey.self] }
        set { self[SupporterTierEnvironmentKey.self] = newValue }
    }
}
