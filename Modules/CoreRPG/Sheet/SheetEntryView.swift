// @copyright André Trettin

import SwiftUI

struct SheetEntryView<LinkType: LinkDataTransferable>: View {
    init(model: SheetRootModel, entry: SheetModel, isEditor: Bool, linkTypes: LinkType.Type) {
        self.model = model
        self.entry = entry
        self.isEditor = isEditor
        self.linkTypes = linkTypes
    }

    let model: SheetRootModel
    let entry: SheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator

    @State private var viewControllable: (any ViewControllable)?

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(entry.inlineEntries) { inlineSheet in
                switch inlineSheet.sheetType {
                case .photoInline:
                    viewControllable?.rowViewer(source: entry.source, destination: entry.destination)
                        .frame(height: 96)
                        .frame(maxWidth: .infinity, alignment: .center)
                default:
                    EmptyView()
                }
            }
        }
        .contentShape(.rect)
        .moveDisabled(entry.sheetType != .item && entry.sheetType != .group)
    }
}
