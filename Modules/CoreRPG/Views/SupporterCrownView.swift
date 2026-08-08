// @copyright André Trettin

import SwiftUI

public struct SupporterCrownView: View {
    public init(tier: SupporterTier) {
        self.tier = tier
    }

    public let tier: SupporterTier

    public var body: some View {
        if tier != .none {
            Image(systemName: "crown.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(highlightColor, baseColor)
                .accessibilityLabel(Text(tier.localizedName))
        }
    }

    private var highlightColor: Color {
        switch tier {
        case .none:
            .clear
        case .bronze:
            Color(red: 0.80, green: 0.48, blue: 0.25)
        case .silver:
            Color(red: 0.82, green: 0.86, blue: 0.91)
        case .gold:
            Color(red: 1.00, green: 0.76, blue: 0.18)
        }
    }

    private var baseColor: Color {
        switch tier {
        case .none:
            .clear
        case .bronze:
            Color(red: 0.42, green: 0.20, blue: 0.09)
        case .silver:
            Color(red: 0.39, green: 0.45, blue: 0.54)
        case .gold:
            Color(red: 0.64, green: 0.38, blue: 0.04)
        }
    }
}

#Preview("Supporter crowns") {
    HStack {
        ForEach(SupporterTier.allCases) { tier in
            SupporterCrownView(tier: tier)
        }
    }
    .padding()
}
