// @copyright André Trettin

import Observation
import SwiftUI

@MainActor @Observable
final class LinkHighLightLocations {
    var locations: [LinkHighLightLocation] = []

    func replace(with measurements: [LinkLayoutMeasurement]) {
        var updatedLocations: [LinkHighLightLocation] = []
        for measurement in measurements {
            if let index = updatedLocations.firstIndex(where: { $0.link == measurement.link }) {
                var linkLocation = updatedLocations[index]
                if linkLocation.locations.first(where: { $0.runId == measurement.runId }) == nil {
                    linkLocation.locations.append(
                        LinkLocationCoordinate(
                            id: UUID(),
                            runId: measurement.runId,
                            rect: measurement.rect
                        )
                    )
                    updatedLocations[index] = linkLocation
                }
            } else {
                updatedLocations.append(
                    LinkHighLightLocation(
                        id: measurement.link.markDown,
                        link: measurement.link,
                        locations: [
                            LinkLocationCoordinate(
                                id: UUID(),
                                runId: measurement.runId,
                                rect: measurement.rect
                            )
                        ]
                    )
                )
            }
        }

        guard updatedLocations != locations else { return }
        locations = updatedLocations
    }
}

struct LinkLayoutMeasurement: Sendable, Equatable {
    let link: LinkReplaceModel
    let runId: Int
    let rect: CGRect
}

struct LinkHighLightLocation: Identifiable, Equatable, Hashable {
    let id: String
    let link: LinkReplaceModel
    var locations: [LinkLocationCoordinate]

    var buttonLocations: [LinkLocationCoordinate] {
        guard !locations.isEmpty else { return [] }
        var lastLocation: LinkLocationCoordinate = locations[0]
        var result: [LinkLocationCoordinate] = []
        for location in locations.dropFirst() {
            let nextX = lastLocation.rect.origin.x + lastLocation.rect.width
            if location.rect.origin.x > nextX - 1 && location.rect.origin.x < nextX + 1 {
                lastLocation.rect = CGRect(
                    x: lastLocation.rect.minX,
                    y: min(lastLocation.rect.minY, location.rect.minY),
                    width: lastLocation.rect.width + location.rect.width,
                    height: max(lastLocation.rect.height, location.rect.height)
                )
            } else {
                result.append(lastLocation)
                lastLocation = location
            }
        }
        result.append(lastLocation)
        return result
    }
}

struct LinkLocationCoordinate: Identifiable, Hashable {
    let id: UUID
    let runId: Int
    var rect: CGRect

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.runId == rhs.runId && lhs.rect == rhs.rect
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(runId)
        hasher.combine(rect.origin.x)
        hasher.combine(rect.origin.y)
        hasher.combine(rect.size.width)
        hasher.combine(rect.size.height)
    }
}

enum LinkExpandHighLightValues: String {
    case begin = "➡️"
    case end = "⬅️"
    case bold = "*"
    case italic = "-"
    case space = " "
}

struct LinkExpandedAttribute: TextAttribute {
    let deep: Int
}

struct LinkIconExpandedAttribute: TextAttribute {
    let isStart: Bool
}

struct LinkHighlightAttribute: TextAttribute {
    let linkModel: LinkReplaceModel
}

struct LinkIconAttribute: TextAttribute {
    let linkModel: LinkReplaceModel
}

struct SearchHighlightAttribute: TextAttribute {}

struct HighlightedTextComponent {
    let text: Text
    let string: String
    let range: Range<String.Index>

    func debugDescription() -> String {
        string
    }
}
