// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftUI

@Observable
final class ChangeGeneratorModel {
    internal init(showGenerator: Bool = false, generatorId: UUID? = nil, itemId: UUID? = nil) {
        self.showGenerator = showGenerator
        self.generatorId = generatorId
        self.itemId = itemId
    }

    var showGenerator: Bool
    var generatorId: UUID?
    var itemId: UUID?
}

struct ChangeGeneratorEditorViewModifier: ViewModifier {
    let model: ChangeGeneratorModel

    @Environment(CharacterRootModel.self) private var root

    var itemBinding: Binding<ItemRowModel?> {
        Binding {
            if let generatedId = model.generatorId {
                return ItemRowModel(itemId: generatedId, typeId: .value)
            } else {
                return nil
            }
        } set: {
            if $0 == nil {
                model.generatorId = nil
                model.showGenerator = false
            }
        }
    }

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .sizedSheet(isPresented: $model.showGenerator) {
                GeneratorInline(root: root, item: itemBinding, saveId: root.editController(type: .main).model.id)
            }
    }
}
