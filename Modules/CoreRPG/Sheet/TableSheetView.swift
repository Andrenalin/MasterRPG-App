// @copyright André Trettin

import SwiftUI

struct TableSheetView<ImageContent: View>: View {
    let model: TableSheetModel
    let showImage: Bool
    let dismissAction: (() -> Void)?
    let imageContent: (CGSize) -> ImageContent

    @Environment(\.dismiss) var dismiss
    //@Environment(\.showGame) private var showGame

    @State private var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            closeButton()
            searchBarView

            if showImage {
                imageContent(CGSize(width: 360, height: 256))
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            listContentView
        }
    }

    var listContentView: some View {
        List {
            SheetView(model: model)
                .animation(.default, value: model.searchText)
        }
        .listStyle(.plain)
        .contentMargins(.horizontal, 12, for: .scrollContent)
    }
}

private extension TableSheetView {
    func closeButton() -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(model.sheetModel.name)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if let dismissAction {
                    dismissAction()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: showImage ? "xmark.circle" : "chevron.down.circle")
            }
            .borderLessTVBottonStyle()
            //.opacity(showGame ? 0 : 1)
            .padding(.top, 8)
        }
        .font(.title)
        .padding(.horizontal)
    }

    var showCloseButton: Bool {
        guard showImage else { return false }
        return true
        //return !showGame
    }

    @ViewBuilder
    var searchBarView: some View {
        @Bindable var model = model
        TextField(text: $model.searchText, prompt: searchPlaceHolder) {
            Label {
                Text("Search", bundle: .module)
            } icon: {
                Image(systemName: "magnifyingglass")
            }
        }
#if os(iOS) || os(visionOS)
        .textFieldStyle(.roundedBorder)
#endif
        .autocorrectionDisabled()
        .padding()
    }

    var searchPlaceHolder: Text {
        Text("\(Image(systemName: "magnifyingglass")) Search", bundle: .module)
    }
}

#Preview {
    TableSheetView(
        model: TableSheetModel(
            linkController: .fake,
            sheetModel: SheetModel(
                id: UUID(),
                name: "Hallo",
                description: "More",
                groups: [
                    .init(id: UUID(), name: "First", description: "Mega mit Link [Name](RPG://PHOTOS/0/9D877C38-41F5-4595-93A4-C25DC94BDD2E)", level: 1, entries: [
                        SheetEntryModel(id: UUID(), name: "Entry", value: "Value of Entry"),
                        SheetEntryModel(id: UUID(), name: "2nd Entry", value: "Another Value of Entry")
                    ]),
                    .init(id: UUID(), name: "Second **Master**", description: "Here it comes more", level: 1, entries: [
                        SheetEntryModel(id: UUID(), name: "Entry", value: "Value [inside link](RPG://MAPS/0/2181D9D0-8896-44E0-B2C4-A6E93F2533D7) of Entry und  [Name](RPG://PHOTOS/0/9D877C38-41F5-4595-93A4-C25DC94BDD2E) noch einer"),
                        SheetEntryModel(id: UUID(), name: "2nd Entry", value: "Another Value of Entry")
                    ])
                ]
            ),
            searchText: "in"
        ),
        showImage: false,
        dismissAction: nil,
        imageContent: { _ in Text("Empty")
        }
    )
}
