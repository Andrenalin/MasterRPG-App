// @copyright André Trettin

import SwiftUI

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

public struct ItemSelectionEditor<Viewer: View, Select: View, ValueType: Equatable & Identifiable>: View {
    public init(editController: any EditControllable, model: Binding<ValueType?>, title: LocalizedStringKey, bundle: Bundle?, value: NetworkModules, inline: Bool, @ViewBuilder viewerView: @escaping (ValueType) -> Viewer, @ViewBuilder selectorView: @escaping () -> Select, valueFactory: @escaping (UUID) -> ValueType) {
        self.editController = editController
        self.model = model
        self.title = title
        self.bundle = bundle
        self.value = value
        self.inline = inline
        self.viewerView = viewerView
        self.selectorView = selectorView
        self.valueFactory = valueFactory
    }

    let editController: any EditControllable
    let model: Binding<ValueType?>
    let title: LocalizedStringKey
    let bundle: Bundle?
    let value: NetworkModules
    let inline: Bool
    let viewerView: (ValueType) -> Viewer
    let selectorView: () -> Select
    let valueFactory: (UUID) -> ValueType

    @Environment(\.navigator) private var navigator
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel
    @Environment(\.wideMode) private var wideMode
#if !os(tvOS)
    @Environment(\.openWindow) private var openWindow
#endif

    @State private var dropBackgroundColor: Color = .clear
    @State private var dropForegroundColor: Color = .primary

    public var body: some View {
        Group {
            if inline {
                ViewThatFits {
                    HStack {
                        contentInlineView
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack {
                        contentInlineView
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Section {
                    contentView
                } header: {
                    headerView
                }
            }
        }
    }
}

private extension ItemSelectionEditor {
    
    @ViewBuilder
    var contentView: some View {
        itemEditorView
        
        if let selectedValue = model.wrappedValue {
            itemViewerView(for: selectedValue)
        }
    }

    @ViewBuilder
    var contentInlineView: some View {
        if let selectedValue = model.wrappedValue {
            itemViewerView(for: selectedValue)
            
            Spacer()
        }
        
        itemEditorView
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    var headerView: some View {
        VStack {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            HStack {
                Text(title, bundle: bundle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                if wideMode != .small {
                    Spacer()
                    Button {
                        withAnimation {
#if !os(tvOS)
                            openWindow(id: value.linkWindowId)
#endif
                        }
                    } label: {
                        Image(systemName: value.icon)
                    }
                }
            }
        }
    }
    
    func itemViewerView(for id: ValueType) -> some View {
        LabeledContent {
            viewerView(id)
                .frame(maxWidth: 300)
                .padding(.leading, 32)
                .overlay(alignment: .topLeading) {
                    Image(systemName: "minus.circle.fill")
                        .imageScale(.large)
                        .padding(4)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
                .onTapGesture { removeItem() }
        } label: {
            Text(title, bundle: bundle)
        }
    }

    func removeItem() {
        withAnimation {
            model.wrappedValue = nil
        }
        editController.save(with: String(localized: "Remove item").localizedString)
    }

    @ViewBuilder
    var itemEditorView: some View {
        if inline {
            addSelectionButtonView
        } else {
            LabeledContent {
                HStack {
                    if !inline && wideMode != .small {
                        dropView
                    }
#if !os(macOS)
                    addSelectionButtonView
#endif
                }
            } label: {
                Text(model.wrappedValue == nil ? "Add" : "Change", bundle: .module)
            }
        }
    }
    
    var addSelectionButtonView: some View {
        Button {
            selectionSheetLinkModel.selectionView = AnyView(selectorView())
            withAnimation { selectionSheetLinkModel.selection = true }
        } label: {
            Label(title: { selectTitle }, icon: { Image(systemName: value.icon) } )
        }
    }

    var dropView: some View {
        Group {
            Text("Drop ", bundle: .module) + Text(title, bundle: bundle) + Text(" here", bundle: .module)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .foregroundStyle(dropForegroundColor)
        .background {
            RoundedRectangle(cornerRadius: 8).fill(dropBackgroundColor)
        }
#if !os(tvOS)
        .dropDestination(for: LinkData.self) { items, _ in
            guard let draggedLinkData = items.first else { return false }
            return drop(link: draggedLinkData)
        } isTargeted: { inDropArea in
            dropBackgroundColor = inDropArea ? .accentColor : .clear
            dropForegroundColor = inDropArea ? .white : .primary
        }
#endif
    }

    var selectTitle: Text {
        (model.wrappedValue == nil ? Text("Add ", bundle: .module) : Text("Change ", bundle: .module)) + Text(title, bundle: bundle)
    }

    func drop(link: LinkData) -> Bool {
        guard link.module == value else { return false }
        withAnimation {
            model.wrappedValue = valueFactory(link.itemId)
        }
        editController.save(with: String(localized: "Change item").localizedString)
        return true
    }
}

#Preview {
    @Previewable @State var value: UUID?

    ItemSelectionEditor(editController: FakeEditController.fake, model: $value, title: "Mega", bundle: nil, value: .photo, inline: false) { value in
        Text(value.uuidString)
    } selectorView: {
        Text("Selection View")
    } valueFactory: { value in
        UUID()
    }
    .environment(SelectionSheetLinkModel())
}

