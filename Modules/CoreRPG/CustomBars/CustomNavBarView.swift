// @copyright André Trettin

import SwiftUI

#Preview("Custom navigation bar") {
    CustomNavBarView({
        Text(verbatim: "Adventure")
    }, content: {
        List {
            Text(verbatim: "Goblin ambush")
            Text(verbatim: "Hidden temple")
        }
    }, leading: { EmptyView() }, trailing: { EmptyView() }, background: { EmptyView() })
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
