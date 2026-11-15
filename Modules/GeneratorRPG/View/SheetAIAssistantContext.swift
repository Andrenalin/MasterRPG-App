// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI
import FoundationModels

public extension View {
    func sheetAIAssistant(
        generatorRoot: GeneratorRootModel?,
        rootModel: SheetRootModel?,
        module: NetworkModules
    ) -> some View {
        safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
            Color.clear
                .frame(height: 80)
                .allowsHitTesting(false)
        }
        .overlayPreferenceValue(
            ItemHeaderEditorPresentedPreferenceKey.self,
            alignment: .bottomTrailing
        ) { isHeaderEditorPresented in
            SheetAIAssistantPlacement(
                generatorRoot: generatorRoot,
                rootModel: rootModel,
                isHidden: isHeaderEditorPresented
            )
        }
    }
}

/// The Ask AI control of a screen, if the screen's item can use it.
///
/// A view of its own, so the observable reads are tracked by a `body`: the preference closure
/// that builds it is not one.
private struct SheetAIAssistantPlacement: View {
    let generatorRoot: GeneratorRootModel?
    let rootModel: SheetRootModel?
    let isHidden: Bool

    var body: some View {
        if let rootModel,
           GeneratorRootModel.isAssistantModelAvailable,
           let generatorController = generatorRoot?.generatorController(forItem: rootModel.sheetModel.source.itemId),
           generatorController.availability {
            SheetAIAssistantContent(generatorController: generatorController, rootModel: rootModel)
                .padding(.horizontal)
                .padding(.bottom)
                // Hidden rather than removed while the header editor covers the screen:
                // removing it would end the AI session and recreate the glass node.
                .opacity(isHidden ? 0 : 1)
                .allowsHitTesting(!isHidden)
                .accessibilityHidden(isHidden)
        }
    }
}

/// The one assistant presentation attached to a parent detail or game screen.
///
/// iPhone publishes one control to the native tab accessory; larger platforms
/// render one control at the parent screen's bottom edge.
struct SheetAIAssistantContent: View {
    let generatorController: GeneratorController
    let rootModel: SheetRootModel

    var body: some View {
        GlassEffectContainerAll {
            SheetAIAssistantOverlayView(
                generatorController: generatorController,
                rootModel: rootModel
            )
        }
    }
}
#endif
