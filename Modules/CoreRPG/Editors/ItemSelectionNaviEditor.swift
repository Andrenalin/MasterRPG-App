// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

public struct ItemSelectionNaviEditor<Viewer: View>: View {
    public init(editController: any EditControllable, selectionModel: SelectionModel, title: LocalizedStringKey, bundle: Bundle?, value: NetworkModules, inline: Bool, selectorRoute: any NavigationDestination, @ViewBuilder viewerView: @escaping (UUID) -> Viewer) {
        self.editController = editController
        self.selectionModel = selectionModel
        self.title = title
        self.bundle = bundle
        self.value = value
        self.inline = inline
        self.selectorRoute = selectorRoute
        self.viewerView = viewerView
    }

    let editController: any EditControllable
    let selectionModel: SelectionModel
    let title: LocalizedStringKey
    let bundle: Bundle?
    let value: NetworkModules
    let inline: Bool
    let selectorRoute: any NavigationDestination
    let viewerView: (UUID) -> Viewer

    @Environment(\.wideMode) private var wideMode
    
    @Environment(\.navigator) private var navigator
#if !os(tvOS)
    @Environment(\.openWindow) private var openWindow
#endif

    @State private var dropBackgroundColor: Color = .clear
    @State private var dropForegroundColor: Color = .primary

    public var body: some View {
        let _ = Self._printChanges()
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

private extension ItemSelectionNaviEditor {
    
    @ViewBuilder
    var contentView: some View {
        itemEditorView
        
        if let selectedValue = selectionModel.currentValue {
            itemViewerView(for: selectedValue)
        }
    }

    @ViewBuilder
    var contentInlineView: some View {
        if let selectedValue = selectionModel.currentValue {
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
    
    func itemViewerView(for id: UUID) -> some View {
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
            selectionModel.currentValue = nil
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
                Text(selectionModel.currentValue == nil ? "Add" : "Change", bundle: .module)
            }
        }
    }
    
    var addSelectionButtonView: some View {
        Button {
            navigator.navigate(to: selectorRoute, method: .sheet)
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
        .dropDestination(for: value, handler: { name, itenId, entryId in
            let _ = drop(itemId: itenId)
        })
//        .dropDestination(for: LinkData.self) { items, _ in
//            guard let draggedLinkData = items.first else { return false }
//            return drop(link: draggedLinkData)
//        } isTargeted: { inDropArea in
//            dropBackgroundColor = inDropArea ? .accentColor : .clear
//            dropForegroundColor = inDropArea ? .white : .primary
//        }
#endif
    }

    var selectTitle: Text {
        (selectionModel.currentValue == nil ? Text("Add ", bundle: .module) : Text("Change ", bundle: .module)) + Text(title, bundle: bundle)
    }

    func drop(itemId: UUID) -> Bool {
        withAnimation {
            selectionModel.currentValue = itemId
        }
        editController.save(with: String(localized: "Change item").localizedString)
        return true
    }
}

@Observable
public final class SelectionModel: Hashable {
    @MainActor
    public init(id: UUID, filter: ItemListCategory, value: UUID? = nil) {
        self.id = id
        self.filter = filter
        self.currentValue = value
    }
    
    public var id: UUID
    public let filter: ItemListCategory
    public var currentValue: UUID?
    public var selectedValue: UUID?
    
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    public static func == (lhs: SelectionModel, rhs: SelectionModel) -> Bool {
        lhs.id == rhs.id
    }
}

#Preview {
    @Previewable @State var itemId: UUID? = UUID()

    ManagedPresentationView {
        ItemSelectionNaviEditor(editController: FakeEditController.fake, selectionModel: SelectionModel(id: UUID(), filter: .all, value: itemId), title: "Mega", bundle: nil, value: .photo, inline: false, selectorRoute: FakeSelectionRoute.selection(.photo)) { value in
            Text(value.uuidString)
        }
    }
    .environment(\.navigator, Navigator(configuration: NavigationConfiguration(verbosity: .info)))
}

enum FakeSelectionRoute: Hashable, Equatable, Codable {
    case selection(NetworkModules)
}

extension FakeSelectionRoute: NavigationDestination {
    var body: some View {
        switch self {
        case .selection(let networkModules):
            FakeSelectionRouteView(module: networkModules)
        }
    }
}

struct FakeSelectionRouteView: View {
    let module: NetworkModules
    
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        Text("Selection for: \(module.title)")
    }
}
