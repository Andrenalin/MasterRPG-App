// @copyright André Trettin

import CoreRPG
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    static let previewId = UUID()
    static let previewId2 = UUID()
    static let previewId3 = UUID()
        
    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(modelContext: context.mainContext))
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try! ModelContainer(
            for: DiceDataModel.self, TagDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        guard try! container.mainContext.fetch(FetchDescriptor<DiceDataModel>()).isEmpty else {
            return container
        }
        
        let die1 = DieDataModel(id: UUID(), index: 0, die: .ten)
        let die2 = DieDataModel(id: UUID(), index: 1, die: .ten)
        let config = DiceConfigDataModel(itemId: previewId, sumUp: false, modifier: 0, percentDice: true, compareOption: .lowerEqual, compareValue: 60, coupValues: [.result(1)], coupOnlyOnFirstDie: false, fumbleValues: [.result(100)], fumbleOnlyOnFirstDie: false, rerollOptions: [], reorderDice: false, addDiceEvery: 0, dice: [die1, die2])
        let model1 = DiceDataModel(
            id: previewId,
            name: "Mega Nice Photo",
            information: "A lot of information about this photo",
            category: .adventure,
            tags: ["Example", "Title", "Ouside"],
        )
        container.mainContext.insert(model1)
        container.mainContext.insert(config)


        let die3 = DieDataModel(id: UUID(), index: 0, die: .six)
        let die4 = DieDataModel(id: UUID(), index: 1, die: .six)
        let config2 = DiceConfigDataModel(itemId: previewId2, sumUp: true, modifier: 0, percentDice: false, compareOption: .equalHigher, compareValue: 6, coupValues: [.diceValue(6)], coupOnlyOnFirstDie: false, fumbleValues: [.diceValue(1)], fumbleOnlyOnFirstDie: false, rerollOptions: [], reorderDice: false, addDiceEvery: 0, dice: [die3, die4])
        let model2 = DiceDataModel(
            id: previewId2,
            name: "Albert",
            information: "The is an example photo and the information is also set here",
            category: .character,
            tags: ["Player", "Mega", "Gnome"]
        )
        container.mainContext.insert(model2)
        container.mainContext.insert(config2)

        let die5 = DieDataModel(id: UUID(), index: 0, die: .twenty, color: "A")
        let config3 = DiceConfigDataModel(itemId: previewId3, sumUp: true, modifier: 0, percentDice: false, compareOption: .lowerEqual, compareValue: 32, coupValues: [.diceValue(1)], coupOnlyOnFirstDie: false, fumbleValues: [.diceValue(20)], fumbleOnlyOnFirstDie: true, rerollOptions: [.init(number: 1, value: 1, maxDiceValue: true)], reorderDice: true, addDiceEvery: 20, dice: [die5])
        let model3 = DiceDataModel(
            id: previewId3,
            name: "Zauberer",
            information: "A photo of a wizard.",
            category: .adventure,
            tags: ["NPC", "Wizward", "Schwarzmagier"]
        )
        container.mainContext.insert(model3)
        container.mainContext.insert(config3)

        return container
    }
}

struct MockRootViewModifier: ViewModifier {
    init(modelContext: ModelContext) {
        self._root = State(wrappedValue: DiceRootModel(modelContext: modelContext))
    }
    
    @State private var root: DiceRootModel

    func body(content: Content) -> some View {
        content.environment(root)
            .environment(root.searchModel)
            .environment(root.listController.listModel)
            .environment(root.listDisplayModel)
            .environment(CacheItemListModel())
            .environment(DeviceRotationModel())
            .environment(TabTitleModel())
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
