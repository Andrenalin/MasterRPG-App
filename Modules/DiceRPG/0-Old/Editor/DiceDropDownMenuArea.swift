// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceDropDownMenuArea: View {
    init(editController: any EditControllable, model: Binding<UUID?>) {
        self.editController = editController
        self.model = model
        self._selectedId = .init(initialValue: model.wrappedValue ?? DiceDropDownMenuArea.noneDiceId)
    }
    
    let editController: any EditControllable
    let model: Binding<UUID?>
    
    @Environment(DiceRootModel.self) private var root
    
    @State private var selectedId: UUID
    @State private var dropBackgroundColor: Color = .clear
    @State private var dropForegroundColor: Color = .primary
    
    var body: some View {
        HStack(spacing: 8) {
            LabeledContent {
                Picker(selection: $selectedId) {
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
            .onChange(of: selectedId) {
                selectDice(id: selectedId)
            }
            .onChange(of: model, initial: true) {
                let newSelectedId: UUID
                if let id = model.wrappedValue {
                    newSelectedId = id
                } else {
                    newSelectedId = DiceDropDownMenuArea.noneDiceId
                }
                guard newSelectedId != newSelectedId else { return }
                withAnimation { selectedId = newSelectedId }
            }
            
            if model.wrappedValue != nil {
                Button {
                    withAnimation {
                        selectedId = DiceDropDownMenuArea.noneDiceId
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

    func selectDice(id: UUID) {
        let newId: UUID?
        if id == DiceDropDownMenuArea.noneDiceId {
            newId = nil
        } else {
            newId = id
        }
        if newId != model.wrappedValue {
            model.wrappedValue = newId
            editController.save(with: String(localized: "Change dice").localizedString)
        }
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
