// @copyright André Trettin

import CoreRPG

public struct RawDie: Equatable, Hashable, Codable, Sendable {
    // MARK: - static

    public static func role(_ sides: Sides) -> Int {
        Int.random(in: 1 ... sides.number())
    }

    public static func rolePercent() -> Double {
        Double.random(in: 0 ... 100)
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

    public func role() -> Int {
        Int.random(in: 1 ... sides.number())
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

    public enum Sides: Equatable, Hashable, Codable, Sendable {
        case four
        case six
        case eight
        case ten
        case twelve
        case twenty
        case number(Int)

        func number() -> Int {
            switch self {
            case .four: 4
            case .six: 6
            case .eight: 8
            case .ten: 10
            case .twelve: 12
            case .twenty: 20
            case let .number(sides): sides < 2 ? 2 : sides
            }
        }

        static func sides(_ number: Int) -> Sides {
            switch number {
            case 4: .four
            case 6: .six
            case 8: .eight
            case 10: .ten
            case 12: .twelve
            case 20: .twenty
            default: .number(number)
            }
        }
    }
}
