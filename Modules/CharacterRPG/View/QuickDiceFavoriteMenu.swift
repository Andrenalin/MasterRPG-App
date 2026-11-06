// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Puts an entry's dice into one of the player's quick dice slots. The slot then follows the
/// entry's value. Offered next to the dice of the player's own character sheet only, while a
/// player plays.
struct QuickDiceFavoriteMenu: View {
    let itemId: UUID
    let entryId: UUID

    @Environment(\.quickDiceSlots) private var quickDiceSlots
    @Environment(\.isSheetEditor) private var isSheetEditor
    @Environment(\.sheetRootItemId) private var sheetRootItemId
    @Environment(AppGameStateModel.self) private var appGameStateModel

    var body: some View {
        // The player's game screen keeps `isOfferedNow` by the one Quick Dice rule, so an observer
        // gets no favorites either. See CODE_AUDIT_Since_3.0.1 §9.14.
        if let quickDiceSlots, !isSheetEditor, appGameStateModel.isGameRunning, quickDiceSlots.isOfferedNow,
           let characterId = quickDiceSlots.characterId, sheetRootItemId == characterId {
            let currentIndex = quickDiceSlots.index(forItem: itemId, entry: entryId)
            Menu {
                ForEach(0..<QuickDiceSlotsModel.slotCount, id: \.self) { index in
                    Button {
                        quickDiceSlots.assign(QuickDiceSlot(source: .entry(itemId: itemId, entryId: entryId)), to: index)
                    } label: {
                        if currentIndex == index {
                            Label {
                                Text("Slot \(index + 1)", bundle: .module)
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                        } else {
                            Text("Slot \(index + 1)", bundle: .module)
                        }
                    }
                }
                if let currentIndex {
                    Divider()
                    Button(role: .destructive) {
                        quickDiceSlots.clear(currentIndex)
                    } label: {
                        Label {
                            Text("Remove from Quick Dice", bundle: .module)
                        } icon: {
                            Image(systemName: "star.slash")
                        }
                    }
                }
            } label: {
                Label {
                    Text("Add to Quick Dice", bundle: .module)
                } icon: {
                    Image(systemName: currentIndex == nil ? "star" : "star.fill")
                        .contentTransition(.symbolEffect(.replace.wholeSymbol))
                }
                .labelStyle(.iconOnly)
            }
#if !os(tvOS)
            .menuStyle(.button)
#endif
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
#if os(visionOS)
            .contentShape(.hoverEffect, .circle)
#endif
            .help(Text("Add to Quick Dice", bundle: .module))
        }
    }
}

#Preview {
    let slots = QuickDiceSlotsModel(store: UserDefaultsQuickDiceSlotStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
    slots.load(characterId: ValueModel.previewId)
    slots.isOfferedNow = true
    return QuickDiceFavoriteMenu(itemId: ValueModel.previewId, entryId: UUID())
        .environment(\.quickDiceSlots, slots)
        .environment(\.sheetRootItemId, ValueModel.previewId)
        .environment(AppGameStateModel())
}
