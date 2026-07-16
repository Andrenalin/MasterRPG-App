// @copyright André Trettin

import SwiftUI

public struct RemoveTagsEditor: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

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
        ScrollView(.horizontal) {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    Text(verbatim: tag)
                        .rowColoredTag(backgroundColor: Color.accentColor)
                        .removeItemImage {
                            remove(tag: tag)
                        }
                        .padding(.top, 8)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    func remove(tag: String) {
        withAnimation(accessibilityReduceMotion ? nil : .bouncy) { tags.removeAll(where: { $0 == tag }) }
    }
}

#Preview {
    @Previewable @State var tags = ["Dungeon", "Mystery", "Undead"]
    RemoveTagsEditor(tags: $tags)
        .padding()
}
