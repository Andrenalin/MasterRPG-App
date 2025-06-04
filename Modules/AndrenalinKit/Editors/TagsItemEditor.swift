// @copyright André Trettin

import SwiftUI

public struct TagsItemEditor: View {
    public init(editController: any EditControllable, module: NetworkModules, title: LocalizedStringKey = "Tags", prompt: LocalizedStringKey = "New tag") {
        self.editController = editController
        self.module = module
        self.title = title
        self.prompt = prompt
    }
    
    let editController: any EditControllable
    let module: NetworkModules
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    
    @FocusState var focusState: Bool
    @State private var currentTag: String = ""
    
    public var body: some View {
        //let _ = Self._printChanges()
        LabeledContent {
            tagsView
        } label: {
            Text(title, bundle: .module)
        }
        
        LabeledContent {
            addTagView
        } label: {
            Text("Add", bundle: .module)
        }
    }
}

private extension TagsItemEditor {
    var tagsView: some View {
        HStack {
            if editController.model.tags.isEmpty {
                Text(editController.model.category.title)
                    .rowColoredTag()
                    .padding(.top, 4)
            }
            
            ForEach(editController.model.tags, id: \.self) { tag in
                Text(tag)
                    .rowColoredTag()
                    .removeItemImage {
                        remove(tag: tag)
                    }
            }
        }
    }
    
    var addTagView: some View {
        HStack {
            Button { addCurrentTag() } label: {
                Image(systemName: "plus")
                    .imageScale(.large)
            }
            .padding(.horizontal, self.valueFor(iOS: 16, macOS: 8, tvOS: 16, visionOS: 16))
            .disabled(currentTag.isEmpty)
            
            TextField(text: $currentTag, prompt: Text(prompt, bundle: .module)) {
                Text("Tag", bundle: .module)
            }
#if os(iOS) || os(visionOS)
            .autocapitalization(.none)
            .textContentType(.name)
#endif
            .disableAutocorrection(true)
            .focused($focusState)
            .onSubmit {
                addCurrentTag()
                focusState = true
            }
        }
        .labelsHidden()
    }
    
    func addCurrentTag() {
        let tag = currentTag.localizedUppercase
        withAnimation {
            editController.add(tag: tag)
            currentTag = ""
        }
    }
    
    func remove(tag: String) {
        editController.remove(tag: tag)
    }
}
