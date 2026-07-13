// @copyright André Trettin

import SwiftUI

#Preview("Custom navigation bar") {
    CustomNavBarView({
        Text("Adventure")
    }, content: {
        List {
            Text("Goblin ambush")
            Text("Hidden temple")
        }
    }, leading: { EmptyView() }, trailing: { EmptyView() }, background: { EmptyView() })
}

#Preview("Navigation bar internals") {
    @Previewable @State var offset: CGFloat = 0
    CustomNavBarInternalView({
        Text("Adventure")
    }, leading: {
        Image(systemName: "chevron.left")
    }, trailing: {
        Image(systemName: "ellipsis")
    }, background: {
        Color.blue.opacity(0.2)
    }, offset: $offset)
}

public struct CustomNavBarView<Title: View, Content: View, Leading: View, Trailing: View, Background: View>: View {
    let content: () -> Content
    let navSearch: (Binding<CGFloat>) -> CustomNavBarInternalView<Title, Leading, Trailing, Background>

    @State private var offset: CGFloat = 0

    public init(@ViewBuilder _ title: @escaping () -> Title, @ViewBuilder content: @escaping () -> Content, @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder background: @escaping () -> Background) {
        self.content = content
        navSearch = { offset in
            CustomNavBarInternalView(title, leading: leading, trailing: trailing, background: background, offset: offset)
        }
    }

    public var body: some View {
        VStack(spacing: 4) {
            content()
                .padding([.vertical], -8)
                .offset(y: offset)
                .rainbowDebug()
        }
        .rainbowDebug()
        .safeAreaInset(edge: .top) {
            navSearch($offset)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: safeInset)
        }
        #if os(iOS) || os(visionOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var safeInset: CGFloat {
        ((offset - 8) > 0) ? (offset - 8) : 0
    }
}

public extension CustomNavBarView where Title == EmptyView {
    init(title: String, searchPrompt: String? = nil, selectedFilters: Binding<[TagFilterSelection]>? = nil, filters: [String] = [], @ViewBuilder content: @escaping () -> Content, @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder background: @escaping () -> Background) {
        self.content = content

        navSearch = { offset in CustomNavBarInternalView(titleText: title, searchPrompt: searchPrompt, selectedFilters: selectedFilters, filters: filters, leading: leading, trailing: trailing, background: background, offset: offset) }
    }
}

public extension CustomNavBarView where Background == EmptyView {
    init(@ViewBuilder _ title: @escaping () -> Title, @ViewBuilder content: @escaping () -> Content, @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.content = content
        navSearch = { offset in CustomNavBarInternalView(title, leading: leading, trailing: trailing, background: { EmptyView() }, offset: offset) }
    }
}

public extension CustomNavBarView where Leading == EmptyView {
    init(@ViewBuilder _ title: @escaping () -> Title, @ViewBuilder content: @escaping () -> Content, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder background: @escaping () -> Background) {
        self.content = content
        navSearch = { offset in CustomNavBarInternalView(title, leading: { EmptyView() }, trailing: trailing, background: background, offset: offset) }
    }
}

public extension CustomNavBarView where Trailing == EmptyView {
    init(@ViewBuilder _ title: @escaping () -> Title, @ViewBuilder content: @escaping () -> Content, @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder background: @escaping () -> Background) {
        self.content = content
        navSearch = { offset in CustomNavBarInternalView(title, leading: leading, trailing: { EmptyView() }, background: background, offset: offset) }
    }
}

public extension CustomNavBarView where Leading == EmptyView, Background == EmptyView {
    init(@ViewBuilder _ title: @escaping () -> Title, @ViewBuilder content: @escaping () -> Content, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.content = content
        navSearch = { offset in CustomNavBarInternalView(title, leading: { EmptyView() }, trailing: trailing, background: { EmptyView() }, offset: offset) }
    }
}

public extension CustomNavBarView where Trailing == EmptyView, Background == EmptyView {
    init(@ViewBuilder _ title: @escaping () -> Title, @ViewBuilder content: @escaping () -> Content, @ViewBuilder leading: @escaping () -> Leading) {
        self.content = content
        navSearch = { offset in CustomNavBarInternalView(title, leading: leading, trailing: { EmptyView() }, background: { EmptyView() }, offset: offset) }
    }
}

public extension CustomNavBarView where Leading == EmptyView, Trailing == EmptyView {
    init(@ViewBuilder _ title: @escaping () -> Title, @ViewBuilder content: @escaping () -> Content, @ViewBuilder background: @escaping () -> Background) {
        self.content = content
        navSearch = { offset in CustomNavBarInternalView(title, leading: { EmptyView() }, trailing: { EmptyView() }, background: background, offset: offset) }
    }
}

public extension CustomNavBarView where Leading == EmptyView, Trailing == EmptyView, Background == EmptyView {
    init(@ViewBuilder _ title: @escaping () -> Title, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        navSearch = { offset in CustomNavBarInternalView(title, leading: { EmptyView() }, trailing: { EmptyView() }, background: { EmptyView() }, offset: offset) }
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
        .background(
            navBackground()
        )
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
