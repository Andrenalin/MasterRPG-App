// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

/// The visible sheet publishes this lightweight context to the owning TabView.
/// On iPhone that lets SwiftUI place Ask AI in the native tab-bar accessory.
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

/// Places the assistant in the phone tab accessory, while larger screens keep its
/// compact icon on the bottom trailing edge of the active editor.
public extension View {
    func sheetAIAssistantPlacement(
        module: NetworkModules,
        itemId: UUID,
        rootModel: SheetRootModel?
    ) -> some View {
        modifier(
            SheetAIAssistantPlacementModifier(
                module: module,
                itemId: itemId,
                rootModel: rootModel
            )
        )
    }
}

private struct SheetAIAssistantPlacementModifier: ViewModifier {
    let module: NetworkModules
    let itemId: UUID
    let rootModel: SheetRootModel?

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    func body(content: Content) -> some View {
#if os(iOS)
        content
            .sheetAIAssistantContext(
                module: module,
                itemId: itemId,
                rootModel: SheetAIGenerationController.isAvailable ? rootModel : nil
            )
            .applyIf(appSizeModel.mode == .regular && rootModel != nil && SheetAIGenerationController.isAvailable) {
                $0.safeAreaInset(edge: .bottom, alignment: .trailing) {
                    assistant
                }
            }
#elseif !os(tvOS)
        content
            .applyIf(rootModel != nil && SheetAIGenerationController.isAvailable) {
                $0.safeAreaInset(edge: .bottom, alignment: .trailing) {
                    assistant
                }
            }
#else
        content
#endif
    }

    @ViewBuilder private var assistant: some View {
        if let rootModel {
            GlassEffectContainerAll {
                SheetAIAssistantOverlayView(module: module, itemId: itemId, rootModel: rootModel)
            }
        }
    }
}
#endif
