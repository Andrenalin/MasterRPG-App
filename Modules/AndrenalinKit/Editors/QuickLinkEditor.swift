// @copyright André Trettin

import SwiftUI

public protocol ItemLinkEditable: Sendable {
    var textLinkContent: String { get }
}

public struct QuickLinkEditor<EntryViewModel: ItemLinkEditable, ActionView: View>: View {
    public init(editController: any EntryDataEditable, linkController: LinkControllable, model: Binding<[EntryViewModel]>, title: String, @ViewBuilder actionView: @escaping (Binding<[EntryViewModel]>) -> ActionView) {
        self.editController = editController
        self.linkController = linkController
        self.model = model
        self.title = title
        self.actionView = actionView
        _beforeEntries = State(wrappedValue: model.wrappedValue)
    }
    
    let editController: any EntryDataEditable
    let linkController: LinkControllable
    let model: Binding<[EntryViewModel]>
    let title: String
    let actionView: (Binding<[EntryViewModel]>) -> ActionView
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var beforeEntries: [EntryViewModel]
    @State private var afterEntries: [EntryViewModel] = []
    
    @State private var showHelp = false
    
    public var body: some View {
        NavigationStack {
            contentView
                .overlay(alignment: .top) {
                    VStack {
                        Text("The quick link editor allows you to select another table to scan the references. It will add links into the entries by searching for the same text and replace the occurences.", bundle: .module)
                            .padding()
                    }
                    .rowEditColor()
                    .background {
                        RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.8))
                    }
                    .padding(.horizontal)
                    .offset(x: 0, y: -8)
                    .opacity(showHelp ? 1 : 0)
                    .animation(.default, value: showHelp)
                }
                .navigationTitle(title)
#if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                    }
                    
                    ToolbarItem(placement: .automatic) {
                        Button {
                            withAnimation { showHelp.toggle() }
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            withAnimation {
                                model.wrappedValue = afterEntries
                            }
                            editController.save(with: String(localized: "Quick links added").localizedString)
                            dismiss()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .disabled(afterEntries.isEmpty)
                    }
                }
        }
    }
}

private extension QuickLinkEditor {
    var contentView: some View {
        VStack(spacing: 0) {
            actionView($afterEntries)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0 ..< beforeEntries.count, id: \.self) { index in
                        QuickLinkTextRow(linkControllable: linkController, model: beforeEntries[index], original: true)

                        if index < afterEntries.count {
                            QuickLinkTextRow(linkControllable: linkController, model: afterEntries[index], original: false)
                        }
                    }
                }
            }
            
        }
    }
}

struct QuickLinkTextRow<EntryViewModel: ItemLinkEditable>: View {
    let linkControllable: LinkControllable
    let model: EntryViewModel
    let original: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var _linkTextModel: LinkHighlightTextModel?

    var body: some View {
        LinkHighlightTextView(model: linkTextModel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(original ? .black : .white)
            .rowColorBackground(isSelected: false, backgroundColor: rowColor)
            .onChange(of: model.textLinkContent, initial: false) {
                updateEntryValues()
            }
    }

    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = _linkTextModel else {
            return updateEntryValues()
        }
        return linkModel
    }

    @discardableResult
    private func updateEntryValues() -> LinkHighlightTextModel {
        let entryText = model.textLinkContent
        if let linkModel = _linkTextModel {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: linkControllable, text: entryText, highlightedText: nil, toggler: nil, shareResult: nil, editAction: { _ in !original })
            Task { @MainActor in
                _linkTextModel = linkModel
            }
            return linkModel
        }
    }

    private var rowColor: Color {
        if original {
            return colorScheme == .dark ? .gray : .gray.opacity(0.25)
        }
        return colorScheme == .dark ? .black : .primary
    }
}
