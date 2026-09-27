// @copyright André Trettin

import SwiftUI

public struct LinkHighlightTextView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    public init(
        model: LinkHighlightTextModel,
        allowsLinkInteraction: Bool = true
    ) {
        self.model = model
        self.allowsLinkInteraction = allowsLinkInteraction
    }

    let model: LinkHighlightTextModel
    let allowsLinkInteraction: Bool

    public var body: some View {
        ZStack(alignment: .topLeading) {
            overlays(foreground: false)

            Group {
                if accessibilityReduceMotion {
                    plainText
                } else {
                    plainText
                        .id(model.linkToggled)
                }
            }
            .applyIf(model.requiresCustomRenderer) {
                $0.textRenderer(
                    LinkHighlightTextRenderer(
                        model: model,
                        style: .yellow.opacity(0.5),
                        elapsedTime: 1,
                        totalDuration: 1
                    )
                )
            }
            .lineSpacing(4)

            overlays(foreground: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var plainText: Text {
        let _ = model.updated
        // Build one flat LocalizedStringKey with all components as sibling interpolation arguments.
        // Folding components pairwise (via reduce with either `+` or nested string interpolation)
        // builds an N-deep nested Text, and resolving that recurses one stack frame per component —
        // verified to stack-overflow past a few thousand components, which long/link-dense rule
        // descriptions can reach. No localization is needed here either way — components are
        // already-resolved Text values, this is purely a concatenation mechanism.
        let components = model.displayText
        var interpolation = LocalizedStringKey.StringInterpolation(literalCapacity: 0, interpolationCount: components.count)
        for component in components {
            interpolation.appendInterpolation(component.text)
        }
        return Text(LocalizedStringKey(stringInterpolation: interpolation))
    }

    func overlays(foreground: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.linkLocations.locations) { linkLocation in
                ForEach(linkLocation.buttonLocations) { location in
                    overlayView(linkLocation: linkLocation, foreground: foreground)
                        .frame(width: location.rect.width, height: location.rect.height)
                        .offset(x: location.rect.origin.x, y: location.rect.origin.y)
                }
            }
        }
    }

    @ViewBuilder
    func overlayView(linkLocation: LinkHighLightLocation, foreground: Bool) -> some View {
        if foreground {
            if allowsLinkInteraction {
                Button {
                    withAnimation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.8)) {
                        model.handle(link: linkLocation.link)
                    }
                } label: {
                    Color.indigo.opacity(0.01)
                }
                .buttonStyle(.plain)
                .contentShape(.rect)
                .accessibilityLabel(Text(verbatim: linkLocation.link.name))
                .accessibilityHint(Text("Open link", bundle: .module))
#if os(visionOS)
                .buttonStyle(LinkButtonStyle())
                .buttonBorderShape(.roundedRectangle(radius: 4))
#endif
            }
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor.secondary)
        }
    }
}

#Preview {
    @Previewable @State var text: String = "**Mega** nice, in my in but let **[More Values and very long Title](RPG://MAPS/0/\(UUID())) and also Value [inside link](RPG://MAPS/0/2181D9D0-8896-44E0-B2C4-A6E93F2533D7) of** Entry un [Name](RPG://PHOTOS/0/9D877C38-41F5-4595-93A4-C25DC94BDD2E) noch einer **nicinyi.,**and now **"

    @Previewable @State var width: CGFloat = 300

    @Previewable @State var model = LinkHighlightTextModel(linkControllable: FakeLinkController.fake, text: "**Mega** nice, in my in but let **[More Values and very long Title](RPG://MAPS/0/\(UUID())) and also Value [inside link](RPG://MAPS/0/2181D9D0-8896-44E0-B2C4-A6E93F2533D7) of** Entry un [Name](RPG://PHOTOS/0/9D877C38-41F5-4595-93A4-C25DC94BDD2E) noch einer **nicinyi.,**and now **", highlightedText: "in")

    VStack {
        Button {
            withAnimation {
                if width < 120 {
                    width = 600
                } else {
                    width -= 100
                }
            }
        } label: {
            Text(verbatim: "Change width")
        }

        LinkHighlightTextView(model: model)
            .frame(width: width)
            .padding()

        Spacer()
    }
#if os(visionOS)
    .glassBackgroundEffect()
#endif
}
