// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct DiceDropDownMenuArea: View {
    let editController: any EditControllable
    let model: Binding<UUID?>
    
    @Environment(DiceRoot.self) private var root
    
    @State private var selectedId: UUID?
    @State private var dropBackgroundColor: Color = .clear
    @State private var dropForegroundColor: Color = .primary
    
    var body: some View {
        HStack(spacing: 8) {
            LabeledContent {
                Picker(selection: selection) {
                    ForEach(allDiceIds) { itemId in
                        Text(diceText(itemId: itemId))
                            .tag(itemId)
                    }
                } label: {
                    Text("Dice", bundle: .module)
                }
                .labelsHidden()
                .pickerStyle(.automatic)
                .tint(Color.accentColor)
            } label: {
                Text("Dice", bundle: .module)
            }
            .labelsHidden()
            
            if model.wrappedValue != nil {
                Button {
                    withAnimation {
                        model.wrappedValue = nil
                    }
                    editController.save(with: String(localized: "Remove dice").localizedString)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.white, .red)
                }
            }
        }
        .animation(.default, value: model.wrappedValue)
        .foregroundStyle(dropForegroundColor)
        .background {
            RoundedRectangle(cornerRadius: 8).fill(dropBackgroundColor)
        }
#if !os(tvOS)
        .dropDestination(for: LinkData.self) { items, _ in
            guard let draggedLinkData = items.first else { return false }
            return drop(link: draggedLinkData)
        } isTargeted: { inDropArea in
            dropBackgroundColor = inDropArea ? .accentColor : .clear
            dropForegroundColor = inDropArea ? .white : .primary
        }
#endif
    }
}

private extension DiceDropDownMenuArea {
    static let noneDiceId: UUID = UUID()
    static var emptyDice:  String {
        "None".localizedString
    }
    var noneDice: DiceModel {
        DiceModel(id: DiceDropDownMenuArea.noneDiceId, name: DiceDropDownMenuArea.emptyDice, description: "", tags: [], category: .character, dice: [])
    }
    
    var allDiceIds: [UUID] {
        [DiceDropDownMenuArea.noneDiceId] + root.itemController.itemDataModel.items
    }
    
    var selection: Binding<UUID> {
        Binding {
            model.wrappedValue ?? DiceDropDownMenuArea.noneDiceId
        } set: {
            if $0 == DiceDropDownMenuArea.noneDiceId {
                model.wrappedValue = nil
            } else {
                model.wrappedValue = $0
            }
            editController.save(with: String(localized: "Change dice").localizedString)
        }
    }

    func diceText(itemId: UUID) -> String {
        guard itemId != DiceDropDownMenuArea.noneDiceId else {
            return noneDice.name
        }
        
        let dice = root.itemController.itemOrEmpty(for: itemId)
        
        if dice.name.compare(dice.inlineText, options: .caseInsensitive, locale: .current) == .orderedSame {
            return dice.inlineText
        }
        return "\(dice.inlineText) - \(dice.name)"
    }
    
    func drop(link: LinkData) -> Bool {
        guard link.module == root.itemController.itemDataModel.networkModule else { return false }
        withAnimation {
            model.wrappedValue = link.itemId
        }
        editController.save(with: String(localized: "Change dice").localizedString)
        return true
    }

}
