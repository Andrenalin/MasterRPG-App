// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GeneratorInline: View {
    init(root: TableRootModel, item: Binding<ItemRowModel?>) {
        self._item = item
        self._generatorController = State(wrappedValue: root.generatorController(rootItem: item.wrappedValue))
    }
    
    @State private var generatorController: GeneratorController
    @Binding var item: ItemRowModel?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeneratorRoot(generatorController: generatorController, item: $item)
            .transition(.move(edge: .bottom))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(.spring(), value: item?.itemId ?? UUID())
    }

    private var color: Color {
#if os(macOS)
        Color(nsColor: NSColor.windowBackgroundColor)
#elseif !os(tvOS)
        Color(uiColor: UIColor.systemBackground)
#else
        Color(uiColor: UIColor.black)
#endif
    }
}

struct GeneratorWindow: View {
    @MainActor
    init(root: TableRootModel) {
        self.root = root
        self._generatorController = State(wrappedValue: root.rootModel.generatorController)
        self._item = State(wrappedValue: ItemRowModel(itemId: UUID(), typeId: .table))
    }
    let root: TableRootModel
    
#if os(macOS)
    @Environment(\.dismissWindow) private var dismissWindow
#endif
    @State private var generatorController: GeneratorController?
    @State private var item: ItemRowModel?
    
    var body: some View {
        Group {
            if let generatorController {
                GeneratorRoot(generatorController: generatorController, item: $item)
                    .onChange(of: root.rootModel.generatorItemId, initial: true) {
                        self.generatorController = root.rootModel.generatorController
                    }
                    .onChange(of: item) {
                        if item == nil {
#if os(macOS)
                            dismissWindow()
#endif
                        }
                    }
            } else {
                Text("Loading ...")
                    .onChange(of: root.rootModel.generatorItemId, initial: true) {
                        self.generatorController = root.rootModel.generatorController
                    }
                    .onAppear {
#if os(macOS)
                        dismissWindow()
#endif
                    }
            }
        }
    }
}
