// @copyright André Trettin

import SwiftUI

/// Simple flow layout for tags
public struct FlowLayout: Layout {
    public init(spacing: CGFloat) {
        self.spacing = spacing
    }
    
    var spacing: CGFloat

    /// The ideal size of every subview, measured once per layout pass: `sizeThatFits` and
    /// `placeSubviews` both need them. See CODE_AUDIT_26 §8.16.
    public struct Cache {
        var sizes: [CGSize]
    }

    public func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        // An unspecified width is "as wide as you need": one line, not a 10 pt column.
        let result = FlowResult(in: proposal.width ?? .infinity, sizes: cache.sizes, spacing: spacing)
        return result.size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let result = FlowResult(in: bounds.width, sizes: cache.sizes, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero

        init(in maxWidth: CGFloat, sizes: [CGSize], spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            var usedWidth: CGFloat = 0

            for size in sizes {
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                usedWidth = max(usedWidth, x + size.width)
                x += size.width + spacing
            }

            // The width the lines use, not the proposal: a proposal of `.infinity` cannot be reported.
            self.size = CGSize(width: usedWidth, height: y + lineHeight)
        }
    }
}
