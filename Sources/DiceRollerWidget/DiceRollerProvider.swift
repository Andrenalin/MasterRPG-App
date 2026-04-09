// @copyright André Trettin

import DiceRPG
import WidgetKit
import SwiftUI
import CoreRPG

/// Timeline provider for the dice roller widget
struct DiceRollerProvider: TimelineProvider {
    
    func placeholder(in context: Context) -> DiceRollerEntry {
        DiceRollerEntry(
            date: Date(),
            selectedDice: .d20,
            lastRoll: nil,
            configuration: .default
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (DiceRollerEntry) -> Void) {
        let entry = DiceRollerEntry(
            date: Date(),
            selectedDice: .d20,
            lastRoll: DiceRollResult(value: 15, diceType: .d20, timestamp: Date()),
            configuration: .default
        )
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<DiceRollerEntry>) -> Void) {
        // Fetch user's preferred dice configuration
        let configuration = DiceConfiguration.loadFromUserDefaults()
        
        // Create entry with current state
        let entry = DiceRollerEntry(
            date: Date(),
            selectedDice: configuration.selectedDice,
            lastRoll: configuration.lastRoll,
            configuration: configuration
        )
        
        // Update timeline every 15 minutes to stay fresh
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
        completion(timeline)
    }
}

// MARK: - Entry Model

struct DiceRollerEntry: TimelineEntry {
    let date: Date
    let selectedDice: DiceType
    let lastRoll: DiceRollResult?
    let configuration: DiceConfiguration
    
    static var preview: DiceRollerEntry {
        DiceRollerEntry(
            date: Date(),
            selectedDice: .d20,
            lastRoll: DiceRollResult(value: 18, diceType: .d20, timestamp: Date()),
            configuration: .default
        )
    }
}

// MARK: - Dice Configuration

struct DiceConfiguration: Codable {
    var selectedDice: DiceType
    var lastRoll: DiceRollResult?
    var availableDice: [DiceType]
    var showHistory: Bool
    
    static var `default`: DiceConfiguration {
        DiceConfiguration(
            selectedDice: .d20,
            lastRoll: nil,
            availableDice: DiceType.allCases,
            showHistory: true
        )
    }
    
    static func loadFromUserDefaults() -> DiceConfiguration {
        guard let data = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")?.data(forKey: "diceConfiguration"),
              let config = try? JSONDecoder().decode(DiceConfiguration.self, from: data) else {
            return .default
        }
        return config
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")?.set(data, forKey: "diceConfiguration")
        }
    }
}

// MARK: - Dice Type

enum DiceType: String, Codable, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case d4 = "D4"
    case d6 = "D6"
    case d8 = "D8"
    case d10 = "D10"
    case d12 = "D12"
    case d20 = "D20"
    case d100 = "D100"
    
    var id: String { rawValue }
    
    var sides: Int {
        switch self {
        case .d4: return 4
        case .d6: return 6
        case .d8: return 8
        case .d10: return 10
        case .d12: return 12
        case .d20: return 20
        case .d100: return 100
        }
    }

    var rawDie: RawDie {
        switch self {
        case .d4: return RawDie.four
        case .d6: return RawDie.six
        case .d8: return RawDie.eight
        case .d10: return RawDie.ten
        case .d12: return RawDie.twelve
        case .d20: return RawDie.twenty
        case .d100: return RawDie(.number(100))
        }
    }
    
    var die: DieModel {
        DieModel(id: UUID(), die: rawDie)
    }
    
    func dieImage(result: Int) -> Image {
        die.diceImage(for: result).resizable()
    }
    
    var dieImage: Image {
        die.diceImage(for: die.die.max).resizable()
    }
            
    func roll() -> Int {
        let die = DieModel(id: UUID(), die: RawDie(.number(sides)))
        return die.die.role()
    }
}

// MARK: - Dice Roll Result

struct DiceRollResult: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let value: Int
    let diceType: DiceType
    let timestamp: Date
    
    init(id: UUID = UUID(), value: Int, diceType: DiceType, timestamp: Date) {
        self.id = id
        self.value = value
        self.diceType = diceType
        self.timestamp = timestamp
    }
    
    var isCritical: Bool {
        value == diceType.sides
    }
    
    var isCriticalFailure: Bool {
        value == 1
    }
}
