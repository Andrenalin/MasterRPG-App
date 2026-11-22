// @copyright André Trettin

import CoreRPG
import Foundation

/// The pure part of the text work of a Foundry mapping pass: HTML to plain text for every
/// document and rule description. It runs off the main actor before the model construction, which
/// then only looks the result up (`FoundryMappingState.sanitizedFoundryText`). Link rewriting
/// stays in the mapping pass because it needs the destinations indexed there.
/// See CODE_AUDIT_28 §3.3.
enum FoundryTextPrepass {
    /// The distinct non-empty HTML strings the mapper will turn into plain text.
    static func htmlSources(documents: [FoundryDocument], rulePackage: FoundryRulePackage?) -> [String] {
        var sources: Set<String> = []
        for document in documents {
            if let html = document.descriptionHTML, !html.isEmpty { sources.insert(html) }
        }
        for compendium in rulePackage?.compendiums ?? [] {
            for rule in compendium.rules {
                if let html = rule.descriptionHTML, !html.isEmpty { sources.insert(html) }
            }
        }
        return Array(sources)
    }

    /// Plain text per source string. Stops early when cancelled; the mapper computes whatever is
    /// missing itself.
    @concurrent
    static func plainTexts(of sources: [String]) async -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(sources.count)
        for source in sources {
            if Task.isCancelled { break }
            result[source] = FoundryTextDecoder.plainText(fromHTML: source)
        }
        return result
    }
}
