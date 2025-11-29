// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceHeader: View {
    let editController: EditController

    @Environment(DiceRootModel.self) private var root
    @Environment(DetailHeaderModel.self) private var headerModel

    @Namespace private var diceNamespace
    var body: some View {
        VStack {
            ScrollView(.horizontal) {
                DiceRoll(itemId: model.id)
                    .frame(height: headerModel.size.height + valueFor(iOS: 0, macOS: 0, tvOS: 0, visionOS: 32) - headerModel.topSafeAreaHeight, alignment: .bottom)
            }
            .padding(.horizontal, 8)
            .frame(width: diceWidth, height: headerModel.size.height + valueFor(iOS: 0, macOS: 0, tvOS: 0, visionOS: 32) - headerModel.topSafeAreaHeight, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, alignment: .center)
#if os(iOS)
        .toolbar {
            ToolbarItem {
                if headerModel.isInline == false {
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
        .padding(.top, valueFor(iOS: headerModel.topSafeAreaHeight / 2, macOS: 0, tvOS: headerModel.topSafeAreaHeight / 2, visionOS: headerModel.topSafeAreaHeight / 2))
        .frame(height: headerModel.size.height, alignment: .center)
    }
}

private extension DiceHeader {
    var model: DiceModel {
        editController.model
    }
    
    var diceWidth: CGFloat {
        let width = root.viewController.width(for: root.gameController.gameItem(for: model.id), maxWidth: headerModel.size.width - 82) + 64
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
        DiceHeader(editController: .preview)
            .environment(DiceRootModel.preview)
            .environment(DetailHeaderModel(size: CGSize(width: 375, height: 64), topSafeAreaHeight: 0, isInline: false))
            .border(.red)
        Spacer()
    }
    .ignoresSafeArea()
}
