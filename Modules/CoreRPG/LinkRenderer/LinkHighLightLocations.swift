// @copyright André Trettin

import Observation
import SwiftUI

@MainActor @Observable
final class LinkHighLightLocations {
    var locations: [LinkHighLightLocation] = []

    @ObservationIgnored private var updatedLocations: [LinkHighLightLocation] = []

    func update(isStart: Bool) {
        if isStart {
            updatedLocations = []
        } else {
            // Fix #1: Only write (and fire @Observable notifications) when the
            // highlight layout actually changed. Without this guard every text
            // render cycle wrote locations — even when the values were identical —
            // causing DetailEditorView to re-render in a tight loop.
            guard updatedLocations != locations else { return }
            locations = updatedLocations
        }
    }

    func reset(link: LinkReplaceModel, runId: Int, location: CGRect) {
        if let index = updatedLocations.firstIndex(where: { $0.link == link }) {
            var linkLocation = updatedLocations[index]
            if linkLocation.locations.first(where: { $0.runId == runId }) == nil {
                linkLocation.locations.append(LinkLocationCoordinate(id: UUID(), runId: runId, rect: location))
                updatedLocations[index] = linkLocation
            }
        } else {
            let linkLocation = LinkHighLightLocation(id: link.markDown, link: link, locations: [LinkLocationCoordinate(id: UUID(), runId: runId, rect: location)])

            updatedLocations.append(linkLocation)
        }
    }
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

struct LinkLocationCoordinate: Identifiable, Hashable, Equatable {
    let id: UUID
    let runId: Int
    var rect: CGRect
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
