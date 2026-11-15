// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §6.1: a hostile `template.json` must not hang or crash the import.
@Suite("Foundry template decoder")
struct FoundryTemplateDecoderTests {
    private func template(named templates: [String: [String]], types: [String: [String]] = ["character": ["base"]]) -> FoundryJSONValue {
        var templateObjects: [String: FoundryJSONValue] = [:]
        for (name, parents) in templates {
            templateObjects[name] = .object([
                "templates": .array(parents.map { .string($0) }),
                "field_\(name)": .integer(1),
            ])
        }
        var actor: [String: FoundryJSONValue] = [
            "types": .array(types["character"]!.map { .string($0) }),
            "templates": .object(templateObjects),
        ]
        for subtype in types["character"]! {
            actor[subtype] = .object(["templates": .array(templates.keys.sorted().prefix(1).map { .string($0) })])
        }
        return .object(["Actor": .object(actor)])
    }

    @Test("A diamond-shaped chain with exponentially many paths resolves once per template")
    func diamondChainIsLinear() throws {
        // t_i lists [t_{i+1}, u_{i+1}] and u_{i+1} lists [t_{i+2}]: the number of paths from t_0
        // grows like Fibonacci, and `deduplicated` cannot collapse it. Without a memo table this
        // is millions of merges; with one it is two per level.
        let levels = 30
        func name(_ prefix: String, _ level: Int) -> String { "\(prefix)\(String(format: "%02d", level))" }
        var templates: [String: [String]] = [:]
        for level in 0..<levels {
            templates[name("t", level)] = [name("t", level + 1), name("u", level + 1)]
            templates[name("u", level + 1)] = [name("t", level + 2)]
        }
        templates[name("t", levels)] = []
        templates[name("t", levels + 1)] = []

        let schemas = try FoundryTemplateDecoder().decode(template(named: templates))

        #expect(schemas.count == 1)
        let expectedField = "field_t\(levels)"
        let hasField = schemas[0].fields.contains { field in field.path.hasSuffix(expectedField) }
        #expect(hasField)
    }

    @Test("Inheritance deeper than the cap is rejected instead of recursing")
    func deepChainIsRejected() {
        var templates: [String: [String]] = [:]
        let depth = FoundryTemplateDecoder.maximumInheritanceDepth + 10
        for level in 0..<depth {
            templates["t\(String(format: "%04d", level))"] = ["t\(String(format: "%04d", level + 1))"]
        }
        templates["t\(String(format: "%04d", depth))"] = []

        #expect(throws: FoundryImportError.self) {
            try FoundryTemplateDecoder().decode(template(named: templates))
        }
    }

    @Test("A real cycle is still reported")
    func cycleIsRejected() {
        #expect(throws: FoundryImportError.self) {
            try FoundryTemplateDecoder().decode(template(named: ["a": ["b"], "b": ["a"]]))
        }
    }

    @Test("A repeated template name is merged once, at its last position")
    func duplicatesCollapseToTheLastOccurrence() {
        #expect(FoundryTemplateDecoder.deduplicated(["a", "b", "a", "c", "b"]) == ["a", "c", "b"])
    }
}
