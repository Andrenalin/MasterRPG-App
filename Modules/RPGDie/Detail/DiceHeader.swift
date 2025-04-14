// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct DiceHeader: View {
    let editController: EditController
    let size: CGSize
    let topMargin: CGFloat
    let inline: Bool
    
    @Environment(DiceRoot.self) private var root

    @Namespace private var diceNamespace
    var body: some View {
        VStack {
            ScrollView(.horizontal) {
                DiceRoll(itemId: model.id)
                    .frame(height: size.height + valueFor(iOS: 0, macOS: 0, tvOS: 0, visionOS: 32) - topMargin, alignment: .bottom)
            }
            .padding(.horizontal, 8)
            .frame(width: diceWidth, height: size.height + valueFor(iOS: 0, macOS: 0, tvOS: 0, visionOS: 32) - topMargin, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, alignment: .center)
#if os(iOS)
        .toolbar {
            ToolbarItem {
                if inline == false {
                    mainToolbarButton
                }
            }
        }
#else
        .overlay(alignment: .topTrailing) {
            mainToolbarButton
                .padding(.trailing, valueFor(iOS: 16, macOS: 16, tvOS: 16, visionOS: 24))
        }
#endif
        .padding(.top, valueFor(iOS: topMargin / 2, macOS: 0, tvOS: topMargin / 2, visionOS: topMargin / 2))
        .frame(height: size.height, alignment: .center)
    }
}

private extension DiceHeader {
    var model: DiceModel {
        editController.model
    }
    
    var diceWidth: CGFloat {
        let width = root.viewController.width(for: root.gameController.gameItem(for: model.id), maxWidth: size.width - 82) + 64
        return max(width, 32)
    }
    
    func resultColor(for dieId: UUID) -> [Bool] {
        let result = root.gameController.diceSuccess(for: model.id)
        guard let colors = result.first(where: { $0.0 == dieId }) else { return [] }
        return colors.1
    }
    
    func roll() {
        withAnimation {
            root.gameController.rollDice(itemId: model.id, networkActions: nil)
        }
    }
    
    private var mainToolbarButton: some View {
        ImageOverlayButton(icon: root.itemController.itemDataModel.networkModule.icon) {
            roll()
        }
    }
}

#Preview {
    VStack {
        DiceHeader(editController: .preview, size: CGSize(width: 380, height: 100), topMargin: 64, inline: false)
            .environment(DiceRoot.preview)
            .border(.red)
        Spacer()
    }
    .ignoresSafeArea()
}
