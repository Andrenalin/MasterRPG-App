// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_28 §5.10: a name with balanced square brackets ("Dragon [Ancient]") was written raw
/// into `[name](address)`; neither the link pattern nor the reference scanner matched it.
@Suite("Links with brackets in the name")
@MainActor
struct BracketedLinkNameTests {
    private let itemId = UUID()
    private let entryId = UUID()

    @Test("The builder escapes the brackets and the labels read them back")
    func builderRoundTrip() {
        let link = LinkBuilder.markdown(name: "Dragon [Ancient]", module: .value, itemId: itemId)

        #expect(LinkBuilder.labels(in: "See \(link) now") == "See Dragon [Ancient] now")
        #expect(link.contains(#"Dragon \[Ancient\]"#))
    }

    @Test("A bracketed name is found as a link of the item")
    func scannerFindsBracketedName() {
        let link = LinkBuilder.markdown(name: "Dragon [Ancient]", module: .value, itemId: itemId, entryId: entryId)

        let found = LinkReplaceController.links(for: "Fight \(link)!")

        #expect(found.count == 1)
        #expect(found.first?.itemId == itemId)
        #expect(found.first?.entryId == entryId)
        #expect(found.first?.name == "Dragon [Ancient]")
    }

    @Test("Backslashes in a name survive the round trip")
    func backslashRoundTrip() {
        let link = LinkBuilder.markdown(name: #"Path\to [x]"#, module: .photo, itemId: itemId)

        #expect(LinkBuilder.labels(in: link) == #"Path\to [x]"#)
        #expect(LinkReplaceController.links(for: link).first?.name == #"Path\to [x]"#)
    }

    @Test("A plain name is unchanged")
    func plainNameUnchanged() {
        #expect(LinkBuilder.escapedLabel("Goblin") == "Goblin")
        #expect(LinkBuilder.unescapedLabel("Goblin") == "Goblin")
    }
}
