// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import PdfRPG
import SwiftUI

struct QuickEntryEditor: View {
    init(editController: EditController, currentModel: TableDataModel) {
        self.editController = editController
        self.currentModel = currentModel
        self._model = State(wrappedValue: currentModel.codableModel)
    }
    
    let editController: EditController
    let currentModel: TableDataModel
    
    @Environment(TableRootModel.self) private var root
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigator) private var navigator

#if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
#endif

    private enum Field: Hashable {
        case editor
    }
    @FocusState private var focusedField: Field?
    
    @State private var referenceText = DebouncerModel(initialValue: "", delay: 2)
    @State private var model: TableDataModel.TableDataModelCodable
    @State private var entries: [TableEntryDataModel.TableEntryDataModelCodable] = []
    
    @State private var showHelp = false
    @State private var showResult = false
    
    @State private var showEffectedLinksAlert: Bool = false
    @State private var editorModel = RemoveEntryListModel()

    var body: some View {
        NavigationStack {
            contentView
                .overlay(alignment: .top) {
                    VStack {
                        Text("The quick editor allows you to add all entries for the table at once. The first line is the title and the next text represents the content of the entry. An empty line is used to separate entries.", bundle: .module)
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
                .sizedSheet(isPresented: $showEffectedLinksAlert, idealSize: CGSize(width: 400, height: 600)) {
                    EffectedLinkAction(itemControllable: root.itemController, removeEntryList: editorModel, overwrite: true) { rowModels in
                        editorModel.removeItems.removeAll(where: { rowModels.contains($0) })
                        _ = editController.merge(entries: entries, into: currentModel, recoverEntries: editorModel.removeItems)
                        dismiss()
                    }
                }
                //.navigationTitle(currentModel.name)
#if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                    }
                    
                    ToolbarItem(placement: secondaryMenuPlacement) {
                        secondaryActionMenu
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
//                            Task {
                            editorModel.removeItems = editController.merge(entries: entries, into: currentModel, recoverEntries: nil)
                                if editorModel.removeItems.isEmpty {
                                    dismiss()
                                } else {
                                    showEffectedLinksAlert.toggle()
                                }
//                            }
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                }
        }
#if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
#endif
    }
}

private extension QuickEntryEditor {
    private var contentView: some View {
        HStack(spacing: 8) {
            if showResult {
                entryListView
            }

            editorView
        }
        .animation(.bouncy, value: showResult)
        .onAppear {
            referenceText.input = initialText
            focusedField = .editor
        }
        .onChange(of: referenceText.output) {
            entries = createMultiLineEntries(referenceText.output)
            model.entries = entries
        }
    }
    
    @ViewBuilder
    var secondaryActionMenu: some View {
        ControlGroup {
            showResultButton
            removeLineBreak
        }
        
        ControlGroup {
            pdfButton
        }
        
        ControlGroup {
            showHelpButton
        }
    }
    
    private var entryListView: some View {
        List {
            ForEach(model.entries, id: \.entryId) { entry in
                EntryRow(entryId: entry.entryId, name: entry.name, content: entry.content, cacheItemListModel: CacheItemListModel())
                    .foregroundStyle(.primary)
            }
        }
#if !os(tvOS)
        .scrollContentBackground(.hidden)
#endif
//        .listTintStyle()
        .environment(CacheItemListModel())
        .overlay {
#if os(iOS) || os(tvOS)
            if let selectedPdf = editController.selectionPdf.itemId {
                root.pdfRoot.viewController.inlineViewer(root: root.pdfRoot, with: selectedPdf, withoutBookmark: true) {
                    withAnimation { editController.selectionPdf.resetSelection(itemId: nil) }
                }
                .background(.black)
                //.pdfViewerActions(PdfViewerActions(selectedText: usePdfSelection(selection:)))
            }
#endif
        }
    }
    
    private func usePdfSelection(selection: NSAttributedString) {
        withAnimation { referenceText.input.append(selection.string) }
    }
    
    private var textBinding: Binding<String> {
        Binding<String>(
            get: { referenceText.input },
            set: { referenceText.input = $0 }
        )
    }

    private var editorView: some View {
        VStack(alignment: .leading, spacing: 8) {
#if !os(tvOS)
            TextEditor(text: textBinding)
                .foregroundStyle(.primary)
                .focused($focusedField, equals: .editor)
#endif
        }
#if !os(visionOS)
        //.rowColorBackground(isSelected: false)
#endif
    }
    
    private var initialText: String {
        currentModel.codableModel.entries.map {
            "\($0.name)\n\($0.content)"
        }.joined(separator: "\n\n")
    }
}

private extension QuickEntryEditor {
    func createMultiLineEntries(_ text: String) -> [TableEntryDataModel.TableEntryDataModelCodable] {
        var newEntries: [TableEntryDataModel.TableEntryDataModelCodable] = []
        var name = ""
        var content = ""
        
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .forEach { (index, entryline) in
                guard !entryline.isEmpty else {
                    if let entry = createEntry(with: name, content: content, index: index) {
                        newEntries.append(entry)
                    }
                    name = ""
                    content = ""
                    return
                }
                
                if name.isEmpty {
                    name = String(entryline.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    content.append(contentsOf: "\(entryline.trimmingCharacters(in: .whitespacesAndNewlines))\n")
                }
            }
        
        if let entry = createEntry(with: name, content: content, index: newEntries.count) {
            newEntries.append(entry)
        }
        
        return newEntries
    }
    
    private func createEntry(with name: String, content: String, index: Int) -> TableEntryDataModel.TableEntryDataModelCodable? {
        guard !name.isEmpty else { return nil }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return TableEntryDataModel.TableEntryDataModelCodable(itemId: model.itemId, entryId: UUID(), index: index, name: name, content: trimmedContent)
    }
    
    func removeLineBreak(_ text: String) -> String {
        var updatedBlock: [String] = []
        var currentTitle: String = ""
        var currentContent: String = ""
        
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .forEach { entryline in
                if entryline.isEmpty {
                    if !currentTitle.isEmpty {
                        var newBlock = currentTitle
                        if !currentContent.isEmpty {
                            newBlock.append("\n\(currentContent)")
                        }
                        updatedBlock.append(newBlock)
                    }
                    currentTitle = ""
                    currentContent = ""
                } else {
                    var newLine = entryline.trimmingCharacters(in: .whitespacesAndNewlines)
                    if currentTitle.isEmpty {
                        currentTitle.append(newLine)
                    } else {
                        // content 2nd line and more
                        if newLine.last == "-" {
                            newLine = String(newLine.dropLast())
                        } else {
                            newLine.append(" ")
                        }
                        currentContent.append(newLine)
                    }
                }
            }

        if !currentTitle.isEmpty {
            var newBlock = currentTitle
            if !currentContent.isEmpty {
                newBlock.append("\n\(currentContent)")
            }
            updatedBlock.append(newBlock)
        }
        return updatedBlock.joined(separator: "\n\n")
    }
    
    var pdfButton: some View {
        Button {
#if os(macOS) || os(visionOS)
            openWindow(id: NetworkModules.pdf.linkWindowId)
#else
            withAnimation { showResult <=> true }
            navigator.navigate(to: SelectionPdfRoute.selection, method: .sheet)
#endif
        } label: {
            Label { Text("Extract PDF", bundle: .module) } icon: { Image(systemName: "book") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var removeLineBreak: some View {
        Button {
            withAnimation {
                referenceText.input = removeLineBreak(referenceText.output)
            }
        } label: {
            Label {
                Text("Remove Line Breaks", bundle: .module)
            } icon: {
                Image(systemName: "text.insert")
            }
        }
    }

    var showHelpButton: some View {
        Button {
            withAnimation { showHelp.toggle() }
        } label: {
            Label {
                Text("Show Help", bundle: .module)
            } icon: {
                Image(systemName: "questionmark")
            }
        }
    }
    
    var showResultButton: some View {
        Toggle(isOn: $showResult) {
            Label {
                Text("Show Result", bundle: .module)
            } icon: {
                Image(systemName: showResult ? "rectangle.split.2x1" : "rectangle.split.2x1.slash")
                    .contentTransition(.symbolEffect(.automatic))
            }
        }
    }
    
    var secondaryMenuPlacement: ToolbarItemPlacement {
#if os(tvOS)
        .automatic
#else
        .secondaryAction
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(TableRootModel.self) var root
    
    QuickEntryEditor(editController: root.editController, currentModel: root.itemController.model(for: MockData.previewId)!)
        .colorScheme(.dark)
        .tint(NetworkModules.table.tint)
}
