// @copyright André Trettin

import Foundation
import Observation

@MainActor @Observable
public final class BattleRoundSettingsModel: Sendable {
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        initiativeName = defaults.string(forKey: Keys.initiativeName) ?? "Ini"
        hitPointsName = defaults.string(forKey: Keys.hitPointsName) ?? "HP"
        if defaults.object(forKey: Keys.initiativeOrder) != nil {
            initiativeOrder = BattleInitiativeOrder(
                rawValue: defaults.integer(forKey: Keys.initiativeOrder)
            ) ?? .descending
        } else {
            initiativeOrder = .descending
        }
    }

    public var initiativeName: String {
        didSet {
            defaults.set(
                initiativeName.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Keys.initiativeName
            )
        }
    }

    public var hitPointsName: String {
        didSet {
            defaults.set(
                hitPointsName.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Keys.hitPointsName
            )
        }
    }

    public var initiativeOrder: BattleInitiativeOrder {
        didSet {
            defaults.set(initiativeOrder.rawValue, forKey: Keys.initiativeOrder)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let initiativeName = "battleRound.initiativeName"
        static let hitPointsName = "battleRound.hitPointsName"
        static let initiativeOrder = "battleRound.initiativeOrder"
    }
}
