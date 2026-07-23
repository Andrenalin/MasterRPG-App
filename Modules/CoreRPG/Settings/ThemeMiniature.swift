// @copyright André Trettin

import SwiftUI

struct ThemeMiniature: View {
    let theme: ResolvedAppTheme

    private let modules: [NetworkModules] = [
        .adventure,
        .audio,
        .value,
        .dice,
        .map
    ]

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.secondaryForegroundColor)
                    .frame(width: 28, height: 5)

                ForEach(modules, id: \.self) { module in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.tint(for: module))
                        .frame(width: module.previewWidth, height: 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 5) {
                Circle()
                    .fill(theme.accentColor)
                Circle()
                    .fill(theme.tint(for: .photo))
                Circle()
                    .fill(theme.tint(for: .table))
            }
            .frame(width: 12)
        }
        .padding(10)
        .background(theme.backgroundGradient)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.secondaryForegroundColor.opacity(0.35))
        }
        .clipShape(.rect(cornerRadius: 12))
    }
}

private extension NetworkModules {
    var previewWidth: CGFloat {
        switch self {
        case .adventure: 52
        case .audio: 42
        case .value: 60
        case .dice: 46
        default: 56
        }
    }
}
