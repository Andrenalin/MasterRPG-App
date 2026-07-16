// @copyright André Trettin

import SwiftUI

struct TokenUsageBar: View {
    let currentTokenCount: Int
    let maxContextSize: Int
    let tokenUsageFraction: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if currentTokenCount > 0 {
            VStack(spacing: 2) {
                ProgressView(value: tokenUsageFraction)
                    .tint(tokenUsageColor)

                HStack {
                    Text("\(currentTokenCount) / \(maxContextSize) tokens", bundle: .module)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(tokenUsageFraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: currentTokenCount)
        }
    }

    private var tokenUsageColor: Color {
        switch tokenUsageFraction {
        case 0..<0.5:
            return .green
        case 0.5..<0.75:
            return .yellow
        case 0.75..<0.9:
            return .orange
        default:
            return .red
        }
    }
}

#Preview {
    TokenUsageBar(currentTokenCount: 4_200, maxContextSize: 8_192, tokenUsageFraction: 0.51)
}
