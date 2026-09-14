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
            GroupBoxTVWithoutGroupView(content: content, label: label)
#elseif os(macOS)
        if withoutGroup {
            GroupBoxTVWithoutGroupView(content: content, label: label)
        } else {
            GroupBoxTVMacView(isCard: isCard, content: content, label: label)
        }
#else
            GroupBoxTVIosView(content: content, label: label)
#endif
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
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
    }
}

#endif

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct GroupBoxTVWithoutGroupView<Label: View, Content: View>: View {
    let content: () -> Content
    let label: () -> Label

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            label()
                .font(.headline)

            content()

            Divider()
        }
    }
}

#if !os(tvOS)
private struct GroupBoxTVMacView<Label: View, Content: View>: View {
    let isCard: Bool
    let content: () -> Content
    let label: () -> Label

    @ViewBuilder var body: some View {
        if isCard {
            GroupBox(content: content, label: label)
                .groupBoxStyle(CardGroupBoxStyle())
        } else {
            GroupBox(content: content, label: label)
        }
    }
}

private struct GroupBoxTVIosView<Label: View, Content: View>: View {
    let content: () -> Content
    let label: () -> Label

    var body: some View {
        GroupBox(content: { GroupBoxTVContentInsettedView(content: content) }, label: label)
    }
}

private struct GroupBoxTVContentInsettedView<Content: View>: View {
    let content: () -> Content

    var body: some View {
        content().padding(-8)
    }
}
#endif
