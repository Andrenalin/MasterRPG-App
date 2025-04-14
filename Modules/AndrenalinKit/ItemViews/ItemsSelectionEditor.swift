// @copyright André Trettin

import SwiftUI

public struct ItemsSelectionEditor<Viewer: View, Select: View, Action: View, ValueType: Equatable & Identifiable>: View {
    public init(editController: any EditControllable, model: Binding<[ValueType]>, selected: Binding<ValueType?>? = nil, title: LocalizedStringKey, bundle: Bundle?, value: NetworkModules, minimumWidth: CGFloat = 300, @ViewBuilder viewerView: @escaping (ValueType) -> Viewer, @ViewBuilder selectorView: @escaping () -> Select, @ViewBuilder actionView: @escaping () -> Action, valueFactory: @escaping (UUID) -> ValueType) {
        self.editController = editController
        self.model = model
        self.selected = selected
        self.title = title
        self.bundle = bundle
        self.value = value
        self.minimumWidth = minimumWidth
        self.viewerView = viewerView
        self.selectorView = selectorView
        self.actionView = actionView
        self.valueFactory = valueFactory
    }

    public init(editController: any EditControllable, model: Binding<[ValueType]>, selected: Binding<ValueType?>? = nil, title: LocalizedStringKey, bundle: Bundle?, value: NetworkModules, minimumWidth: CGFloat = 300, @ViewBuilder viewerView: @escaping (ValueType) -> Viewer, @ViewBuilder selectorView: @escaping () -> Select, valueFactory: @escaping (UUID) -> ValueType) where Action == EmptyView {
        self.editController = editController
        self.model = model
        self.selected = selected
        self.title = title
        self.bundle = bundle
        self.value = value
        self.minimumWidth = minimumWidth
        self.viewerView = viewerView
        self.selectorView = selectorView
        self.actionView = { EmptyView() }
        self.valueFactory = valueFactory
    }

    let editController: any EditControllable
    let model: Binding<[ValueType]>
    let selected: Binding<ValueType?>?
    let title: LocalizedStringKey
    let bundle: Bundle?
    let value: NetworkModules
    let minimumWidth: CGFloat
    let viewerView: (ValueType) -> Viewer
    let selectorView: () -> Select
    let actionView: () -> Action
    let valueFactory: (UUID) -> ValueType

    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel
    @Environment(\.itemSplitViewSizeMode) private var sizeMode
    @Environment(\.wideMode) private var wideMode
#if !os(tvOS)
    @Environment(\.openWindow) private var openWindow
#endif

    @State private var dropBackgroundColor: Color = .clear
    @State private var dropForegroundColor: Color = .primary

    public var body: some View {
        Section {
            itemEditorView

            itemsView
            
            actionView()
        } header: {
            headerView
        }
    }
}

private extension ItemsSelectionEditor {
    var itemsView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth))], spacing: 16) {
            ForEach(model.wrappedValue) { id in
                itemViewerView(for: id)
                    .padding(.top, 8)
            }
        }
        .onChange(of: model.wrappedValue, initial: false) {
            guard selected?.wrappedValue == nil, let firstValue = model.wrappedValue.first else { return }
            withAnimation {
                selected?.wrappedValue = firstValue
            }
            editController.save(with: String(localized: "Added selected item").localizedString)
        }
    }

    func itemViewerView(for id: ValueType) -> some View {
        viewerView(id)
            .frame(maxWidth: 300)
            .padding(.leading, valueFor(iOS: 0, macOS: 0, tvOS: 0, visionOS: 16))
            .overlay(alignment: .topLeading) {
                Button {
                    withAnimation { removeItem(id: id) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .imageScale(.large)
                        .padding(4)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .borderLessTVBottonStyle()
                .contentShape(.circle)
            }
            .selectListItem(isActive: selected != nil) {
                guard let selected else { return }
                withAnimation {
                    if selected.wrappedValue == id {
                        selected.wrappedValue = nil
                    } else {
                        selected.wrappedValue = id
                    }
                }
                editController.save(with: String(localized: "Current selected item").localizedString)
            } isSelected: {
                selected?.wrappedValue == id
            }
    }

    func removeItem(id: ValueType) {
        if let index = model.wrappedValue.firstIndex(of: id) {
            withAnimation {
                model.wrappedValue.remove(at: index)
                if selected?.wrappedValue == id {
                    selected?.wrappedValue = nil
                }
            }
            editController.save(with: String(localized: "Remove item").localizedString)
        }
    }

    var itemEditorView: some View {
        LabeledContent {
            HStack {
                if sizeMode != .small && wideMode != .small {
                    dropView
                }
#if !os(macOS)
                Button {
                    selectionSheetLinkModel.selectionView = AnyView(selectorView())
                    withAnimation { selectionSheetLinkModel.selection = true }
                } label: {
                    Label(title: { selectTitle }, icon: { Image(systemName: value.icon) } )
                }
                .borderLessTVBottonStyle()
                .foregroundStyle(.tint)
                .contentShape(.rect)
#endif
            }
        } label: {
            Text(model.isEmpty ? "Add" : "Change", bundle: .module)
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
        (model.isEmpty ? Text("Add ", bundle: .module) : Text("Change ", bundle: .module)) + Text(title, bundle: bundle)
    }

    func drop(link: LinkData) -> Bool {
        guard link.module == value else { return false }
        withAnimation {
            model.wrappedValue.append(valueFactory(link.itemId))
        }
        editController.save(with: String(localized: "Change item").localizedString)
        return true
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
#if !os(tvOS)
                        withAnimation { openWindow(id: value.linkWindowId) }
#endif
                    } label: {
                        Image(systemName: value.icon)
                    }
                    .contentShape(.rect)
                }
            }
        }
    }
}
