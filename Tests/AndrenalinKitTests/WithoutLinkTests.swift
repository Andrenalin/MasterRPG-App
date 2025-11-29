// @copyright André Trettin

import Testing

@testable import CoreRPG

struct WithoutLinkTests {

    @Test(arguments: [
        ("Not a Link", "Not a Link"),
        ("[Not a Link]", "[Not a Link]"),
        ("[Broken Link](", "[Broken Link]("),
        ("[Broken Link])", "[Broken Link])"),
        ("Broken Link](Some)", "Broken Link](Some)"),
        ("[Easy](Some)", "Easy"),
        ("[Easy](Some)-[Easy 2](Some)", "Easy-Easy 2"),
        ("[Hol (sechs)]", "[Hol (sechs)]"),
        ("[Hol (sechs)](RPG://TABLES/0/558DA4B8-54110398CBF3/220F5D16-)", "Hol (sechs)"),
        ("[Hol (sechs)](RPG) [Easy](Some)-[Easy 2](Some)", "Hol (sechs) Easy-Easy 2"),
        ("Hol (sechs)](RPG) [Easy](Some)-[Easy 2](Some)", "Hol (sechs)](RPG) Easy-Easy 2"),
        ("[Hol (sechs)](RPG) [Easy]Some)-[Easy 2](Some)", "Hol (sechs) [Easy]Some)-Easy 2")
    ])
    func bracketsInsideName(what: (sut: String, result: String)) async throws {
        #expect(what.sut.withoutLink() == what.result)
    }
}
