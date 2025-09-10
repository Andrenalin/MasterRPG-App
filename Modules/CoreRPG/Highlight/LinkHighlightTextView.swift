// @copyright André Trettin

import SwiftUI

public struct LinkHighlightTextView: View {
    public init(model: LinkHighlightTextModel) {
        self.model = model
    }

    let model: LinkHighlightTextModel
#if os(iOS)
    @Environment(DeviceRotationModel.self) private var deviceRotationModel
#endif

    public var body: some View {
        ZStack(alignment: .topLeading) {
            overlays(foreground: false)

            let text = model.displayText.reduce(Text("")) {
                partialResult, component in
                return partialResult + component.text
            }
            text
                .textRenderer(LinkHighlightTextRenderer(model: model, style: .yellow.opacity(0.5), elapsedTime: 2, totalDuration: 2))
                .lineSpacing(4)
                .transition(OnboardingTextTransition(model: model))

            overlays(foreground: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width.rounded()
        } action: { oldValue, newValue in
            if model.recordedWidth != newValue {
                withAnimation { model.resetLocations() }
            }
            model.recordedWidth <=> newValue
        }
#if os(iOS)
        .onChange(of: deviceRotationModel.orientation) {
            Task { @MainActor in
                await Task.yield()
                model.resetLocations(force: true)
            }
        }
#endif
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
            Button {
                withAnimation(.easeInOut(duration: 1)) {
                    model.handle(link: linkLocation.link)
                }
            } label: {
                Color.indigo.opacity(0.01)
            }
            .buttonStyle(.plain)
            .contentShape(.rect)
#if os(visionOS)
            .buttonStyle(LinkButtonStyle())
            .buttonBorderShape(.roundedRectangle(radius: 4))
#endif
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor.secondary)
        }
    }
}

#Preview {
    @Previewable @State var text: String = "**Mega** nice, in my in but let **[More Values and very long Title](RPG://MAPS/0/\(UUID())) and also Value [inside link](RPG://MAPS/0/2181D9D0-8896-44E0-B2C4-A6E93F2533D7) of** Entry un [Name](RPG://PHOTOS/0/9D877C38-41F5-4595-93A4-C25DC94BDD2E) noch einer **nicinyi.,**and now **"

    @Previewable @State var width: CGFloat = 300

    @Previewable @State var model = LinkHighlightTextModel(linkController: LinkRegisterController.fake, text: "**Mega** nice, in my in but let **[More Values and very long Title](RPG://MAPS/0/\(UUID())) and also Value [inside link](RPG://MAPS/0/2181D9D0-8896-44E0-B2C4-A6E93F2533D7) of** Entry un [Name](RPG://PHOTOS/0/9D877C38-41F5-4595-93A4-C25DC94BDD2E) noch einer **nicinyi.,**and now **", highlightedText: "in")

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
            Text("Change width")
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
