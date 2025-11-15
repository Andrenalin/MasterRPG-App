// @copyright André Trettin

import AndrenalinKit
import RoleGameKit
import RPGDie
import SwiftUI
import WidgetKit
import _AppIntents_SwiftUI

struct DiceWidgetProvider: AppIntentTimelineProvider {
    init(sharedDataBase: DataBaseLoader) {
        self.sharedDataBase = sharedDataBase
    }
    
    private let sharedDataBase: DataBaseLoader

    @MainActor
    private func root() async -> DiceRoot {
        await sharedDataBase.setup()
        let dbloadRoot = sharedDataBase.appModel.diceRoot
        return dbloadRoot
    }
    
    func placeholder(in context: Context) -> DiceWidgetIntentEntry {
        DiceWidgetIntentEntry(date: Date(), configuration: SelectedDiceAppIntent(), selectedDice: nil)
    }

    func snapshot(for configuration: SelectedDiceAppIntent, in context: Context) async -> DiceWidgetIntentEntry {
        let dice = await getDice(itemId: configuration.selectedDice?.id)
        return DiceWidgetIntentEntry(date: Date(), configuration: configuration, selectedDice: dice)
    }
    
    func timeline(for configuration: SelectedDiceAppIntent, in context: Context) async -> Timeline<DiceWidgetIntentEntry> {
        let currentDate = Date.now
        let selectedDice = await getDice(itemId: configuration.selectedDice?.id)
        let entry = DiceWidgetIntentEntry(date: currentDate, configuration: configuration, selectedDice: selectedDice)
        return Timeline(entries: [entry], policy: .atEnd)
    }
    
    @MainActor func getDice(itemId: String?) async -> DiceWidgetModel? {
        await widgetEntity(for: itemId)
    }
    
    @MainActor
    func widgetEntity(for idString: String?) async -> DiceWidgetModel? {
        let root = await root()
        return await root.widgetEntity(for: idString)
    }
}

struct DiceWidgetIntentEntry: TimelineEntry {
    let date: Date
    let configuration: SelectedDiceAppIntent
    let selectedDice: DiceWidgetModel?
}

struct DiceWidgetEntryView : View {
    var entry: DiceWidgetProvider.Entry

    var body: some View {
        Group {
            if let selectedDice = entry.selectedDice, let diceRoot = DataBaseLoader.shared.diceRoot {
                Link(destination: selectedDice.link()) {
                    ZStack {
                        Color.clear
                        
                        VStack {
                            Button(intent: RollDiceAppIntent(name: selectedDice.name)) {
                                diceRoot.viewController.viewCompactDice(itemId: selectedDice.itemId)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Select dice", systemImage: "dice")
            }
        }
    }
}

struct DiceWidget: Widget {
    let kind: String = "DiceWidget"
    
    let sharedDataBase = DataBaseLoader.shared

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectedDiceAppIntent.self, provider: DiceWidgetProvider(sharedDataBase: sharedDataBase)) { entry in
            DiceWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Dice")
        .description("Roll dice")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    DiceWidget()
} timeline: {
    DiceWidgetIntentEntry(date: .now, configuration: SelectedDiceAppIntent(), selectedDice: DiceWidgetModel(itemId: UUID(), name: "DS", displayName: "D20", root: .preview))
}
