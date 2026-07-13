// @copyright André Trettin

import SwiftUI

public struct GroupBoxTV<Label: View, Content: View>: View {
    let isCard: Bool
    let withoutGroup: Bool
    let content: () -> Content
    let label: () -> Label

    public init(isCard: Bool = false, withoutGroup: Bool = false, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.isCard = isCard
        self.withoutGroup = withoutGroup
        self.content = content
        self.label = label
    }

    public var body: some View {
#if os(tvOS)
            withoutGroupView
#elseif os(macOS)
        if withoutGroup {
            withoutGroupView
        } else {
            macView
        }
#else
            iosView
#endif
    }
    
    private var withoutGroupView: some View {
        VStack(alignment: .leading, spacing: 20) {
            label()
                .font(.headline)
            
            content()
            
            Divider()
        }
    }
    
#if !os(tvOS)
    @ViewBuilder
    private var macView: some View {
        if isCard {
            GroupBox(content: content, label: label)
                .groupBoxStyle(CardGroupBoxStyle())
        } else {
            GroupBox(content: content, label: label)
        }
    }
    
    private var iosView: some View {
        GroupBox(content: { contentInsettedView }, label: label)
    }
    
#endif
    
    private var contentInsettedView: some View {
        content().padding(-8)
    }
}

#Preview {
    GroupBoxTV {
        Text("Inside")
    } label: {
        Text("Header")
    }
}

#Preview("Disclosure group") {
    @Previewable @State var isExpanded = true
    DisclosureGroupTV(isExpanded: $isExpanded) {
        Text("The party has entered the dungeon.")
    } label: {
        Label("Adventure notes", systemImage: "book.closed")
    }
    .padding()
}

#Preview("Menu") {
    MenuTV {
        Button("Edit", action: {})
        Button("Duplicate", action: {})
    } label: {
        Label("Actions", systemImage: "ellipsis.circle")
    }
    .padding()
}

#if !os(tvOS)
struct CardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.label
            configuration.content.padding(-12)
        }
        .padding(4)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#endif

public struct DisclosureGroupTV<Label: View, Content: View>: View {
    @Binding public var isExpanded: Bool
    public let content: () -> Content
    public let label: () -> Label
    private let hasExpanded: Bool

    public init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.content = content
        self.label = label
        hasExpanded = false
        _isExpanded = .constant(false)
    }

    public init(isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.content = content
        self.label = label
        hasExpanded = true
        _isExpanded = isExpanded
    }

    public var body: some View {
        #if os(tvOS)
            Group {
                label()
                content()
            }
        #else
            if hasExpanded {
                DisclosureGroup(isExpanded: $isExpanded, content: content, label: label)
            } else {
                DisclosureGroup(content: content, label: label)
            }
        #endif
    }
}

public struct MenuTV<Label: View, Content: View>: View {
    public let content: () -> Content
    public let label: () -> Label
    public let primaryAction: (() -> Void)?

    public init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label, primaryAction: (() -> Void)? = nil) {
        self.content = content
        self.label = label
        self.primaryAction = primaryAction
    }

    public var body: some View {
        #if os(tvOS)
            HStack(spacing: 16) {
                content()
            }
        #else
            if let primaryAction {
                Menu(content: content, label: label, primaryAction: primaryAction)
            } else {
                Menu(content: content, label: label)
            }
        #endif
    }
}
