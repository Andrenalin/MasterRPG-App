// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

/// `DiceEntity.urlRepresentation` (Modules/DiceRPG/Intent/DiceEntity.swift) must hardcode its
/// scheme/module-token literal — `URLRepresentation`'s string-interpolation template only
/// accepts KeyPath-based placeholders (like `.id`), not an arbitrary runtime `String`, so it
/// can't be composed from `URL.appScheme`/`NetworkModules.dice.token` the way every other
/// link-construction site in the codebase is. This test is the safeguard in place of that
/// composition: if either constant ever changes, this fails and flags the now-stale literal
/// for a matching hand-edit, instead of the Shortcuts/Spotlight entry point silently drifting
/// out of sync. See CODE_AUDIT §9.13.
struct DiceEntityURLRepresentationTests {
    @Test func schemeMatchesDiceEntityURLRepresentationLiteral() {
        #expect(URL.appScheme == "RPG")
    }

    @Test func diceTokenMatchesDiceEntityURLRepresentationLiteral() {
        #expect(NetworkModules.dice.token == "DICE")
    }
}
