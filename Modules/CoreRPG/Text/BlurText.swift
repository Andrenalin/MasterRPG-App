// @copyright André Trettin

import SwiftUI

#Preview {
    BlurText(text: "Critical hit!", color: .red, animates: false)
        .padding()
}

public struct BlurText: View {
    public init(text: String, color: Color, animates: Bool = true) {
        self.text = text
        self.color = color
        self.animates = animates
        self._shown = State(initialValue: !animates)
    }
    
    public let text: String
    public let color: Color
    private let animates: Bool
    
    @State private var shown: Bool
    
    public var body: some View {
        Group {
            if shown {
                Text(text)
                    .bold()
                    .customAttribute(BlurAttribute())
                    .customAttribute(OnboardingEmphasisAttribute())
                    .transition(OnboardingNameTransition())
                    .gradientForeground(colors: [.red, .green, .blue])
            }
        }
        .onChange(of: shown, initial: true) {
            guard animates else { return }
            Task {
                let wait = shown ? 10 : 2
                try? await Task.sleep(for: .seconds(wait))
                shown.toggle()
            }
        }
    }
}

struct BlurAttribute: TextAttribute {}

struct BlurEffect: TextRenderer {
  func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
    for run in layout.flattenedRuns {
      if run[BlurAttribute.self] != nil {
        // Apply a blur effect to Run with BlurAttribute
        var blurContext = ctx
        let radius = run.typographicBounds.rect.height / 5
        blurContext.addFilter(.blur(radius: radius))
        blurContext.draw(run)
      }
      // Draw all Run, whether blurred or not
      ctx.draw(run)
    }
  }
}


extension View {
    public func gradientForeground(colors: [Color]) -> some View {
        self.overlay(
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
        )
            .mask(self)
    }
}
