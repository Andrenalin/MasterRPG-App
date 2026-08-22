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
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    
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
                        Color.primary.opacity(0.8).clipShape(.rect(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                    .offset(x: 0, y: -8)
                    .opacity(showHelp ? 1 : 0)
                    .allowsHitTesting(showHelp)
                    .accessibilityHidden(!showHelp)
                    .animation(accessibilityReduceMotion ? nil : .default, value: showHelp)
                }
                .navigationTitle(Text(verbatim: title))
                .navigationBarTitleDisplayModeAll(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .accessibilityLabel(Text("Cancel", bundle: .module))
                    }
                    
                    ToolbarItem(placement: .automatic) {
                        Button {
                            withAnimation(accessibilityReduceMotion ? nil : .default) { showHelp.toggle() }
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .accessibilityLabel(
                            showHelp
                                ? Text("Hide Help", bundle: .module)
                                : Text("Show Help", bundle: .module)
                        )
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            withAnimation(accessibilityReduceMotion ? nil : .default) {
                                model.wrappedValue = afterEntries
                            }
                            dismiss()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .disabled(afterEntries.isEmpty)
                        .accessibilityLabel(Text("Apply", bundle: .module))
                    }
                }
        }
    }
}

/// Pairs a `beforeEntries` row with its (possibly not-yet-scanned) `afterEntries`
/// counterpart at the same position, so `ForEach` below yields exactly one view
/// per iteration instead of a variable 1-or-2 view count. `beforeEntries` is only
/// ever seeded once, at `QuickLinkEditor.init`, so the position is a genuinely
/// stable identity here — not the usual "reorderable list" case.
private struct QuickLinkComparisonPair<EntryViewModel>: Identifiable {
    let id: Int
    let before: EntryViewModel
    let after: EntryViewModel?
}

private extension QuickLinkEditor {
    var comparisonPairs: [QuickLinkComparisonPair<EntryViewModel>] {
        beforeEntries.indices.map { index in
            QuickLinkComparisonPair(
                id: index,
                before: beforeEntries[index],
                after: index < afterEntries.count ? afterEntries[index] : nil
            )
        }
    }

    var contentView: some View {
        VStack(spacing: 0) {
            actionView($afterEntries)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(comparisonPairs) { pair in
                        VStack(alignment: .leading, spacing: 4) {
                            QuickLinkTextRow(linkControllable: linkController, model: pair.before, original: true)

                            if let after = pair.after {
                                QuickLinkTextRow(linkControllable: linkController, model: after, original: false)
                            }
                        }
                    }
                }
            }

        }
    }
}

struct QuickLinkPreviewEntry: ItemLinkEditable {
    let textLinkContent: String
}

#Preview("Quick Link Editor") {
    @Previewable @State var entries = [QuickLinkPreviewEntry(textLinkContent: "The forgotten shrine awaits.")]
    QuickLinkEditor(
        editController: FakeEditController.fake,
        linkController: FakeLinkController.fake,
        model: $entries,
        title: "Quick Links"
    ) { afterEntries in
        Button {
            afterEntries.wrappedValue = [QuickLinkPreviewEntry(textLinkContent: "The [forgotten shrine](RPG://ADVENTURE/preview) awaits.")]
        } label: {
            Text(verbatim: "Scan Links")
        }
        .padding()
    }
}
