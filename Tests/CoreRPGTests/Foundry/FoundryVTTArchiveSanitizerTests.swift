// @copyright André Trettin

import Foundation
import Testing
@testable import CoreRPG

@Suite("Foundry durable archive privacy")
struct FoundryVTTArchiveSanitizerTests {
    @Test("Disabled users and chat are absent from the encoded archive")
    func encodedArchiveRecursivelyScrubsPrivateData() throws {
        // Given
        let privateUserValue = "PRIVATE-FOUNDRY-USER-314159"
        let privateChatValue = "PRIVATE-FOUNDRY-CHAT-271828"
        let semanticUserValue = "RULE-SYSTEM-USER-MUST-REMAIN"
        let semanticMessagesValue = "RULE-SYSTEM-MESSAGES-MUST-REMAIN"
        let itemRaw: FoundryJSONValue = .object([
            "_id": .string("item-1"),
            "name": .string("Sword"),
            "ownership": .object(["private": .string(privateUserValue)]),
            "safe": .string("retained"),
        ])
        let item = document(
            id: "foundry://world/test/collection/adventure/Adventure/adventure-1/Item/item-1",
            documentID: "item-1",
            type: .item,
            rawData: itemRaw
        )
        let actorRaw: FoundryJSONValue = .object([
            "_id": .string("actor-1"),
            "name": .string("Hero"),
            "ownership": .object(["default": .integer(0), "private": .string(privateUserValue)]),
            "items": .array([itemRaw]),
            "nested": .array([
                .object(["userId": .string(privateUserValue)]),
                .object(["documentName": .string("User"), "name": .string(privateUserValue)]),
                .object([
                    "documentName": .string("ChatMessage"),
                    "content": .string(privateChatValue),
                ]),
            ]),
            "messages": .array([.object(["content": .string(privateChatValue)])]),
        ])
        let actor = document(
            id: "foundry://world/test/collection/adventure/Adventure/adventure-1/Actor/actor-1",
            documentID: "actor-1",
            type: .actor,
            rawData: actorRaw,
            embeddedDocuments: [item]
        )
        let folder = FoundryDocumentFolder(
            id: "foundry://world/test/collection/adventure/Folder/folder-1",
            documentID: "folder-1",
            name: "People",
            parentID: nil,
            documentType: .actor,
            sort: nil,
            rawData: .object([
                "_id": .string("folder-1"),
                "type": .string("Actor"),
                "permission": .object(["user-secret": .string(privateUserValue)]),
            ])
        )
        let contentCollection = collection(
            id: "adventure",
            type: .adventure,
            documents: [actor],
            folders: [folder],
            rawData: .object([
                "documents": .array([actorRaw]),
                "ownership": .object(["private": .string(privateUserValue)]),
                "chatMessages": .array([.object(["content": .string(privateChatValue)])]),
            ])
        )
        let userDocument = document(
            id: "foundry://world/test/collection/users/User/user-1",
            documentID: "user-1",
            type: .user,
            rawData: .object(["_id": .string("user-1"), "name": .string(privateUserValue)])
        )
        let chatDocument = document(
            id: "foundry://world/test/collection/messages/ChatMessage/chat-1",
            documentID: "chat-1",
            type: .chatMessage,
            rawData: .object(["_id": .string("chat-1"), "content": .string(privateChatValue)])
        )
        let package = FoundryVTTImportPackage(
            kind: .world,
            manifestPath: "world.json",
            manifest: FoundryVTTPackageManifest(
                kind: .world,
                id: "test",
                title: "Test",
                descriptionHTML: nil,
                version: "1",
                systemID: "test",
                compatibility: compatibility,
                rawData: .object([
                    "author": .string("Package Author Must Remain"),
                    "nestedUser": .object([
                        "documentName": .string("User"),
                        "name": .string(privateUserValue),
                    ]),
                    "nestedChat": .object([
                        "documentType": .string("ChatMessage"),
                        "content": .string(privateChatValue),
                    ]),
                ])
            ),
            collections: [
                contentCollection,
                collection(id: "users", type: .user, documents: [userDocument]),
                collection(id: "messages", type: .chatMessage, documents: [chatDocument]),
            ],
            resources: [],
            diagnostics: [],
            statistics: .init(
                collectionCount: 3,
                topLevelDocumentCount: 3,
                embeddedDocumentCount: 1,
                folderCount: 1,
                unknownFieldCount: 0,
                documentCounts: [:]
            ),
            rulePackage: rulePackage(
                privateUserValue: privateUserValue,
                privateChatValue: privateChatValue,
                semanticUserValue: semanticUserValue,
                semanticMessagesValue: semanticMessagesValue
            )
        )

        // When
        let sanitized = FoundryVTTArchiveSanitizer.sanitize(
            package,
            includingChat: false,
            includingUsers: false
        )
        let archiveID = try #require(UUID(uuidString: "8C8BF1A3-D724-4122-B8D6-BEDFEAD3C398"))
        let archive = FoundryImportArchive(
            id: archiveID,
            importedAt: Date(timeIntervalSince1970: 0),
            sourceFileName: "test-world.zip",
            package: sanitized,
            mappings: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(archive)
        let encodedText = try #require(String(data: encoded, encoding: .utf8))

        // Then
        #expect(!encodedText.contains(privateUserValue))
        #expect(!encodedText.contains(privateChatValue))
        #expect(!encodedText.contains("\"ownership\""))
        #expect(!encodedText.contains("\"permission\""))
        #expect(!encodedText.contains("\"chatMessages\""))
        #expect(encodedText.contains(semanticUserValue))
        #expect(encodedText.contains(semanticMessagesValue))
        #expect(sanitized.collections.count == 1)
        #expect(sanitized.statistics.collectionCount == 1)
        #expect(sanitized.statistics.topLevelDocumentCount == 1)
        #expect(sanitized.manifest?.rawData["author"]?.stringValue == "Package Author Must Remain")
        let sanitizedActor = try #require(sanitized.documents.first)
        #expect(sanitizedActor.rawData["items"] == nil)
        #expect(sanitizedActor.embeddedDocuments.first?.rawData["safe"]?.stringValue == "retained")
        #expect(sanitized.collections.first?.rawData == nil)
        #expect(
            sanitized.rulePackage?.schemas.first?.fields.map(\.path)
                == ["system.user", "system.messages"]
        )
        #expect(sanitized.rulePackage?.compendiums.first?.rules.count == 1)
        #expect(
            sanitized.rulePackage?.compendiums.first?.rules.first?.effects.first?.changes.map(\.path)
                == ["flags.example-module.messages"]
        )
    }

    @Test("Document metadata is scrubbed without interpreting game-system field names")
    func documentPrivacyIsContextAware() throws {
        // Given
        let privateValue = "PRIVATE-IDENTITY-MUST-BE-SCRUBBED"
        let semanticUser = "SYSTEM-USER-RULE-MUST-REMAIN"
        let semanticMessages = "SYSTEM-MESSAGES-RULE-MUST-REMAIN"
        let actor = document(
            id: "foundry://world/test/collection/actors/Actor/actor-1",
            documentID: "actor-1",
            type: .actor,
            rawData: .object([
                "_id": .string("actor-1"),
                "authorID": .string(privateValue),
                "owners": .array([.string(privateValue)]),
                "playerOwners": .array([.string(privateValue)]),
                "users": .array([.string(privateValue)]),
                "whisper": .array([.string(privateValue)]),
                "messages": .array([.string(privateValue)]),
                "system": .object([
                    "user": .string(semanticUser),
                    "users": .array([.string(semanticUser)]),
                    "messages": .array([.string(semanticMessages)]),
                    "nested": .object([
                        "authorID": .string("semantic-author-field"),
                        "whisper": .string("semantic-whisper-rule"),
                    ]),
                ]),
                "flags": .object([
                    "example-module": .object([
                        "user": .string("module-user-rule"),
                        "messages": .array([.string("module-message-rule")]),
                    ]),
                ]),
            ])
        )
        let package = FoundryVTTImportPackage(
            kind: .world,
            manifestPath: nil,
            manifest: nil,
            collections: [collection(id: "actors", type: .actor, documents: [actor])],
            resources: [],
            diagnostics: [],
            statistics: .init(
                collectionCount: 1,
                topLevelDocumentCount: 1,
                embeddedDocumentCount: 0,
                folderCount: 0,
                unknownFieldCount: 0,
                documentCounts: [:]
            )
        )

        // When
        let sanitized = FoundryVTTArchiveSanitizer.sanitize(
            package,
            includingChat: false,
            includingUsers: false
        )

        // Then
        let raw = try #require(sanitized.documents.first?.rawData)
        #expect(raw["authorID"] == nil)
        #expect(raw["owners"] == nil)
        #expect(raw["playerOwners"] == nil)
        #expect(raw["users"] == nil)
        #expect(raw["whisper"] == nil)
        #expect(raw["messages"] == nil)
        #expect(raw.value(at: "system.user")?.stringValue == semanticUser)
        #expect(raw.value(at: "system.users")?.arrayValue?.first?.stringValue == semanticUser)
        #expect(raw.value(at: "system.messages")?.arrayValue?.first?.stringValue == semanticMessages)
        #expect(raw.value(at: "system.nested.authorID")?.stringValue == "semantic-author-field")
        #expect(raw.value(at: "system.nested.whisper")?.stringValue == "semantic-whisper-rule")
        #expect(raw.value(at: "flags.example-module.user")?.stringValue == "module-user-rule")
        #expect(
            raw.value(at: "flags.example-module.messages")?.arrayValue?.first?.stringValue
                == "module-message-rule"
        )
    }

    @Test("Normalization retains raw array values that were not represented as documents")
    func normalizationKeepsUnrepresentedEmbeddedValues() throws {
        // Given
        let representedRaw: FoundryJSONValue = .object([
            "_id": .string("item-1"),
            "name": .string("Represented"),
        ])
        let parent = document(
            id: "foundry://world/test/collection/actors/Actor/actor-1",
            documentID: "actor-1",
            type: .actor,
            rawData: .object([
                "_id": .string("actor-1"),
                "items": .array([representedRaw, .string("future-format-value")]),
            ]),
            embeddedDocuments: [
                document(
                    id: "foundry://world/test/collection/actors/Actor/actor-1/Item/item-1",
                    documentID: "item-1",
                    type: .item,
                    rawData: representedRaw
                ),
            ]
        )
        let package = FoundryVTTImportPackage(
            kind: .world,
            manifestPath: nil,
            manifest: nil,
            collections: [collection(id: "actors", type: .actor, documents: [parent])],
            resources: [],
            diagnostics: [],
            statistics: .init(
                collectionCount: 1,
                topLevelDocumentCount: 1,
                embeddedDocumentCount: 1,
                folderCount: 0,
                unknownFieldCount: 0,
                documentCounts: [:]
            )
        )

        // When
        let sanitized = FoundryVTTArchiveSanitizer.sanitize(
            package,
            includingChat: true,
            includingUsers: true
        )

        // Then
        let rawItems = try #require(sanitized.documents.first?.rawData["items"]?.arrayValue)
        #expect(rawItems == [.string("future-format-value")])
    }
}

private extension FoundryVTTArchiveSanitizerTests {
    var compatibility: FoundryCompatibility {
        FoundryCompatibility(minimum: nil, verified: "13", maximum: nil)
    }

    func document(
        id: String,
        documentID: String,
        type: FoundryDocumentType,
        rawData: FoundryJSONValue,
        embeddedDocuments: [FoundryDocument] = []
    ) -> FoundryDocument {
        FoundryDocument(
            id: id,
            documentID: documentID,
            documentType: type,
            subtype: nil,
            name: rawData["name"]?.stringValue ?? documentID,
            folderID: nil,
            sort: nil,
            imagePath: nil,
            descriptionHTML: nil,
            parentID: nil,
            embeddedDocuments: embeddedDocuments,
            references: [],
            unknownFieldNames: [],
            rawData: rawData
        )
    }

    func collection(
        id: String,
        type: FoundryDocumentType,
        documents: [FoundryDocument],
        folders: [FoundryDocumentFolder] = [],
        rawData: FoundryJSONValue? = nil
    ) -> FoundryDocumentCollection {
        FoundryDocumentCollection(
            id: id,
            name: id,
            label: id,
            sourcePath: "data/\(id)",
            declaredDocumentType: type,
            documents: documents,
            folders: folders,
            rawData: rawData
        )
    }

    func rulePackage(
        privateUserValue: String,
        privateChatValue: String,
        semanticUserValue: String,
        semanticMessagesValue: String
    ) -> FoundryRulePackage {
        let privateEffect = FoundryRuleEffect(
            id: "effect-1",
            name: "Private effect",
            isDisabled: false,
            transfersToActor: false,
            statuses: [],
            changes: [
                FoundryRuleEffectChange(
                    path: "_stats.createdBy",
                    mode: 2,
                    operand: .string(privateUserValue),
                    priority: nil
                ),
                FoundryRuleEffectChange(
                    path: "flags.example-module.messages",
                    mode: 2,
                    operand: .string(semanticMessagesValue),
                    priority: nil
                ),
            ],
            duration: nil,
            rawData: .object([
                "ownership": .object(["private": .string(privateUserValue)]),
                "messages": .array([.string(privateChatValue)]),
            ])
        )
        let retainedRule = FoundryRuleDefinition(
            id: "pack.Item.item-1",
            documentID: "item-1",
            packName: "pack",
            documentType: "Item",
            subtype: "equipment",
            category: .equipment,
            name: "Item",
            descriptionHTML: nil,
            imagePath: nil,
            folderID: nil,
            values: [
                FoundryRuleValue(path: "system.user", value: .string(semanticUserValue)),
                FoundryRuleValue(
                    path: "system.messages",
                    value: .array([.string(semanticMessagesValue)])
                ),
            ],
            tags: [],
            references: [
                FoundryRuleReference(
                    kind: .uuid,
                    sourcePath: "system.link",
                    rawToken: "@UUID[User.user-1]",
                    target: "User.user-1",
                    label: nil,
                    packName: nil,
                    documentID: "user-1"
                ),
            ],
            embeddedRules: [],
            effects: [privateEffect],
            rawData: .object([
                "_id": .string("item-1"),
                "ownership": .object(["private": .string(privateUserValue)]),
                "system": .object([
                    "user": .string(semanticUserValue),
                    "messages": .array([.string(semanticMessagesValue)]),
                ]),
                "future": .object([
                    "documentType": .string("ChatMessage"),
                    "content": .string(privateChatValue),
                ]),
            ])
        )
        let chatRule = FoundryRuleDefinition(
            id: "pack.ChatMessage.chat-1",
            documentID: "chat-1",
            packName: "pack",
            documentType: "ChatMessage",
            subtype: "message",
            category: .equipment,
            name: "Private chat",
            descriptionHTML: privateChatValue,
            imagePath: nil,
            folderID: nil,
            values: [],
            tags: [],
            references: [],
            embeddedRules: [],
            effects: [],
            rawData: .object(["content": .string(privateChatValue)])
        )
        return FoundryRulePackage(
            manifest: FoundrySystemManifest(
                id: "test",
                title: "Test",
                description: nil,
                version: "1",
                compatibility: compatibility,
                packs: [],
                rawData: .object([
                    "author": .string("Rule package author"),
                    "nested": .object([
                        "documentName": .string("User"),
                        "name": .string(privateUserValue),
                    ]),
                ])
            ),
            manifestPath: "system.json",
            templatePath: "template.json",
            templateData: .object([
                "Actor": .object([
                    "system": .object([
                        "user": .string(semanticUserValue),
                        "messages": .array([.string(semanticMessagesValue)]),
                    ]),
                ]),
            ]),
            schemas: [
                FoundryRuleSchema(
                    documentType: "Item",
                    subtype: "equipment",
                    inheritedTemplates: [],
                    fields: [
                        FoundryRuleField(
                            path: "ownership.default",
                            valueKind: .string,
                            defaultValue: .string(privateUserValue)
                        ),
                        FoundryRuleField(
                            path: "system.user",
                            valueKind: .string,
                            defaultValue: .string(semanticUserValue)
                        ),
                        FoundryRuleField(
                            path: "system.messages",
                            valueKind: .array,
                            defaultValue: .array([.string(semanticMessagesValue)])
                        ),
                    ],
                    rawData: .object([
                        "system": .object([
                            "user": .string(semanticUserValue),
                            "messages": .array([.string(semanticMessagesValue)]),
                        ]),
                    ])
                ),
            ],
            compendiums: [
                FoundryCompendium(
                    manifest: FoundryPackManifest(
                        name: "pack",
                        label: "Pack",
                        path: "packs/pack",
                        documentType: "Item",
                        systemID: "test"
                    ),
                    rules: [retainedRule, chatRule],
                    folders: []
                ),
            ],
            assetPaths: [],
            licensePaths: [],
            diagnostics: []
        )
    }
}
