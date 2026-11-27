// @copyright André Trettin

import Foundation

// Extracted from FoundryVTTImportReader.swift per CODE_AUDIT §9.8 — the per-collection decode
// strategies `FoundryVTTDecoder` dispatches to from `decodeCollection(_:packageKind:packageId:
// source:diagnostics:)` (still in the main file's "Collection Discovery" section). Despite the
// historical "LevelDB Collection Decoding" name, this also covers the Legacy NeDB and plain-JSON
// collection formats — all three ultimately hand their raw (id, JSON) pairs to the shared
// `FoundryVTTDocumentDecoder` (which stays in the main file, since it's also used by
// `FoundryVTTBridgeDecoding.swift`) for document-tree assembly.

// MARK: - LevelDB Collection Decoding

private struct FoundryLevelDBLiveFiles {
    let tables: [String]
    let logs: [String]
}

extension FoundryVTTDecoder {
    func decodeLevelDBCollection(
        _ spec: FoundryVTTCollectionSpec,
        packageKind: FoundryVTTPackageKind,
        packageId: String,
        source: FoundryVTTDataSource,
        budget: inout FoundryVTTReadBudget
    ) throws -> (collection: FoundryDocumentCollection, diagnostics: [FoundryImportDiagnostic]) {
        let prefix = spec.path.isEmpty ? "" : (spec.path.hasSuffix("/") ? spec.path : spec.path + "/")
        let candidatePaths = source.paths(withPrefix: prefix)
        let discoveredTablePaths = candidatePaths.filter { path in
            let lowercased = path.lowercased()
            return (lowercased.hasSuffix(".ldb") || lowercased.hasSuffix(".sst"))
                && (prefix.isEmpty || path.hasPrefix(prefix))
        }.sorted()
        let discoveredLogPaths = candidatePaths.filter { path in
            guard path.lowercased().hasSuffix(".log"), prefix.isEmpty || path.hasPrefix(prefix) else { return false }
            return URL(filePath: path).deletingPathExtension().lastPathComponent.allSatisfy(\.isNumber)
        }.sorted()
        guard !discoveredTablePaths.isEmpty || !discoveredLogPaths.isEmpty else {
            throw FoundryImportError.missingPack(spec.name)
        }
        let liveFiles = try liveLevelDBPaths(
            discoveredTables: discoveredTablePaths,
            discoveredLogs: discoveredLogPaths,
            prefix: prefix,
            packName: spec.name,
            source: source,
            budget: &budget
        )

        var records: [FoundryLevelDBRecord] = []
        for path in liveFiles.tables {
            try Task.checkCancellation()
            guard let data = try source.data(forPath: path) else { continue }
            try budget.includeEncoded(data.count, limits: limits)
            let decoded = try FoundryLevelDBTableReader(limits: limits).records(in: data)
            for record in decoded {
                try budget.includeDecoded(record.key.utf8.count + record.value.count + 9, limits: limits)
            }
            let (nextCount, overflow) = records.count.addingReportingOverflow(decoded.count)
            guard !overflow, nextCount <= limits.maximumDocumentCount else {
                throw FoundryImportError.tooManyDocuments(overflow ? Int.max : nextCount)
            }
            records.append(contentsOf: decoded)
        }
        for path in liveFiles.logs {
            try Task.checkCancellation()
            guard let data = try source.data(forPath: path) else { continue }
            try budget.includeEncoded(data.count, limits: limits)
            let decoded = try FoundryLevelDBWriteAheadLogReader(limits: limits).records(in: data, path: path)
            for record in decoded {
                try budget.includeDecoded(record.key.utf8.count + record.value.count + 9, limits: limits)
            }
            let (nextCount, overflow) = records.count.addingReportingOverflow(decoded.count)
            guard !overflow, nextCount <= limits.maximumDocumentCount else {
                throw FoundryImportError.tooManyDocuments(overflow ? Int.max : nextCount)
            }
            records.append(contentsOf: decoded)
        }
        let current = try FoundryLevelDBRecordMerger.currentRecords(records)
        return try FoundryVTTDocumentDecoder(
            packageKind: packageKind,
            packageId: packageId,
            spec: spec,
            limits: limits
        ).decodeLevelDB(current, budget: &budget)
    }

    private func liveLevelDBPaths(
        discoveredTables: [String],
        discoveredLogs: [String],
        prefix: String,
        packName: String,
        source: FoundryVTTDataSource,
        budget: inout FoundryVTTReadBudget
    ) throws -> FoundryLevelDBLiveFiles {
        let currentPath = [prefix + "CURRENT", prefix + "current"].first { source.contains(path: $0) }
        guard let currentPath else {
            for path in discoveredLogs {
                guard let data = try source.data(forPath: path) else { continue }
                try budget.includeEncoded(data.count, limits: limits)
                guard data.isEmpty else {
                    throw FoundryImportError.unsupportedLevelDBLog(path)
                }
            }
            guard discoveredTables.count == 1 else {
                throw FoundryImportError.unsupportedLevelDBTableSet(
                    pack: packName,
                    tableCount: discoveredTables.count
                )
            }
            return FoundryLevelDBLiveFiles(tables: discoveredTables, logs: [])
        }
        guard let currentData = try source.data(forPath: currentPath),
              let currentText = String(data: currentData, encoding: .utf8) else {
            throw FoundryImportError.corruptLevelDB("The CURRENT file is not UTF-8.")
        }
        try budget.includeEncoded(currentData.count, limits: limits)
        let manifestName = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard manifestName.hasPrefix("MANIFEST-"),
              !manifestName.contains("/"), !manifestName.contains("\\") else {
            throw FoundryImportError.corruptLevelDB("The CURRENT file names an invalid MANIFEST.")
        }
        let manifestPath = prefix + manifestName
        guard let manifestData = try source.data(forPath: manifestPath) else {
            throw FoundryImportError.corruptLevelDB("The CURRENT MANIFEST is missing.")
        }
        try budget.includeEncoded(manifestData.count, limits: limits)
        let state = try FoundryLevelDBManifestReader(limits: limits).state(in: manifestData)
        let tablesByNumber = try numberedLevelDBPaths(discoveredTables, kind: "SSTable")
        let missingNumbers = state.activeFileNumbers.subtracting(tablesByNumber.keys)
        guard missingNumbers.isEmpty else {
            throw FoundryImportError.corruptLevelDB("The MANIFEST references a missing SSTable.")
        }
        let tablePaths = state.activeFileNumbers.compactMap { tablesByNumber[$0] }.sorted()

        let logsByNumber = try numberedLevelDBPaths(discoveredLogs, kind: "write-ahead log")
        guard let minimumLogNumber = state.logNumber else {
            for path in discoveredLogs {
                guard let data = try source.data(forPath: path) else { continue }
                try budget.includeEncoded(data.count, limits: limits)
                guard data.isEmpty else {
                    throw FoundryImportError.corruptLevelDB(
                        "The MANIFEST does not identify which non-empty write-ahead logs are live."
                    )
                }
            }
            return FoundryLevelDBLiveFiles(tables: tablePaths, logs: [])
        }
        let previousLogNumber = state.previousLogNumber.flatMap { $0 == 0 ? nil : $0 }
        let requiredLogNumbers = Set([minimumLogNumber == 0 ? nil : minimumLogNumber, previousLogNumber].compactMap { $0 })
        guard requiredLogNumbers.isSubset(of: Set(logsByNumber.keys)) else {
            throw FoundryImportError.corruptLevelDB("The MANIFEST references a missing live write-ahead log.")
        }
        let logPaths = logsByNumber.compactMap { number, path in
            number >= minimumLogNumber || previousLogNumber == number ? path : nil
        }.sorted()
        return FoundryLevelDBLiveFiles(tables: tablePaths, logs: logPaths)
    }

    func numberedLevelDBPaths(_ paths: [String], kind: String) throws -> [UInt64: String] {
        var result: [UInt64: String] = [:]
        for path in paths {
            let stem = URL(filePath: path).deletingPathExtension().lastPathComponent
            guard let number = UInt64(stem), result[number] == nil else {
                throw FoundryImportError.corruptLevelDB("A \(kind) filename is invalid or duplicated.")
            }
            result[number] = path
        }
        return result
    }

    // MARK: - Legacy NeDB Database Decoding

    func decodeLegacyDatabase(
        _ spec: FoundryVTTCollectionSpec,
        packageKind: FoundryVTTPackageKind,
        packageId: String,
        source: FoundryVTTDataSource,
        budget: inout FoundryVTTReadBudget
    ) throws -> (collection: FoundryDocumentCollection, diagnostics: [FoundryImportDiagnostic]) {
        guard let data = try source.data(forPath: spec.path) else { throw FoundryImportError.missingPack(spec.name) }
        try budget.includeEncoded(data.count, limits: limits)
        var current: [String: FoundryJSONValue] = [:]
        var diagnostics: [FoundryImportDiagnostic] = []
        var omittedDiagnosticCount = 0
        let diagnosticLimit = max(0, limits.maximumDiagnosticCount)
        for (lineNumber, line) in FoundryVTTLineSequence(data).enumerated() {
            try Task.checkCancellation()
            guard lineNumber < max(0, limits.maximumRecordCount) else {
                throw FoundryImportError.tooManyDocuments(lineNumber + 1)
            }
            let trimmed = line.foundryTrimmingASCIIWhitespace()
            guard !trimmed.isEmpty else { continue }
            try budget.includeDecoded(trimmed.count, limits: limits)
            do {
                let raw = try FoundryJSONDecoding.decode(Data(trimmed), context: spec.path)
                guard let object = raw.objectValue else {
                    throw FoundryImportError.invalidDocument(pack: spec.name, key: "line \(lineNumber + 1)")
                }
                let id = object["_id"]?.stringValue
                    ?? object["id"]?.stringValue
                    ?? "line-\(lineNumber + 1)"
                if object["$$deleted"]?.boolValue == true {
                    current.removeValue(forKey: id)
                } else {
                    current[id] = raw
                }
            } catch {
                if diagnostics.count < diagnosticLimit {
                    diagnostics.append(FoundryImportDiagnostic(
                        severity: .warning,
                        code: "invalid-nedb-record",
                        message: "Skipped invalid JSON at line \(lineNumber + 1) of \(spec.name).",
                        packName: spec.name
                    ))
                } else {
                    omittedDiagnosticCount += 1
                }
            }
        }
        if omittedDiagnosticCount > 0, diagnosticLimit > 0 {
            if diagnostics.count == diagnosticLimit {
                diagnostics.removeLast()
                omittedDiagnosticCount += 1
            }
            diagnostics.append(FoundryImportDiagnostic(
                severity: .warning,
                code: "diagnostics-truncated",
                message: "Suppressed \(omittedDiagnosticCount) invalid records in \(spec.name).",
                packName: spec.name
            ))
        }
        let decoded = try FoundryVTTDocumentDecoder(
            packageKind: packageKind,
            packageId: packageId,
            spec: spec,
            limits: limits
        ).decodeRawDocuments(current.map { ($0.key, $0.value) }, budget: &budget)
        return (decoded.collection, diagnostics + decoded.diagnostics)
    }

    // MARK: - JSON Collection Decoding

    func decodeJSONCollection(
        _ spec: FoundryVTTCollectionSpec,
        packageKind: FoundryVTTPackageKind,
        packageId: String,
        source: FoundryVTTDataSource,
        budget: inout FoundryVTTReadBudget
    ) throws -> (collection: FoundryDocumentCollection, diagnostics: [FoundryImportDiagnostic]) {
        guard let data = try source.data(forPath: spec.path) else { throw FoundryImportError.missingPack(spec.name) }
        try budget.includeEncoded(data.count, limits: limits)
        try budget.includeDecoded(data.count, limits: limits)
        let raw = try FoundryJSONDecoding.decode(data, context: spec.path)
        let documents: [(String, FoundryJSONValue)]
        if let array = raw.arrayValue {
            documents = array.enumerated().map { index, value in
                (value["_id"]?.stringValue ?? value["id"]?.stringValue ?? "document-\(index + 1)", value)
            }
        } else if let object = raw.objectValue,
                  let array = object["documents"]?.arrayValue {
            documents = array.enumerated().map { index, value in
                (value["_id"]?.stringValue ?? value["id"]?.stringValue ?? "document-\(index + 1)", value)
            }
        } else {
            let id = raw["_id"]?.stringValue ?? raw["id"]?.stringValue ?? spec.name
            documents = [(id, raw)]
        }
        let collectionRawData: FoundryJSONValue? = raw.arrayValue != nil || raw["documents"]?.arrayValue != nil
            ? raw
            : spec.rawData
        let decodedSpec = FoundryVTTCollectionSpec(
            id: spec.id,
            name: spec.name,
            label: spec.label,
            path: spec.path,
            declaredType: spec.declaredType,
            rawData: collectionRawData
        )
        return try FoundryVTTDocumentDecoder(
            packageKind: packageKind,
            packageId: packageId,
            spec: decodedSpec,
            limits: limits
        ).decodeRawDocuments(documents, budget: &budget)
    }
}

// MARK: - LevelDB Record Merging

struct FoundryLevelDBRecordMerger {
    static func currentRecords(_ records: [FoundryLevelDBRecord]) throws -> [FoundryLevelDBRecord] {
        var current: [String: FoundryLevelDBRecord] = [:]
        var recordsBySequence: [UInt64: FoundryLevelDBRecord] = [:]
        for record in records {
            if let existingSequence = recordsBySequence[record.sequence] {
                guard record == existingSequence else {
                    throw FoundryImportError.corruptLevelDB(
                        "The same LevelDB sequence number has conflicting records."
                    )
                }
            } else {
                recordsBySequence[record.sequence] = record
            }
            if let existing = current[record.key] {
                if record.sequence < existing.sequence { continue }
                if record.sequence == existing.sequence {
                    guard record.operation == existing.operation, record.value == existing.value else {
                        throw FoundryImportError.corruptLevelDB(
                            "The same key and sequence have conflicting LevelDB values."
                        )
                    }
                    continue
                }
            }
            current[record.key] = record
        }
        return current.values
            .filter { $0.operation == .value }
            .sorted { $0.key < $1.key }
    }
}
