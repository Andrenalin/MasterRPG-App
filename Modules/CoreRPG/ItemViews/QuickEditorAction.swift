// @copyright André Trettin

import SwiftUI

public struct QuickEditorAction<EntryViewModel, SelectionView: View>: View {
    public init(configs: [QuickLinkConfig], bundle: Bundle?, afterEntries: Binding<[EntryViewModel]>, scanner: @escaping ([UUID]?, NetworkModules, Bool, Bool) -> [EntryViewModel], @ViewBuilder selectionView: @escaping (Binding<[UUID]?>, NetworkModules, @escaping () -> Void) -> SelectionView) {
        self.configs = configs
        self.bundle = bundle
        _afterEntries = afterEntries
        self.selectionView = selectionView
        self.scanner = scanner
        _selectedLinkModule = State(wrappedValue: configs.first?.module ?? .none)
    }

    let configs: [QuickLinkConfig]
    let bundle: Bundle?
    @Binding var afterEntries: [EntryViewModel]
    let scanner: ([UUID]?, NetworkModules, Bool, Bool) -> [EntryViewModel]
    let selectionView: (Binding<[UUID]?>, NetworkModules, @escaping () -> Void) -> SelectionView

    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedLinkModule: NetworkModules = .none
    @State private var linkScanId: [NetworkModules: [UUID]] = [:]
    @State private var caseInsensitive = false
    @State private var isEntryLink = true
    @State private var wordOnly = false

    private var config: QuickLinkConfig? {
        configs.first { $0.module == selectedLinkModule }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let idForLinks = linkScanId[selectedLinkModule], let config {
                    Text(config.name(idForLinks))
                } else {
                    Text("Not yet selected", bundle: .module)
                }
            }
            .rowEditColor()

            HStack {
                Toggle(isOn: $isEntryLink) {
                    Label { Text(isEntryLink ? "Entry links" : "Root Links", bundle: .module) } icon: { Image(systemName: isEntryLink ? "chevron.down.circle" : "chevron.up.circle") }
                }
                .switchTVToggleStyle()
                .tint(Color.accentColor)

                Spacer()

                Button {
//                    selectionSheetLinkModel.selectionView = AnyView(
//                        selectionView($linkScanId[selectedLinkModule], selectedLinkModule) {
//                            selectionSheetLinkModel.selection = false
//                        }
//                        .environment(\.colorScheme, colorScheme)
//                    )
//                    selectionSheetLinkModel.selection = true
                } label: {
                    Text(linkScanId[selectedLinkModule] == nil ? "Select" : "Change", bundle: .module)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .borderLessTVBottonStyle()
                .disabled(!isEntryLink)
            }

            if configs.count > 1 {
                LabeledContent {
                    Picker(selection: $selectedLinkModule) {
                        ForEach(configs, id: \.module) { config in
                            Text(config.title, bundle: bundle)
                                .tag(config.module)
                        }
                    } label: {
                        Text("Which Module", bundle: .module)
                    }
                    .labelsHidden()
                    .pickerStyle(.automatic)
                } label: {
                    Text("Which Module", bundle: .module)
                }
            }

            HStack {
                Toggle(isOn: $caseInsensitive) {
                    Label { Text("Case Insensitive", bundle: .module) } icon: { Image(systemName: "textformat") }
                }
                Spacer()
                Toggle(isOn: $wordOnly) {
                    Label { Text("Word", bundle: .module) } icon: { Image(systemName: "character.textbox") }
                }
            }
            .switchTVToggleStyle()
            .tint(Color.accentColor)
        }
        .frame(maxWidth: .infinity)
        .detailSectionRow(color: colorScheme == .light ? .white : .blue.opacity(0.6)) {
            HStack {
                Text("Scan", bundle: .module)
                Spacer()
                Button {
                    afterEntries = scanner(isEntryLink ? linkScanId[selectedLinkModule] : nil, selectedLinkModule, caseInsensitive, wordOnly)
                } label: {
                    Image(systemName: "scanner")
#if os(macOS)
                        .imageScale(.large)
#endif
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEntryLink && linkScanId[selectedLinkModule] == nil)
#if os(macOS)
                .padding(.trailing)
#endif
            }
        }
    }
}
