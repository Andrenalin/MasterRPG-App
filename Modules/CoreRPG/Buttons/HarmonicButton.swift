// @copyright André Trettin

import SwiftUI

public struct HarmonicButton: View {
    public init(animates: Bool = true) {
      self.animates = animates
    }

  private let animates: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public var body: some View {
    Button(
      action: {},
      label: {}
    )
    .frame(width: 240.0, height: 70.0)
    .buttonStyle(HarmonicStyle(animates: animates && !reduceMotion))
    .accessibilityHidden(true)
  }
}

#Preview {
    HarmonicButton(animates: false)
}

struct HarmonicStyle: ButtonStyle {
  let animates: Bool

  @State private var scale: CGFloat = 1.0

  @State private var speedMultiplier: Double = 1.0
  @State private var amplitude: Float = 0.5

  @State private var elapsedTime: Double = 0.0
  private let updateInterval: Double = 0.016
  
  func makeBody(configuration: Configuration) -> some View {
    TimelineView(.animation(minimumInterval: updateInterval / speedMultiplier, paused: !animates)) { context in
      configuration.label
        .spatialWrap(Capsule(), lineWidth: 1.0)
        .background {
          Rectangle()
                .colorEffect(ShaderLibrary.bundle(.module).harmonicColorEffect(
              .boundingRect, // bounding rect
              .float(6), // waves count,
              .float(elapsedTime), // animation clock
              .float(amplitude), // amplitude
              .float(configuration.isPressed ? 1.0 : 0.0) // monochrome coeff
            ))
        }
        .clipShape(Capsule())
        .scaleEffect(scale)
        .onChange(of: context.date) { _, _ in
          guard animates else { return }
          elapsedTime += updateInterval * speedMultiplier
        }
    }
    .onChange(of: configuration.isPressed) { _, newValue in
      withAnimation(animates ? .spring(duration: 0.3) : nil) {
        amplitude = newValue ? 2.0 : 0.5
        speedMultiplier = newValue ? 2.0 : 1.0
        scale = newValue ? 0.95 : 1.0
      }
    }
      #if !os(visionOS)
    .sensoryFeedback(.impact, trigger: configuration.isPressed)
      #endif
  }
}

extension View {
  @ViewBuilder
  func spatialWrap(
    _ shape: some InsettableShape,
    lineWidth: CGFloat
  ) -> some View {
    self
      .background {
        shape
          .strokeBorder(
            LinearGradient(
              gradient: Gradient(stops: [
                .init(color: .white.opacity(0.4), location: 0.0),
                .init(color: .white.opacity(0.0), location: 0.4),
                .init(color: .white.opacity(0.0), location: 0.6),
                .init(color: .white.opacity(0.1), location: 1.0),
              ]),
              startPoint: .init(x: 0.16, y: -0.4),
              endPoint: .init(x: 0.2, y: 1.5)
            ),
            style: .init(lineWidth: lineWidth)
          )
      }
  }
}
