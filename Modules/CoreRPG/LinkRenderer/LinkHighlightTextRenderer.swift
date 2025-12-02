// @copyright André Trettin

import SwiftUI

struct LinkHighlightTextRenderer: TextRenderer {
    let model: LinkHighlightTextModel

    var elapsedTime: TimeInterval
    var elementDuration: TimeInterval
    var totalDuration: TimeInterval
    var spring: Spring {
        .snappy(duration: elementDuration - 0.05, extraBounce: 0.4)
    }

    var animatableData: Double {
        get { elapsedTime }
        set { elapsedTime = newValue }
    }

    private let style: any ShapeStyle

    init(model: LinkHighlightTextModel, style: any ShapeStyle = .yellow.opacity(0.5), elapsedTime: TimeInterval, elementDuration: Double = 1.5, totalDuration: TimeInterval) {
        self.model = model
        self.style = style
        self.elapsedTime = min(elapsedTime, totalDuration)
        self.elementDuration = min(elementDuration, totalDuration)
        self.totalDuration = totalDuration
    }

    // MARK : - TextRenderer
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        Task { @MainActor in
            model.linkLocations.update(isStart: true)
        }
        for line in layout {
            for run in line {
                if run[SearchHighlightAttribute.self] != nil {
                    let copy = context
                    let rect = run.typographicBounds.rect
                    let shape = RoundedRectangle(cornerRadius: 4, style: .continuous).path(in: rect)
                    copy.fill(shape, with: .style(style))
                    copy.draw(run)
                } else if let link = run[LinkHighlightAttribute.self] {
                    
                    var rect = run.typographicBounds.rect
                    //print("\(link.linkModel.itemId) with \(line.indices) \(run.indices) on \(rect)")
                    rect = CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width + 2, height: rect.height)
                    let location = rect
                    let runId = run.indices.upperBound + 10000 + run.indices.upperBound
                    Task { @MainActor in
                        model.linkLocations.reset(link: link.linkModel, runId: runId, location: location)
                    }
                    context.draw(run)
                } else if let link = run[LinkIconAttribute.self] {
                    var rect = run.typographicBounds.rect
                    rect = CGRect(x: rect.origin.x - 2, y: rect.origin.y - 2, width: rect.width + 2, height: rect.height + 4)
                    let location = rect
                    let runId = run.indices.upperBound + 10000 + run.indices.upperBound
                    Task { @MainActor in
                        model.linkLocations.reset(link: link.linkModel, runId: runId, location: location)
                    }
                    context.draw(run)
                } else if let _ = run[LinkIconExpandedAttribute.self] {
                    context.draw(run)
                } else if let linkExpand = run[LinkExpandedAttribute.self] {
                    let copy = context
                    var rect = run.typographicBounds.rect
                    rect = CGRect(x: rect.origin.x - 2, y: rect.origin.y, width: rect.width + 4, height: rect.height)
                    let shape = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 4, style: .continuous)
                        .path(in: rect)
                    let deep: CGFloat = CGFloat(linkExpand.deep * 5) / 100.0
                    //copy.fill(shape, with: .style(.green.opacity(0.40 - CGFloat(linkExpand.deep * 5))))
                    copy.fill(shape, with: .style(.green.opacity(0.40 - deep)))
                    copy.draw(run)
                    //                let delay = elementDelay(count: run.count)
                    //
                    //                for (index, slice) in run.enumerated() {
                    //                    let timeOffset = TimeInterval(index) * delay
                    //                    let elementTime = max(0, min(elapsedTime - timeOffset, elementDuration))
                    //
                    //                    draw(slice, at: elementTime, in: &copy)
                    //                }
                } else {
                    let copy = context
                    //copy.opacity = UnitCurve.easeIn.value(at: elapsedTime / 0.2)
                    copy.draw(run)
                }
            }
        }
        Task { @MainActor in
            model.linkLocations.update(isStart: false)
        }
    }

    func elementDelay(count: Int) -> TimeInterval {
        let count = TimeInterval(count)
        let remainingTime = totalDuration - count * elementDuration

        return max(remainingTime / (count + 1), (totalDuration - elementDuration) / count)
    }

    func draw(_ slice: Text.Layout.RunSlice, at time: TimeInterval, in context: inout GraphicsContext) {
        let progress = time / elementDuration

        let opacity = UnitCurve.easeIn.value(at: 1.4 * progress)

        let blurRadius =
        slice.typographicBounds.rect.height / 16 *
        UnitCurve.easeIn.value(at: 1 - progress)

        // The y-translation derives from a spring, which requires a
        // time in seconds.
        let translationY = spring.value(
            fromValue: -slice.typographicBounds.descent,
            toValue: 0,
            initialVelocity: 0,
            time: time)

        context.translateBy(x: 0, y: translationY)
        context.addFilter(.blur(radius: blurRadius))
        context.opacity = opacity
        context.draw(slice, options: .disablesSubpixelQuantization)
    }
}
