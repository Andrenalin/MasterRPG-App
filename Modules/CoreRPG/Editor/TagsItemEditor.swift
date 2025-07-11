// @copyright André Trettin

import SwiftUI

public struct TagsItemEditor: View {
    public init(tags: Binding<[String]>, title: LocalizedStringKey = "Tags", prompt: LocalizedStringKey = "New tag") {
        self._tags = tags
        self.title = title
        self.prompt = prompt
    }
    
    @Binding var tags: [String]
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    
    @FocusState var focusState: Bool
    @State private var currentTag: String = ""
    
    public var body: some View {
        let _ = Self._printChanges()
        tagsView
        
        addTagView
    }
}

private extension TagsItemEditor {
    var tagsView: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .rowColoredTag()
                        .removeItemImage {
                            remove(tag: tag)
                        }
                        .padding(.top, 8)
                }
            }
        }
    }
    
    var addTagView: some View {
        HStack {
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
            
            Button { addCurrentTag() } label: {
                Image(systemName: "plus")
                    .imageScale(.large)
            }
            .padding(.horizontal, self.valueFor(iOS: 16, macOS: 8, tvOS: 16, visionOS: 16))
            .disabled(currentTag.isEmpty)
            .buttonStyle(.borderedProminent)
        }
        //.labelsHidden()
    }
    
    func addCurrentTag() {
        let tag = currentTag.localizedUppercase
        withAnimation {
            tags.append(tag)
            //editController.add(tag: tag)
            currentTag = ""
        }
    }
    
    func remove(tag: String) {
        tags.removeAll(where: { $0 == tag })
        //editController.remove(tag: tag)
    }
}
