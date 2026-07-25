// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

/// The visible sheet publishes this context so iPhone can host one sheet-wide
/// Ask AI control in the native tab accessory.
public struct SheetAIAssistantContext: Equatable {
    public init(module: NetworkModules, itemId: UUID, rootModel: SheetRootModel) {
        self.module = module
        self.itemId = itemId
        self.rootModel = rootModel
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let rootModel: SheetRootModel

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.module == rhs.module
            && lhs.itemId == rhs.itemId
            && lhs.rootModel === rhs.rootModel
    }
}

public struct SheetAIAssistantContextPreferenceKey: PreferenceKey {
    public static var defaultValue: [SheetAIAssistantContext] { [] }

    public static func reduce(
        value: inout [SheetAIAssistantContext],
        nextValue: () -> [SheetAIAssistantContext]
    ) {
        value.append(contentsOf: nextValue())
    }
}

public extension View {
    func sheetAIAssistantContext(
        module: NetworkModules,
        itemId: UUID,
        rootModel: SheetRootModel?
    ) -> some View {
        preference(
            key: SheetAIAssistantContextPreferenceKey.self,
            value: rootModel.map {
                [SheetAIAssistantContext(module: module, itemId: itemId, rootModel: $0)]
            } ?? []
        )
    }
}

/// Content supplied to `SheetRootView` when its assistant configuration is enabled.
///
/// The sheet owns this content's placement. iPhone publishes one control to the
/// native tab accessory; larger platforms render one control at the root's bottom edge.
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
