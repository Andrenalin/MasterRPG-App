// @copyright André Trettin

import SwiftUI

public struct LinkSelectionButton<Model>: View {
    public init(entryId: UUID, type: NetworkModules, keyPath: WritableKeyPath<Model, String>? = nil, title: LocalizedStringKey, bundle: Bundle?, showLink: Binding<ShowLinkEntryAction<Model>?>) {
        self.entryId = entryId
        self.type = type
        self.keyPath = keyPath
        self.title = title
        self.bundle = bundle
        self.showLink = showLink
    }

    let entryId: UUID
    let type: NetworkModules
    let keyPath: WritableKeyPath<Model, String>?
    let title: LocalizedStringKey
    let bundle: Bundle?
    let showLink: Binding<ShowLinkEntryAction<Model>?>

    public var body: some View {
        Button {
            withAnimation { showLink.wrappedValue = ShowLinkEntryAction(id: UUID(), entryId: entryId, type: type, keyPath: keyPath) }
        } label: {
            Label { Text(title, bundle: bundle) } icon: { Image(systemName: type.icon) }
        }
    }
}

#Preview {
    LinkSelectionButton(entryId: UUID(), type: .dice, keyPath: nil, title: "Add Dice", bundle: nil, showLink: .constant(ShowLinkEntryAction<ItemRowModel>(id: UUID(), entryId: UUID(), type: .dice, keyPath: nil)))
}
