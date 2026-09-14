// @copyright André Trettin

import SwiftUI

struct ItemGenerationPresentationModifier: ViewModifier {
    let root: any ItemRootControllable
    @Binding var selection: WindowItemSelection?

    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(
                \.itemGenerationAction,
                ItemGenerationAction(
                    id: .module(root.configurable.module),
                    isEnabled: root.generationControllable != nil,
                    present: present(itemId:)
                )
            )
            .overlay {
                if let selection, let generator = root.generationControllable {
                    generator.generationView(
                        itemId: selection.itemId,
                        dismissAction: dismiss
                    )
                    // Forces SwiftUI to tear down and rebuild the generation
                    // panel (and its `@State` session model) whenever the
                    // selected item changes, instead of preserving the
                    // previous item's view identity — without this, jumping
                    // from one item's panel directly to another's (bypassing
                    // `nil`) would keep editing/saving the first item's
                    // session under the second item's visible `itemId`.
                    // See CODE_AUDIT §5.1.
                    .id(selection.itemId)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
                }
            }
    }

    @MainActor
    private func present(itemId: UUID) {
#if os(macOS) || os(visionOS)
        scenesManager.openWindow(
            .tableGenerator,
            selection: WindowItemSelection(itemId: itemId)
        )
#elseif os(iOS)
        withAnimation(reduceMotion ? nil : .smooth) {
            selection = WindowItemSelection(itemId: itemId)
        }
#endif
    }

    @MainActor
    private func dismiss() {
        withAnimation(reduceMotion ? nil : .smooth) {
            selection = nil
        }
    }
}

extension View {
    func itemGenerationPresentation(
        root: any ItemRootControllable,
        selection: Binding<WindowItemSelection?>
    ) -> some View {
        modifier(
            ItemGenerationPresentationModifier(
                root: root,
                selection: selection
            )
        )
    }
}
