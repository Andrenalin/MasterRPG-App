// @copyright André Trettin

import SwiftUI

struct CustomNavBarInternalView<Title: View, Leading: View, Trailing: View, Background: View>: View {
    let title: () -> Title
    let leading: () -> Leading
    let trailing: () -> Trailing
    let navBackground: () -> Background

    var titleText: String? = nil
    var searchPrompt: String? = nil

    @Binding private var externalSearchText: String

    @State private var isEditing = false
    @State private var isSearching = false

    private var hasFilter = false
    @State private var isFiltering = false
    @Binding private var externalSelectedFilter: [TagFilterSelection]
    private var filters: [String] = []
    @Binding private var offset: CGFloat

    init(@ViewBuilder _ title: @escaping () -> Title, @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder background: @escaping () -> Background, offset: Binding<CGFloat>) {
        self.title = title
        self.leading = leading
        self.trailing = trailing
        navBackground = background
        _externalSearchText = .constant("")
        _externalSelectedFilter = .constant([])
        _offset = offset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                leading()

                if let titleText {
                    NavBarTitleView(title: titleText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    title()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                trailing()
            }
        }
        .padding(8)
        .background(navBackground())
    }

    func updateOffset() {
        if isSearching && isFiltering {
            offset <=> 84
        } else if isSearching {
            offset <=> 44
        } else {
            offset <=> 0
        }
    }
}

extension CustomNavBarInternalView where Title == EmptyView {
    init(titleText: String, searchPrompt: String? = nil, selectedFilters: Binding<[TagFilterSelection]>? = nil, filters: [String] = [], @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder background: @escaping () -> Background, offset: Binding<CGFloat>) {
        title = { EmptyView() }
        self.titleText = titleText
        self.leading = leading
        self.trailing = trailing
        navBackground = background
        self.searchPrompt = searchPrompt
        _externalSearchText = .constant("")

        if let selectedFilters {
            _externalSelectedFilter = selectedFilters
            self.filters = filters
            hasFilter = !filters.isEmpty
        } else {
            _externalSelectedFilter = .constant([])
        }

        _offset = offset
    }
}

#Preview("Navigation bar internals") {
    @Previewable @State var offset: CGFloat = 0
    CustomNavBarInternalView({
        Text(verbatim: "Adventure")
    }, leading: {
        Image(systemName: "chevron.left")
    }, trailing: {
        Image(systemName: "ellipsis")
    }, background: {
        Color.blue.opacity(0.2)
    }, offset: $offset)
}
