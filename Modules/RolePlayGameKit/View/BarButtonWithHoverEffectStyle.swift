// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import SwiftUI

struct BarButtonWithHoverEffectStyle: ButtonStyle {
    let isSelected: Bool
    let hoverGroup: HoverEffectGroup?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var hoverEffectNamespace

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(10)
            .background {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.thinMaterial)
                        .hoverEffect(reduceMotion ? HoverEffect(FadeEffect()) : HoverEffect(.empty), in: hoverGroup)
                        .hoverEffect(.highlight)

                    if reduceMotion {
                        Circle()
                            .fill(.thinMaterial)
                            .hoverEffect(.highlight)
                            .hoverEffect(FadeEffect(from: 1, to: 0), in: hoverGroup)
                    }
                }
                .hoverEffect(in: HoverEffectGroup(hoverEffectNamespace)) { effect, isActive, proxy in
                    effect.opacity(isActive ? 1 : (isSelected ? 1 : 0.0))
                }
            }
            .hoverEffect()
            .hoverEffect(.highlight)
            .hoverEffect(reduceMotion ? HoverEffect(.empty) : HoverEffect(ExpandEffect()), in: hoverGroup)
    }
}

struct ExpandEffect: CustomHoverEffect {
    func body(content: Content) -> some CustomHoverEffect {
        content.hoverEffect { effect, isActive, proxy in
            effect.animation(.default.delay(isActive ? 0.8 : 0.2)) {
                $0.clipShape(.rect(cornerRadius: 28, style: .continuous).size(
                    width: isActive ? proxy.size.width : proxy.size.height,
                    height: proxy.size.height, anchor: .leading)
                )
                .scaleEffect(isActive ? 1.05 : 1.0)
            }
        }
    }
}

struct FadeEffect: CustomHoverEffect {
    var from: Double = 0
    var to: Double = 1

    func body(content: Content) -> some CustomHoverEffect {
        content.hoverEffect { effect, isActive, _ in
            effect.animation(.default.delay(isActive ? 0.8 : 0.2)) {
                $0.opacity(isActive ? to : from)
            }
        }
    }
}
#endif
