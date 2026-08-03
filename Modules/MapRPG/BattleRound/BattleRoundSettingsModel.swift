// @copyright André Trettin

import Foundation
import Observation
import SwiftUI

@MainActor @Observable
public final class BattleRoundSettingsModel: Sendable {
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        initiativeNames = defaults.stringArray(forKey: Keys.initiativeNames) ?? ["Ini"]
        hitPointsNames = defaults.stringArray(forKey: Keys.hitPointsNames) ?? ["HP"]
        if defaults.object(forKey: Keys.initiativeOrder) != nil {
            initiativeOrder = BattleInitiativeOrder(
                rawValue: defaults.integer(forKey: Keys.initiativeOrder)
            ) ?? .descending
        } else {
            initiativeOrder = .descending
        }
    }

    /// Name aliases matched when auto-detecting a Character's initiative
    /// value at battle start, e.g. `["Ini", "Initiative"]`.
    public var initiativeNames: [String] {
        didSet {
            defaults.set(initiativeNames, forKey: Keys.initiativeNames)
        }
    }

    /// Name aliases matched when auto-detecting a Character's hit-points
    /// value at battle start, e.g. `["HP", "HitPoints"]`.
    public var hitPointsNames: [String] {
        didSet {
            defaults.set(hitPointsNames, forKey: Keys.hitPointsNames)
        }
    }

    public var initiativeOrder: BattleInitiativeOrder {
        didSet {
            defaults.set(initiativeOrder.rawValue, forKey: Keys.initiativeOrder)
        }
    }

    public func names(for kind: BattleValueKind) -> [String] {
        switch kind {
        case .initiative: initiativeNames
        case .hitPoints: hitPointsNames
        }
    }

    /// Adds a trimmed alias, skipping empty or case-insensitive duplicates.
    @discardableResult
    public func addName(_ name: String, for kind: BattleValueKind) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !names(for: kind).contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return false
        }
        switch kind {
        case .initiative: initiativeNames.append(trimmed)
        case .hitPoints: hitPointsNames.append(trimmed)
        }
        return true
    }

    public func removeName(_ name: String, for kind: BattleValueKind) {
        switch kind {
        case .initiative: initiativeNames.removeAll { $0 == name }
        case .hitPoints: hitPointsNames.removeAll { $0 == name }
        }
    }

    public func removeNames(at offsets: IndexSet, for kind: BattleValueKind) {
        switch kind {
        case .initiative: initiativeNames.remove(atOffsets: offsets)
        case .hitPoints: hitPointsNames.remove(atOffsets: offsets)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let initiativeNames = "battleRound.initiativeNames"
        static let hitPointsNames = "battleRound.hitPointsNames"
        static let initiativeOrder = "battleRound.initiativeOrder"
    }
}
