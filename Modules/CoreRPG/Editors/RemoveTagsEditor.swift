// @copyright André Trettin

import SwiftUI

public struct RemoveTagsEditor: View {
    public init(tags: Binding<[String]>) {
        self._tags = tags
    }
    
    @Binding var tags: [String]
    
    public var body: some View {
        tagsView
    }
}

private extension RemoveTagsEditor {
    var tagsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .rowColoredTag(backgroundColor: Color.accentColor)
                        .removeItemImage {
                            remove(tag: tag)
                        }
                        .padding(.top, 8)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    func remove(tag: String) {
        withAnimation(.bouncy) { tags.removeAll(where: { $0 == tag }) }
    }
}

public struct AddTagsEditor: View {
    public init(tags: Binding<[String]>, prompt: LocalizedStringKey = "New tag") {
        self._tags = tags
        self.prompt = prompt
    }
    
    @Binding var tags: [String]
    let prompt: LocalizedStringKey
    
    @FocusState var focusState: Bool
    @State private var currentTag: String = ""
    
    public var body: some View {
        addTagView
    }
}

private extension AddTagsEditor {
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
    }
    
    func addCurrentTag() {
        let tag = currentTag.localizedUppercase
        guard !tags.contains(where: { $0 == tag }) else { return }
        var updatedTags = tags
        updatedTags.append(tag)
        updatedTags = updatedTags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        withAnimation(.bouncy(duration: 0.5, extraBounce: 0.4)) {
            tags = updatedTags
            currentTag = ""
        }
    }
}
