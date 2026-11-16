// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

// The value types the dice options are made of: compare operator, coup / fumble triggers and reroll rules.
extension DiceModel {
    public enum CompareValue: Int, Identifiable, Equatable, Hashable, Codable, CaseIterable, Sendable {
        case off
        case lower
        case lowerEqual
        case equalHigher
        case higher

        public var id: Int {
            rawValue
        }

        var text: LocalizedStringKey {
            switch self {
            case .off:
                return "Off"
            case .lower:
                return "<"
            case .lowerEqual:
                return "<="
            case .equalHigher:
                return ">="
            case .higher:
                return ">"
            }
        }

        var rawText: String {
            switch self {
            case .off:
                return "Off"
            case .lower:
                return "<"
            case .lowerEqual:
                return "<="
            case .equalHigher:
                return ">="
            case .higher:
                return ">"
            }
        }

        var icon: String {
            switch self {
            case .off:
                return ""
            case .lower:
                return "lessthan.circle"
            case .lowerEqual:
                return "arrow.left.to.line.circle"
            case .equalHigher:
                return "arrow.right.to.line.circle"
            case .higher:
                return "greaterthan.circle"
            }
        }

        func check(value: Double, against other: Double) -> Bool {
            switch self {
            case .off:
                return false
            case .lower:
                return value < other
            case .lowerEqual:
                return value <= other
            case .equalHigher:
                return value >= other
            case .higher:
                return value > other
            }
        }
    }

    public enum CoupFumbleOption: Identifiable, Equatable, Hashable, Codable, RawRepresentable, Sendable {
        case result(Int)
        case diceValue(Int)

        public init?(rawValue: String) {
            guard rawValue.count > 1 else { return nil }
            let index = rawValue.index(after: rawValue.startIndex)
            let number = Int(rawValue[index...]) ?? 0
            if rawValue[rawValue.startIndex] == "r" {
                self = .result(number)
            } else if rawValue[rawValue.startIndex] == "d" {
                self = .diceValue(number)
            } else {
                return nil
            }
        }

        public var rawValue: String {
            switch self {
            case let .result(number):
                return "r\(number)"
            case let .diceValue(number):
                return "d\(number)"
            }
        }

        public var id: String {
            rawValue
        }

        var icon: String {
            switch self {
            case .diceValue:
                return NetworkModules.dice.icon
            case .result:
                return "123.rectangle"
            }
        }

        var text: String {
            switch self {
            case let .diceValue(number):
                return "\(number)"
            case let .result(number):
                return "\(number)"
            }
        }

        func isDiceValue(_ value: Int) -> Bool {
            switch self {
            case let .diceValue(number):
                return number == value
            case .result:
                return false
            }
        }

        func isResultValue(_ value: Int) -> Bool {
            switch self {
            case .diceValue:
                return false
            case let .result(number):
                return number == value
            }
        }

        var isResult: Bool {
            switch self {
            case .result:
                return true
            default:
                return false
            }
        }
    }

    public struct RerollOption: Identifiable, Equatable, Hashable, Codable, Sendable {
        public let number: Int
        public let value: Int
        public let maxDiceValue: Bool

        public var id: Int {
            number
        }
    }
}
