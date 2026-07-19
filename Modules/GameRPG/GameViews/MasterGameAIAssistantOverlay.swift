// @copyright André Trettin

#if !os(tvOS)
import AdventureRPG
import CoreRPG
import Foundation
import GeneratorRPG
import SwiftUI

/// A window-level AI surface for the game master. It deliberately remains a
/// sibling of the game surface so opening it never participates in map layout.
struct MasterGameAIAssistantOverlay: View {
    let root: GameRoot
    let adventureId: UUID

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var sheetRootModel: SheetRootModel?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let sheetRootModel {
                if sheetRootModel.isAIModeActive {
                    MasterGameAIAssistantPanel(
                        root: root,
                        adventureId: adventureId,
                        sheetRootModel: sheetRootModel
                    )
                    .frame(width: gameScreenModel.sideBarWidth)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    SheetAIAssistantOverlayView(
                        module: .adventure,
                        itemId: adventureId,
                        rootModel: sheetRootModel
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.top, topInset)
        .padding(.trailing, trailingInset)
        .padding(.bottom, bottomInset)
        .animation(
            accessibilityReduceMotion ? nil : .smooth,
            value: sheetRootModel?.isAIModeActive
        )
        .task(id: adventureId) {
            prepareSheetModel()
        }
        .onDisappear {
            sheetRootModel?.setAIModeActive(false)
        }
    }

    private var topInset: CGFloat {
#if os(iOS)
        gameScreenModel.topGameMenuHeight + GameScreenModel.mapOverlaySpacing
#else
        sheetRootModel?.isAIModeActive == true ? 0 : 8
#endif
    }

    private var bottomInset: CGFloat {
        sheetRootModel?.isAIModeActive == true ? 0 : 8
    }

    private var trailingInset: CGFloat {
#if os(macOS)
        // Leave the vertical module menu fully visible and tappable.
        64 + gameScreenModel.mapTrailingViewportReservation
#else
        8 + gameScreenModel.mapTrailingViewportReservation
#endif
    }

    private func prepareSheetModel() {
        if let sheetRootModel {
            sheetRootModel.reset(itemId: adventureId)
            return
        }

        guard let rootManager = root.adventureRoot.rootManager else { return }
        sheetRootModel = SheetRootModel(
            rootManager: rootManager,
            linkControllable: root.adventureRoot.linkControllable,
            sheetControllable: root.adventureRoot.sheetControllable,
            itemId: adventureId,
            isEditor: true
        )
    }
}

private struct MasterGameAIAssistantPanel: View {
    let root: GameRoot
    let adventureId: UUID
    let sheetRootModel: SheetRootModel

    var body: some View {
        SheetRootView(
            root: root.adventureRoot.rootController,
            rootModel: sheetRootModel,
            isEditor: true,
            linkTypes: EmptyLinkTransferable.self
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            SheetAIAssistantOverlayView(
                module: .adventure,
                itemId: adventureId,
                rootModel: sheetRootModel
            )
        }
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .shadow(radius: 8)
    }
}

#Preview(traits: .mockData) {
    let root = GameRoot.previewFixture()
    MasterGameAIAssistantOverlay(
        root: root,
        adventureId: GamePreviewData.adventureID
    )
    .environment(GameScreenModel())
}
#endif
