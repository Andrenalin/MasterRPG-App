// @copyright André Trettin

import SwiftUI

struct ItemListSection<Row: View>: View {
    let listController: any ListControllable
    let rowView: (ItemRowTreeModel, Bool) -> Row
    var removeEntryList: RemoveEntryListModel? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.itemSplitViewSizeMode) private var itemSplitSizeMode
    @Environment(\.itemListConfiguration) private var itemListConfiguration
    @Environment(\.itemListChildrenConfiguration) private var childrenConfiguration
    
    private var sizeMode: WideMode {
#if os(tvOS)
        .small
#else
        itemSplitSizeMode
#endif
    }
    
    var body: some View {
        if listController.model.selectionMode != nil {
            Section {
                ForEach(listController.model.selectedItems, id: \.selectionId) { item in
                    rowLinkView(for: item, selectable: false)
                        .selectionDisabled(true)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
#if os(iOS) || os(visionOS)
                        .listRowSeparator(.hidden)
#endif
#if os(visionOS)
                        .listRowBackground(RoundedRectangle(cornerRadius: 16).fill(colorRow(item: item)))
#else
                        .listRowBackground(Rectangle().fill(colorRow(item: item)))
#endif
#if os(macOS)
                        .padding(EdgeInsets(top: 4, leading: CGFloat(item.level * 8), bottom: 4, trailing: 0))
#elseif os(visionOS)
                        .padding(EdgeInsets(top: 4, leading: CGFloat(item.level * 8), bottom: 4, trailing: 0))
#else
                        .padding(EdgeInsets(top: 4, leading: CGFloat(item.level * 8), bottom: 4, trailing: 36))
#endif
                        .overlay(alignment: .topLeading) {
                            if item.level % 2 == 1 {
                                overlayChildrenView(item: item)
                            } else {
                                overlayContentView(item: item)
                            }
                        }
#if !os(macOS)
                        .padding(.leading, 2)
#endif
                        .padding(.leading, 8)
                }
            } header: {
                selectionHeaderView
            }
        }
        
        Section {
            ForEach(listController.model.filteredItems, id: \.id) { item in
                VStack {
                    rowLinkView(for: item, selectable: listController.model.allowEditing || !childrenConfiguration.disableSelection)
                        .environment(\.itemListToggleAction, ItemListToggleAction(toggler: { itemId, module in await listController.toggle(parent: item, child: ItemRowModel(itemId: itemId, typeId: module))
                        }))
#if !os(tvOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                withAnimation { listController.resetAction(selection: Set([item])) }
                                removeEntryList?.removeItems = [item.model]
                                withAnimation { removeEntryList?.showDeleteAlert.toggle() }
                            } label: {
                                Image(systemName: "trash")
                                    .tint(.red)
                            }
                        }
#endif
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
#if os(iOS) || os(visionOS)
                .listRowSeparator(.hidden)
#endif
#if os(visionOS)
                .listRowBackground(RoundedRectangle(cornerRadius: 16).fill(colorRow(item: item)))
#else
                .listRowBackground(Rectangle().fill(colorRow(item: item)))
#endif
#if os(macOS)
                .padding(EdgeInsets(top: 4, leading: CGFloat(item.level * 8), bottom: 4, trailing: 0))
#elseif os(visionOS)
                .padding(EdgeInsets(top: 4, leading: CGFloat(item.level * 8), bottom: 4, trailing: 0))
#else
                .padding(EdgeInsets(top: 4, leading: CGFloat(item.level * 8), bottom: 4, trailing: 36))
#endif
                .overlay(alignment: .topLeading) {
                    if item.level % 2 == 1 {
                        overlayChildrenView(item: item)
                    } else {
                        overlayContentView(item: item)
                    }
                }
#if !os(macOS)
                .padding(.leading, 2)
#endif
                .tag(item)
            }
        } header: {
            headerView
        }
    }
    
    @ViewBuilder
    func rowLinkView(for item: ItemRowTreeModel, selectable: Bool) -> some View {
        Group {
            if sizeMode == .small && childrenConfiguration.canNavigate {
                NavigationLink(value: item) {
                    pureRowView(for: item, selectable: selectable)
                }
            } else {
                pureRowView(for: item, selectable: selectable)
            }
        }
    }
    
    func pureRowView(for item: ItemRowTreeModel, selectable: Bool) -> some View {
        rowView(item, listController.model.selectedItems.contains(item))
            .contentShape(Rectangle())
#if !os(tvOS)
            .applyIf(valueFor(iOS: true, macOS: !childrenConfiguration.canNavigate, tvOS: false, visionOS: true)) { content in
                content.draggable(LinkData(item: item, name: listController.itemControllable.createLink(model: item.model)))
            }
#endif
            .applyIf(listController.model.selectionMode != nil) {
                $0.onTapGesture {
                    if selectable && isSelectable(item: item) {
                        withAnimation { listController.setSelectedItem(selection: item) }
                    }
                }
            }
            .expandChildren(isActive: subListActive(model: item.model), isExpanded: item.expanded, isSelected: listController.model.selectedItems.contains(item)) {
                withAnimation { listController.toggleExpanded(item: item) }
            }
            .selectListItem(isActive: isSelectable(item: item), hide: false) {
                listController.setSelectedItem(selection: item)
            } isSelected: {
                listController.model.selectedItems.contains(item)
            }
    }
    
    private func isSelectable(item: ItemRowTreeModel) -> Bool {
        listController.model.selectionMode != nil &&
        ((listController.model.onlyItems && item.model.entryId == nil) ||
         (listController.model.onlyEntries && item.model.entryId != nil) ||
         (!listController.model.onlyItems && !listController.model.onlyEntries))
    }
    
    private func subListActive(model: ItemRowModel) -> Bool {
        let platform = valueFor(iOS: true, macOS: true, tvOS: !childrenConfiguration.canNavigate, visionOS: true)
        return platform && listController.model.hasChildren && model.entryId == nil && !listController.itemControllable.children(for: model).isEmpty
    }
    
    private func overlayChildrenView(item: ItemRowTreeModel) -> some View {
        ForEach(1 ... item.level, id: \.self) { i in
            if i % 2 == 1 {
                ListChildShape(thickness: 1, isHalf: i == item.level ? item.isLast : false, upOffset: item.isFirst ? 20 : 20, downOffset: 20, withoutChild: i < item.level)
                    .fill(indexColor(for: i))
                    .frame(width: 8)
                    .offset(x: CGFloat((i - 1) * 8))
            }
        }
    }
    
    @ViewBuilder
    private func overlayContentView(item: ItemRowTreeModel) -> some View {
        if item.level > 1 {
            ForEach(2 ... item.level, id: \.self) { i in
                if i % 2 == 0 {
                    ListChildShape(thickness: 1, isHalf: false, upOffset: 20, downOffset: 20, withoutChild: true)
                        .fill(indexColor(for: i))
                        .frame(width: 8)
                        .offset(x: CGFloat((i - 2) * 8))
                }
            }
        }
    }
    
    private func indexColor(for level: Int) -> Color {
        switch level {
        case 1, 2:
            return .primary
        case 3, 4:
            return .yellow
        case 5, 6:
            return .orange
        case 7, 8:
            return .green
        default:
            return .red
        }
    }
    
    private func colorRow(item: ItemRowTreeModel) -> Color {
        guard let index = listController.model.filteredItems.firstIndex(where: { $0.id == item.id }) else { return .clear }
#if os(visionOS)
        if index % 2 == 1 {
            return .clear
        } else {
            return .black.opacity(0.1)
        }
#else
#if !os(macOS)
        guard !listController.model.selectedItems.contains(item) else { return colorScheme == .dark ? .blue.opacity(0.4) : .indigo.opacity(0.8) }
#endif
        if index % 2 == 1 {
            return .clear
        } else {
            return colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.1)
        }
#endif
    }
    
    private var headerView: some View {
        HStack {
#if os(macOS)
            ItemListAddNewButton(listController: listController, canAdd: itemListConfiguration.canAdd)
                .padding(.trailing)
#endif
            headerTitleView
                .font(.headline)
#if !os(macOS)
            Spacer()
#endif
            hideAllView
        }
    }
    
    private var selectionHeaderView: some View {
        HStack {
            Text("Selected - \(listController.model.selectedItems.count)", bundle: .module)
                .font(.headline)
        }
    }
    
    @ViewBuilder
    private var headerTitleView: some View {
#if os(macOS)
        headerTitleLabel
#else
        Button {
            withAnimation { listController.model.isSearching = true }
        } label: {
            Label {
                headerTitleLabel
            } icon: {
                Image(systemName: "text.magnifyingglass")
            }
        }
        .borderLessTVBottonStyle()
#endif
    }

    @ViewBuilder
    private var headerTitleLabel: some View {
        if listController.model.searchToken == listController.model.categoryTags.first {
            Text(listController.model.listTitleName) + Text(" - \(listController.model.filteredItems.count)")
        } else {
            Text(listController.model.searchToken.title) + Text(" - \(listController.model.filteredItems.count)", bundle: .module)
        }
    }

    @ViewBuilder
    private var hideAllView: some View {
        Button {
            withAnimation {
                listController.toggleHide()
            }
        } label: {
            Image(systemName: listController.model.isHiddenItems ? "eye.slash" : "eye")
                .contentTransition(.symbolEffect(.automatic))
        }
        .contentShape(.rect)
    }
}
