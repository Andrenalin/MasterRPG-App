// @copyright André Trettin

import Foundation

// Split out of ExternalImportSourceRegistry.swift — see CODE_AUDIT_19 §9.23.

extension ExternalImportSourceRegistry {
    static func resolve(
        _ descriptor: ExternalImportSourceDescriptor,
        among entries: [ExternalImportSourceEntry],
        aliases: SourceAliases,
        newCopyScopeID: UUID = UUID()
    ) -> ExternalImportSourceResolution {
        let compatible = entries.filter { isCompatible($0, with: descriptor) }

        if let intrinsicScopeID = descriptor.intrinsicScopeID {
            // A copied Foundry world can retain the bridge instance ID. Explicit aliases make each
            // user-created scope a durable candidate; physical aliases decide between candidates.
            let reassignedMatches = compatible.filter { $0.intrinsicScopeAlias == intrinsicScopeID }
            let implicitMatches = compatible.filter { $0.scopeID == intrinsicScopeID }
            let intrinsicMatches = mergingByScope(implicitMatches, reassignedMatches)
            guard !intrinsicMatches.isEmpty else { return .resolved(scopeID: intrinsicScopeID) }

            let exactFiles = exactFileMatches(in: intrinsicMatches, aliases: aliases)
            if let resolution = resolution(
                forExactMatches: exactFiles,
                proposedScopeID: newCopyScopeID
            ) {
                return resolution
            }

            let pathMatches = intrinsicMatches.filter { $0.lastKnownPathAlias == aliases.path }
            if let resolution = resolution(
                forExactMatches: pathMatches,
                proposedScopeID: newCopyScopeID
            ) {
                return resolution
            }

            if intrinsicMatches.count == 1,
               descriptor.semanticMatchPolicy == .automatic,
               let match = intrinsicMatches.first {
                return .resolved(scopeID: match.scopeID)
            }
            return .requiresSelection(
                existing: sorted(intrinsicMatches),
                proposedScopeID: newCopyScopeID
            )
        }

        let fileMatches = exactFileMatches(in: compatible, aliases: aliases)
        if let resolution = resolution(forExactMatches: fileMatches, proposedScopeID: newCopyScopeID) {
            return resolution
        }

        let pathMatches = compatible.filter { $0.lastKnownPathAlias == aliases.path }
        if !pathMatches.isEmpty {
            if descriptor.semanticMatchPolicy == .automatic,
               let resolution = resolution(forExactMatches: pathMatches, proposedScopeID: newCopyScopeID) {
                return resolution
            }
            return .requiresSelection(existing: sorted(pathMatches), proposedScopeID: newCopyScopeID)
        }

        let semanticMatches: [ExternalImportSourceEntry]
        if let semanticKey = descriptor.semanticKey {
            semanticMatches = compatible.filter { $0.semanticKey == semanticKey }
        } else {
            semanticMatches = []
        }
        if descriptor.semanticMatchPolicy == .automatic, semanticMatches.count == 1,
           let match = semanticMatches.first {
            return .resolved(scopeID: match.scopeID)
        }
        if !semanticMatches.isEmpty {
            return .requiresSelection(existing: sorted(semanticMatches), proposedScopeID: newCopyScopeID)
        }
        if let contentHash = descriptor.contentHash {
            let contentMatches = compatible.filter { $0.lastContentHash == contentHash }
            if !contentMatches.isEmpty {
                if descriptor.semanticMatchPolicy == .automatic,
                   let resolution = resolution(forExactMatches: contentMatches, proposedScopeID: newCopyScopeID) {
                    return resolution
                }
                return .requiresSelection(existing: sorted(contentMatches), proposedScopeID: newCopyScopeID)
            }
        }
        return .resolved(scopeID: deterministicScopeID(for: descriptor, aliases: aliases))
    }

    static func revalidate(
        _ intent: ExternalImportSourceClaimIntent,
        latestResolution: ExternalImportSourceResolution,
        descriptor: ExternalImportSourceDescriptor,
        entries: [ExternalImportSourceEntry],
        aliases: SourceAliases
    ) -> ExternalImportSourceClaimResult {
        let requestedScopeID = intent.scopeID
        switch intent {
        case .selectedNew:
            // This is the one intent which deliberately creates a separate identity for a copied
            // source. For bridge exports, registration retains the intrinsic ID as a candidate.
            return .claimed(scopeID: requestedScopeID)

        case .selectedExisting:
            switch latestResolution {
            case .resolved(let canonicalScopeID):
                guard canonicalScopeID != requestedScopeID else {
                    return .claimed(scopeID: requestedScopeID)
                }
                return .requiresRemapping(canonicalScopeID: canonicalScopeID)
            case .requiresSelection(let existing, let proposedScopeID):
                guard existing.contains(where: { $0.scopeID == requestedScopeID }) else {
                    return .requiresSelection(existing: existing, proposedScopeID: proposedScopeID)
                }
                return .claimed(scopeID: requestedScopeID)
            }

        case .resolved:
            switch latestResolution {
            case .resolved(let canonicalScopeID):
                guard canonicalScopeID != requestedScopeID else {
                    return .claimed(scopeID: requestedScopeID)
                }
                return .requiresRemapping(canonicalScopeID: canonicalScopeID)
            case .requiresSelection(let existing, let proposedScopeID):
                // A second review of the exact same bytes can arrive after the first review's
                // claim. Canonicalize it without asking; genuine path replacement stays ambiguous.
                let physicalMatches = matchingPhysicalSource(
                    descriptor: descriptor,
                    entries: entries,
                    aliases: aliases
                )
                if physicalMatches.count == 1, let canonical = physicalMatches.first {
                    guard canonical.scopeID != requestedScopeID else {
                        return .claimed(scopeID: requestedScopeID)
                    }
                    return .requiresRemapping(canonicalScopeID: canonical.scopeID)
                }
                return .requiresSelection(existing: existing, proposedScopeID: proposedScopeID)
            }
        }
    }

    static func registering(
        scopeID: UUID,
        descriptor: ExternalImportSourceDescriptor,
        aliases: SourceAliases,
        importedAt: Date,
        in entries: [ExternalImportSourceEntry]
    ) -> [ExternalImportSourceEntry] {
        let existing = entries.first { $0.scopeID == scopeID }
        let reassignedIntrinsicAlias: UUID?
        if let intrinsicScopeID = descriptor.intrinsicScopeID, intrinsicScopeID != scopeID {
            reassignedIntrinsicAlias = intrinsicScopeID
        } else {
            reassignedIntrinsicAlias = existing?.intrinsicScopeAlias
        }

        var result = entries
        result.removeAll { $0.scopeID == scopeID }
        result.append(ExternalImportSourceEntry(
            scopeID: scopeID,
            format: descriptor.format,
            semanticKey: descriptor.semanticKey,
            fileResourceAlias: aliases.file,
            volumeResourceAlias: aliases.volume,
            lastKnownPathAlias: aliases.path,
            lastContentHash: descriptor.contentHash,
            createdAt: existing?.createdAt ?? importedAt,
            lastImportedAt: importedAt,
            intrinsicScopeAlias: reassignedIntrinsicAlias
        ))
        result.sort { $0.scopeID.uuidString < $1.scopeID.uuidString }
        return result
    }

    static func write(_ entries: [ExternalImportSourceEntry], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encodedIndex(entries).write(to: url, options: .atomic)
    }

    static func matchingPhysicalSource(
        descriptor: ExternalImportSourceDescriptor,
        entries: [ExternalImportSourceEntry],
        aliases: SourceAliases
    ) -> [ExternalImportSourceEntry] {
        let compatible = entries.filter { isCompatible($0, with: descriptor) }
        let exactFiles = exactFileMatches(in: compatible, aliases: aliases)
        guard exactFiles.isEmpty else { return exactFiles }
        guard let contentHash = descriptor.contentHash else { return [] }
        return compatible.filter {
            $0.lastKnownPathAlias == aliases.path && $0.lastContentHash == contentHash
        }
    }

    static func exactFileMatches(
        in entries: [ExternalImportSourceEntry],
        aliases: SourceAliases
    ) -> [ExternalImportSourceEntry] {
        entries.filter {
            guard let requested = aliases.file, let existing = $0.fileResourceAlias,
                  requested == existing else { return false }
            guard let requestedVolume = aliases.volume,
                  let existingVolume = $0.volumeResourceAlias else { return true }
            return requestedVolume == existingVolume
        }
    }

    static func sorted(_ entries: [ExternalImportSourceEntry]) -> [ExternalImportSourceEntry] {
        entries.sorted { lhs, rhs in
            if lhs.lastImportedAt != rhs.lastImportedAt {
                return lhs.lastImportedAt > rhs.lastImportedAt
            }
            return lhs.scopeID.uuidString < rhs.scopeID.uuidString
        }
    }

    static func mergingByScope(
        _ first: [ExternalImportSourceEntry],
        _ second: [ExternalImportSourceEntry]
    ) -> [ExternalImportSourceEntry] {
        var entries: [UUID: ExternalImportSourceEntry] = [:]
        for entry in first + second {
            guard let existing = entries[entry.scopeID] else {
                entries[entry.scopeID] = entry
                continue
            }
            if entry.lastImportedAt > existing.lastImportedAt {
                entries[entry.scopeID] = entry
            }
        }
        return Array(entries.values)
    }

    /// First allocation must converge even when two devices have not yet synchronized their source
    /// indexes. A deliberate "new copy" choice still receives the random proposal supplied above.
    static func deterministicScopeID(
        for descriptor: ExternalImportSourceDescriptor,
        aliases: SourceAliases
    ) -> UUID {
        if let intrinsicScopeID = descriptor.intrinsicScopeID {
            return intrinsicScopeID
        }

        let format = boundedIdentityComponent(descriptor.format)
        let identityComponent: String
        if let semanticKey = descriptor.semanticKey, !semanticKey.isEmpty {
            identityComponent = "semantic:\(boundedIdentityComponent(semanticKey))"
        } else if let contentHash = descriptor.contentHash, !contentHash.isEmpty {
            identityComponent = "fingerprint:\(boundedIdentityComponent(contentHash))"
        } else if let fileAlias = aliases.file {
            let volumeAlias = aliases.volume.map(boundedIdentityComponent) ?? "unknown-volume"
            identityComponent = "physical:\(volumeAlias):\(boundedIdentityComponent(fileAlias))"
        } else {
            identityComponent = "path:\(boundedIdentityComponent(aliases.path))"
        }
        return FoundryRuleIdentity.uuid(
            for: "external-import-source:v1#\(format)#\(identityComponent)"
        )
    }

    /// Avoid allowing malformed metadata to create an unbounded canonical identity key while still
    /// distinguishing ordinary long values by length and both ends of the value.
    static func boundedIdentityComponent(_ value: String) -> String {
        let limit = 512
        guard value.count > limit else { return value }
        let half = limit / 2
        return "\(value.prefix(half))#length:\(value.count)#\(value.suffix(half))"
    }

    static func resolution(
        forExactMatches matches: [ExternalImportSourceEntry],
        proposedScopeID: UUID
    ) -> ExternalImportSourceResolution? {
        if matches.count == 1, let match = matches.first {
            return .resolved(scopeID: match.scopeID)
        }
        guard !matches.isEmpty else { return nil }
        return .requiresSelection(
            existing: sorted(matches),
            proposedScopeID: proposedScopeID
        )
    }

    static func isCompatible(
        _ entry: ExternalImportSourceEntry,
        with descriptor: ExternalImportSourceDescriptor
    ) -> Bool {
        guard entry.format == descriptor.format else { return false }
        guard let requestedKey = descriptor.semanticKey, let existingKey = entry.semanticKey else {
            return true
        }
        return requestedKey == existingKey
    }

    static func aliases(for url: URL) -> SourceAliases {
        let securityScope = url.startSecurityScopedAccess()
        defer { securityScope.stop() }
        // URL resource values may remain cached on a reused security-scoped URL even after the
        // file at that path has been removed and replaced. Resolve metadata through a fresh file
        // URL so a replacement cannot inherit the previous file's physical identity and silently
        // update an unrelated arbitrary import.
        let metadataURL = URL(filePath: url.path(percentEncoded: false))
        let values = try? metadataURL.resourceValues(forKeys: [
            .fileResourceIdentifierKey,
            .volumeIdentifierKey,
        ])
        return SourceAliases(
            file: opaqueAlias(values?.fileResourceIdentifier),
            volume: opaqueAlias(values?.volumeIdentifier),
            path: pathAlias(of: url.standardizedFileURL.resolvingSymlinksInPath())
        )
    }

    /// The path as it is stored in the source index and compared with the stored aliases:
    /// without the trailing slash `path(percentEncoded:)` keeps for a folder, which is the form
    /// `URL.path` gave it. A Foundry world is a folder; with the slash it would no longer match
    /// its own entry. See CODE_AUDIT_21 §4.2.
    static func pathAlias(of url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    static func opaqueAlias(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let data = value as? Data { return "data:\(data.base64EncodedString())" }
        if let string = value as? String { return "string:\(string)" }
        if let number = value as? NSNumber { return "number:\(number.stringValue)" }
        if let secureValue = value as? (any NSSecureCoding),
           let data = try? NSKeyedArchiver.archivedData(
               withRootObject: secureValue,
               requiringSecureCoding: true
           ) {
            return "archive:\(data.base64EncodedString())"
        }
        return "description:\(String(reflecting: type(of: value))):\(String(describing: value))"
    }
}
