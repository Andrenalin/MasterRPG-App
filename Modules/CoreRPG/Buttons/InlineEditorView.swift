// @copyright André Trettin

import SwiftUI

struct InlineEditorView: View {
    let entryDataEditable: (any EntryDataEditable)
    let updateHandler: (String) -> Void
    let entry: SheetModel

    init(entryDataEditable: any EntryDataEditable, updateHandler: @escaping (String) -> Void, entry: SheetModel) {
        self.entryDataEditable = entryDataEditable
        self.updateHandler = updateHandler
        self.entry = entry
        self._editModel = State(wrappedValue: TextEditModel(linkRegisterController: entryDataEditable.linkRegisterController))
    }

    @State private var selectedValue: Bool = false
    @State private var editModel: TextEditModel
    @FocusState private var currentFocus: EntryEditorFocusField?

    @State private var intValue: Int = 0
    @State private var doubleValue: Double = 0.0

    var body: some View {
        VStack {
            switch entry.editType {
            case .none:
                EmptyView()
            case .number:
                textFieldEditor()
                QuickEditorIntView(number: $intValue)
            case .decimal:
                textFieldEditor()
                QuickEditorDoubleView(number: $doubleValue)
            case .selection:
                InlineEditorViewSelectionEditorView(selectedValue: $selectedValue, entryDataEditable: entryDataEditable)
            case .text:
                textFieldEditor()
            }
        }
        .onChange(of: entryDataEditable.entryValue(itemId: entry.source.itemId, entryId: entry.source.entryId), initial: true) {
            withAnimation {
                syncEditModel(with: entryDataEditable.entryValue(itemId: entry.source.itemId, entryId: entry.source.entryId))
                doubleValue <=> entryDataEditable.entryValueAsDecimal(itemId: entry.source.itemId, entryId: entry.source.entryId)
                intValue <=> entryDataEditable.entryValueAsNumber(itemId: entry.source.itemId, entryId: entry.source.entryId)
                selectedValue <=> entryDataEditable.entryValueAsSelected(itemId: entry.source.itemId, entryId: entry.source.entryId)
            }
        }
        .onChange(of: selectedValue) {
            updateValue {
                entryDataEditable.updateValue(
                    itemId: entry.source.itemId,
                    entryId: entry.source.entryId,
                    selected: selectedValue
                )
            }
        }
        .onChange(of: intValue) {
            updateValue {
                entryDataEditable.updateValue(
                    itemId: entry.source.itemId,
                    entryId: entry.source.entryId,
                    number: intValue
                )
            }
        }
        .onChange(of: doubleValue) {
            updateValue {
                entryDataEditable.updateValue(
                    itemId: entry.source.itemId,
                    entryId: entry.source.entryId,
                    decimal: doubleValue
                )
            }
        }
        // EntryNameEditor debounces attributedName → name internally
        // (TextEditModel.updateNameLinks(), ~100ms) — this piggybacks on that
        // existing signal to commit the value rather than adding a second,
        // separate debounce.
        //
        // Restricted to `.text` — for `.number`/`.decimal` the text field is
        // shown alongside the stepper only so a formula/link value stays
        // inspectable (e.g. a hit-points entry set up as a pure markdown
        // link), never as a second way to edit it. Committing raw text here
        // for those types would overwrite the "base|modifier" convention
        // wholesale with plain text — destroying the link and permanently
        // freezing any dependent calculation (e.g. `pin.healthPercent`) at
        // 100%. It's also one unintended trigger away: `EntryNameEditor`'s
        // attributed-link rendering can normalize the stored markdown
        // differently than what's on disk, and the sync in the `onChange`
        // above (whenever the stored value legitimately changes, e.g. from
        // the stepper) re-syncs `editModel.name` right back through this
        // same debounce.
        .onChange(of: editModel.name) {
            guard entry.editType == .text else { return }
            commitValue(editModel.name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

private extension InlineEditorView {
    /// Reflects an externally-changed value (from `entryDataEditable`, e.g. a
    /// network sync) into the edit model without going through the debounced
    /// name/link update path — mirrors the old `textValue <=> value` sync.
    func syncEditModel(with value: String) {
        editModel.source = ItemRowModel(itemId: entry.source.itemId, entryId: entry.source.entryId, typeId: entry.source.typeId)
        editModel.name = value
        editModel.resetAttributedName()
    }

    func updateValue(_ mutation: () -> Void) {
        let previousValue = entryDataEditable.entryValue(
            itemId: entry.source.itemId,
            entryId: entry.source.entryId
        )
        mutation()
        let updatedValue = entryDataEditable.entryValue(
            itemId: entry.source.itemId,
            entryId: entry.source.entryId
        )
        withAnimation {
            syncEditModel(with: updatedValue)
        }
        if updatedValue != previousValue {
            updateHandler(updatedValue)
        }
    }

    func commitValue(_ value: String) {
        updateValue {
            entryDataEditable.updateValue(
                itemId: entry.source.itemId,
                entryId: entry.source.entryId,
                value: value
            )
        }
    }

    /// Uses the same attributed-string editor as the full entry editor
    /// (`EntryNameEditor`/`TextEditModel`) instead of a plain `TextField`, so
    /// a markdown link typed into a live value gets rendered specially
    /// instead of showing as raw "[Name](scheme://...)" text.
    func textFieldEditor() -> some View {
        EntryNameEditor(editModel: editModel, currentFocus: $currentFocus, showLabel: false, showClearButton: false)
            .padding(.horizontal, 8)
#if os(iOS)
            .applyIf(entry.editType == .number || entry.editType == .decimal) { content in
                content.keyboardType(.numbersAndPunctuation)
            }
#endif
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct InlineEditorViewSelectionEditorView: View {
    @Binding var selectedValue: Bool
    let entryDataEditable: any EntryDataEditable

    var body: some View {
        Toggle(isOn: $selectedValue) {
            Label { Text("Selected", bundle: .module) } icon: { Image(systemName: "checkmark.square") }
        }
        .labelsHidden()
        .moduleTint(entryDataEditable.itemControllable.config.module)
        .toggleStyle(.automatic)
        .fixedSize(horizontal: true, vertical: true)
    }
}

#Preview {
    InlineEditorView(
        entryDataEditable: FakeEditController.fake,
        updateHandler: { _ in },
        entry: SheetModel(
            source: ItemRowModel(itemId: .fixture1, entryId: .fixture2, typeId: .none),
            editType: .number,
            name: "Armor Class",
            description: "A deterministic inline editor.",
            entries: []
        )
    )
    .padding()
}
