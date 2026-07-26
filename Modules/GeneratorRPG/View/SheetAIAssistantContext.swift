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

    /// Attaches one sheet assistant to the bottom of its parent screen.
    func sheetAIAssistant(
        module: NetworkModules,
        itemId: UUID,
        rootModel: SheetRootModel?
    ) -> some View {
        overlay(alignment: .bottomTrailing) {
            if let rootModel {
                SheetAIAssistantContent(
                    module: module,
                    itemId: itemId,
                    rootModel: rootModel
                )
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }
}

/// The one assistant presentation attached to a parent detail or game screen.
///
/// iPhone publishes one control to the native tab accessory; larger platforms
/// render one control at the parent screen's bottom edge.
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
            
            // For now deactivated the tabbar view
//#if os(iOS)
//            if SheetAIGenerationController.usesPhoneTabAccessory {
//                Color.clear
//                    .frame(width: 0, height: 0)
//                    .accessibilityHidden(true)
//                    .sheetAIAssistantContext(
//                        module: module,
//                        itemId: itemId,
//                        rootModel: rootModel
//                    )
//            } else {
//                standardAssistant
//            }
//#else
//            standardAssistant
//#endif
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
