// @copyright André Trettin

import SwiftUI

public struct AddTagsEditor: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

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
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, self.valueFor(iOS: 16, macOS: 8, tvOS: 16, visionOS: 16))
            .disabled(currentTag.isEmpty)
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(Text("Add tag", bundle: .module))
        }
    }

    func addCurrentTag() {
        let tag = currentTag.localizedUppercase
        guard !tags.contains(where: { $0 == tag }) else { return }
        var updatedTags = tags
        updatedTags.append(tag)
        updatedTags = updatedTags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        withAnimation(accessibilityReduceMotion ? nil : .bouncy(duration: 0.5, extraBounce: 0.4)) {
            tags = updatedTags
            currentTag = ""
        }
    }
}

#Preview {
    @Previewable @State var tags = ["Dungeon"]
    AddTagsEditor(tags: $tags)
        .padding()
}
