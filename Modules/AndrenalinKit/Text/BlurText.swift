// @copyright André Trettin

import SwiftUI

public struct BlurText: View {
    public init(text: String, color: Color) {
        self.text = text
        self.color = color
    }
    
    public let text: String
    public let color: Color
    
    @State private var shown = false
    
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
            Task {
                let wait = shown ? 10 : 2
                try await Task.sleep(for: .seconds(wait))
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
