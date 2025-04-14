// @copyright André Trettin

import Observation
import SwiftUI

@Observable
final class LinkHighLightLocations {
    var locations: [LinkHighLightLocation] = []

    func reset(link: LinkReplaceModel, run: String, location: CGRect) {
        if let index = locations.firstIndex(where: { $0.link == link }) {
            var linkLocation = locations[index]
            if linkLocation.locations.first(where: { $0.rect == location }) == nil {
                linkLocation.locations.append(LinkLocationCoordinate(id: UUID(), run: run, rect: location))
                locations[index] = linkLocation
            }
        } else {
            let linkLocation = LinkHighLightLocation(id: link.markDown, link: link, locations: [LinkLocationCoordinate(id: UUID(), run: run, rect: location)])

            locations.append(linkLocation)
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
    let run: String
    var rect: CGRect
}

enum LinkExpandHighLightValues: String {
    case begin = "➡️"
    case end = "⬅️"
    case bold = "*"
    case italic = "-"
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

