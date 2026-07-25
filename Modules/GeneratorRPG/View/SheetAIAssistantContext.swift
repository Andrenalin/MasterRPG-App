// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

/// Content supplied to `SheetRootView` when its assistant configuration is enabled.
///
/// The sheet owns this content's placement and renders the expandable control once
/// at its bottom edge.
public struct SheetAIAssistantContent: View {
    public init(
        module: NetworkModules,
        itemId: UUID,
        rootModel: SheetRootModel
    ) {
        self.module = module
        self.itemId = itemId
        self.rootModel = rootModel
    }

    let module: NetworkModules
    let itemId: UUID
    let rootModel: SheetRootModel

    public var body: some View {
        if SheetAIGenerationController.isAvailable {
            standardAssistant
        }
    }

    private var standardAssistant: some View {
        GlassEffectContainerAll {
            SheetAIAssistantOverlayView(
                module: module,
                itemId: itemId,
                rootModel: rootModel
            )
        }
    }
}
#endif
