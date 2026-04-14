// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailInspectorView: View {
    let root: CharacterRootModel
    let model: ValueModel
    
    var body: some View {
        EditorLinkView(root: root.rootController, model: model, editorLinkModel: root.editorLinkModel)
    }
}
