// @copyright André Trettin

import SwiftUI

public struct RemoveTagsEditor: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    public init(tags: Binding<[String]>) {
        self._tags = tags
    }
    
    @Binding var tags: [String]
    
    public var body: some View {
        RemoveTagsListView(tags: $tags, remove: remove(tag:))
    }
}

private struct RemoveTagsListView: View {
    @Binding var tags: [String]
    let remove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(tags.occurrenceKeyed()) { keyed in
                    let tag = keyed.element
                    Text(verbatim: tag)
                        .rowColoredTag(backgroundColor: Color.accentColor)
                        .removeItemImage(accessibilityName: tag) {
                            remove(tag)
                        }
                        .padding(.top, 8)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

private extension RemoveTagsEditor {
    func remove(tag: String) {
        withAnimation(accessibilityReduceMotion ? nil : .bouncy) { tags.removeAll(where: { $0 == tag }) }
    }
}

#Preview {
    @Previewable @State var tags = ["Dungeon", "Mystery", "Undead"]
    RemoveTagsEditor(tags: $tags)
        .padding()
}
