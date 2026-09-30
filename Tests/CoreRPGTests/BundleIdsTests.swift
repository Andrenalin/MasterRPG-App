// @copyright André Trettin

import Foundation
import Testing
import UniformTypeIdentifiers

@testable import CoreRPG

/// CODE_AUDIT_18 §9.17: identifiers composed from `BundleIds` are registered externally and must
/// stay byte-identical to the literals they replaced.
@Suite("Bundle identifiers")
struct BundleIdsTests {
    @Test("Composed identifiers match their registered values")
    func composedIdentifiersAreUnchanged() {
        #expect(UserDefaults.appGroupString == "group.de.andretrettin.MasterRPG")
        #expect(FileManager.cloudContainerIdentifier == "iCloud.de.andretrettin.gamemaster")
        #expect(BundleIds.app("joinCode") == "de.andretrettin.MasterRPG.joinCode")
        #expect(BundleIds.app("play-rpg-together") == "de.andretrettin.MasterRPG.play-rpg-together")
        #expect("\(BundleIds.achievement).first_game" == "de.andretrettin.masterrpg.achievement.first_game")
        #expect(UTType.adventureLink.identifier == "de.andretrettin.MasterRPG.Link.Adventure")
        #expect(UTType.entryLink.identifier == "de.andretrettin.MasterRPG.Link.Entry")
        // CODE_AUDIT_19 §9.6: the legacy spelling of the document and Handoff types.
        #expect(UTType.rpgDocument.identifier == "de.AndreTrettin.GameMaster.gmz")
        #expect(UTType.gmsDocument.identifier == "de.AndreTrettin.GameMaster.gms")
        #expect(UserActivity.bundleIdentifierType == "de.AndreTrettin.GameMaster.Activity.Detail")
    }
}
