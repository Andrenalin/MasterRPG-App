// @copyright André Trettin

import SwiftUI

/// The Quick Link part of the quick editor: the table picker sheet, the scan once a table is
/// chosen, and the alert that reports what the scan did. `scan` runs the editor's own action and
/// returns `nil` when the table could not be read. See CODE_AUDIT_Since_3.0.1 §9.12.
struct QuickEntryEditorQuickLinkModifier: ViewModifier {
    let tableRoot: ItemRootController?
    @Binding var showPicker: Bool
    let scan: (UUID) -> QuickLinkScanner.Outcome?

    @State private var selection = ItemSelectionModel(isSingleSelection: true, allowCollections: false)
    @State private var outcome: QuickLinkScanner.Outcome?

    func body(content: Content) -> some View {
        content
            .sizedSheet(isPresented: $showPicker, idealSize: .pickerSheet) {
                if let tableRoot {
                    QuickEntryEditorTablePickerView(tableRoot: tableRoot, selection: selection)
                }
            }
            .onChange(of: selection.itemId) {
                guard let tableId = selection.itemId else { return }
                showPicker = false
                selection.resetSelection(itemId: nil, entryId: nil)
                outcome = scan(tableId)
            }
            .alert(Text("Quick Link", bundle: .module), isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } })) {
                Button { outcome = nil } label: { Text("OK", bundle: .module) }
            } message: {
                switch outcome {
                case .sameTable:
                    Text("This is the table you are editing. Its entries can't link to themselves, so the scan was ignored.", bundle: .module)
                case .linked(let result) where result.count > 0:
                    Text("\(result.count) links added", bundle: .module)
                default:
                    Text("No matching entries found", bundle: .module)
                }
            }
    }
}

struct QuickEntryEditorQuickLinkButtonView: View {
    @Binding var showPicker: Bool

    var body: some View {
        Button {
            showPicker = true
        } label: {
            Label { Text("Quick Link", bundle: .module) } icon: { Image(systemName: "link.badge.plus") }
        }
    }
}

private struct QuickEntryEditorTablePickerView: View {
    let tableRoot: ItemRootController
    let selection: ItemSelectionModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ManagedNavigationStack(name: "QuickEntryEditorTablePicker") {
            tableRoot.viewControllable.linkListView(rootController: tableRoot, type: .selection, itemSelectionModel: selection)
                .navigationTitle(Text("Quick Link", bundle: .module))
                .navigationBarTitleDisplayModeAll(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .accessibilityLabel(Text("Cancel", bundle: .module))
                    }
                }
        }
    }
}
