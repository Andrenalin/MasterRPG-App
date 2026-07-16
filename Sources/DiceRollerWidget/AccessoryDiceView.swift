// @copyright André Trettin

#if os(iOS)
import DiceRPG
import SwiftUI
import WidgetKit

struct AccessoryDiceView: View {
    @Environment(\.widgetFamily) var family
    let entry: DiceRollerEntry
    private let previewFamily: WidgetFamily?

    init(entry: DiceRollerEntry, previewFamily: WidgetFamily? = nil) {
        self.entry = entry
        self.previewFamily = previewFamily
    }
    
    var body: some View {
        switch previewFamily ?? family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 2) {
                    if let lastRoll = entry.snapshot.lastRoll {
                        Image(systemName: diceSymbol(for: lastRoll.dice.sides))
                            .font(.title3)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: "\(entry.snapshot.lastRoll?.sum ?? 0)")
                        .font(.caption)
                        .bold()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(
                    verbatim: entry.snapshot.lastRoll?.dice.name
                        ?? String(localized: "No rolls yet", bundle: .main)
                )
            )
            .accessibilityValue(Text(verbatim: "\(entry.snapshot.lastRoll?.sum ?? 0)"))
            
        case .accessoryRectangular:
            HStack(spacing: 8) {
                if let lastRoll = entry.snapshot.lastRoll {
                    Image(systemName: diceSymbol(for: lastRoll.dice.sides))
                        .font(.title3)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: lastRoll.dice.name)
                            .font(.headline)
                        Text(verbatim: "\(lastRoll.sum)")
                            .font(.title3)
                            .bold()
                    }
                } else {
                    Image(systemName: "dice.fill")
                        .accessibilityHidden(true)
                    Text("No rolls yet", bundle: .main)
                        .font(.caption)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)
            
        case .accessoryInline:
            if let lastRoll = entry.snapshot.lastRoll {
                Text("🎲 \(lastRoll.dice.name): \(lastRoll.sum)", bundle: .main)
            } else {
                Text("🎲 Tap to roll", bundle: .main)
            }
            
        default:
            EmptyView()
        }
    }
    
    private func diceSymbol(for sides: Int) -> String {
        switch sides {
        case 4: return "triangle.fill"
        case 6: return "square.fill"
        case 8: return "diamond.fill"
        case 10: return "pentagon.fill"
        case 12: return "hexagon.fill"
        case 20: return "circle.hexagonpath.fill"
        default: return "die.face.\(min(sides, 6)).fill"
        }
    }
}

#Preview("Accessory dice view") {
    AccessoryDiceView(entry: .preview, previewFamily: .accessoryRectangular)
        .containerBackground(for: .widget) { }
}
#endif
