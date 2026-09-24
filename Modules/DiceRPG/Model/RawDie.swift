// @copyright André Trettin

import CoreRPG

public struct RawDie: Equatable, Hashable, Codable, Sendable {
    // MARK: - static

    public static func roll(_ sides: Sides) -> Int {
        Int.random(in: 1 ... sides.number())
    }

    public static func rollPercent() -> Double {
        Double.random(in: 0 ... 100)
    }

    public static var two: RawDie {
        RawDie(.two)
    }

    public static var three: RawDie {
        RawDie(.three)
    }

    public static var four: RawDie {
        RawDie(.four)
    }

    public static var six: RawDie {
        RawDie(.six)
    }

    public static var eight: RawDie {
        RawDie(.eight)
    }

    public static var ten: RawDie {
        RawDie(.ten)
    }

    public static var twelve: RawDie {
        RawDie(.twelve)
    }

    public static var twenty: RawDie {
        RawDie(.twenty)
    }

    // MARK: - init

    public let sides: Sides

    public init(_ sides: Sides = .twenty) {
        self.sides = sides
    }

    public init(text: String) {
        let pattern = "(?<Die>d)(?<Sides>[0-9]+)"
        let results = RegularExpressionParser.parse(text, with: pattern, extract: ["Sides"])
        if results.count == 1, let number = Int(results[0]) {
            sides = Sides.sides(number)
        } else {
            sides = .twenty
        }
    }

    public func roll() -> Int {
        Self.roll(sides)
    }

    public var min: Int {
        1
    }

    public var max: Int {
        sides.number()
    }

    public var text: String {
        "d\(sides.number())"
    }

    public var colorCodes: [DieModel.ColorCode] {
        switch sides {
        case .two: [.G]
        case .three: [.A, .B, .G]
        case .four: [.A, .B, .C, .G]
        case .six: [.A, .B, .G]
        case .eight: [.A, .B, .G]
        case .ten: [.A, .B, .G]
        case .twelve: [.A, .B, .C, .G]
        case .twenty: [.A, .B, .C, .D, .G]
        case .number: [.G]
        }
    }

    public enum Sides: Equatable, Hashable, Codable, Sendable {
        case two
        case three
        case four
        case six
        case eight
        case ten
        case twelve
        case twenty
        case number(Int)

        func number() -> Int {
            switch self {
            case .two:
                return 2
            case .three:
                return 3
            case .four:
                return 4
            case .six:
                return 6
            case .eight:
                return 8
            case .ten:
                return 10
            case .twelve:
                return 12
            case .twenty:
                return 20
            case let .number(sides):
                // `sides == 1` is a valid "always rolls 1" die (a common
                // guaranteed-minimum mechanic in imported game systems) — only
                // clamp genuinely invalid (≤0) values up. Previously any
                // `sides < 2` was doubled to a coin flip, silently turning a
                // deterministic "d1" into a 50% chance of rolling 2. See
                // CODE_AUDIT_9 §5.3.
                if sides < 1 {
                    return 2
                }
                return sides
            }
        }

        static func sides(_ number: Int) -> Sides {
            switch number {
            case 2:
                return .two
            case 3:
                return .three
            case 4:
                return .four
            case 6:
                return .six
            case 8:
                return .eight
            case 10:
                return .ten
            case 12:
                return .twelve
            case 20:
                return .twenty
            default:
                return .number(number)
            }
        }
    }
}
