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
        Text(verbatim: "Inside")
    } label: {
        Text(verbatim: "Header")
    }
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
