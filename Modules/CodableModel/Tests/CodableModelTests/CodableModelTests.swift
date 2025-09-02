import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(CodableModelMacros)
import CodableModelMacros

let testMacros: [String: Macro.Type] = [
    "CodableModel": CodableModelMacro.self,
    "CodableIgnored": CodableIgnoredMacro.self,
]
#endif

final class CodableModelTests: XCTestCase {

    func testCodableModelBasic() throws {
        #if canImport(CodableModelMacros)
        assertMacroExpansion(
            """
            @CodableModel
            @Model
            public final class DieDataModel {
                public var id: UUID = UUID()
                var index: Int = 0
                var die: RawDie = RawDie.twenty
                var color: String = ""
                
                @Transient
                var rotation: Double = 0
                @Transient
                var result: [Int] = []
                
                var parent: DiceDataModel? = nil
            }
            """,
            expandedSource: """
            @Model
            public final class DieDataModel {
                public var id: UUID = UUID()
                var index: Int = 0
                var die: RawDie = RawDie.twenty
                var color: String = ""
                
                @Transient
                var rotation: Double = 0
                @Transient
                var result: [Int] = []
                
                var parent: DiceDataModel? = nil
            }
            
            struct DieDataCodableModel: Equatable, Hashable, Codable, Sendable {
                init(id: UUID = UUID(), index: Int = 0, die: RawDie = RawDie.twenty, color: String = "", rotation: Double = 0, result: [Int] = []) {
                    self.id = id
                    self.index = index
                    self.die = die
                    self.color = color
                    self.rotation = rotation
                    self.result = result
                }
                var id: UUID = UUID()
                var index: Int = 0
                var die: RawDie = RawDie.twenty
                var color: String = ""
                var rotation: Double = 0
                var result: [Int] = []
            }
            
            extension DieDataModel {
                convenience init(_ model: DieDataCodableModel) {
                    self.init(
                        id: model.id,
                        index: model.index,
                        die: model.die,
                        color: model.color,
                        rotation: model.rotation,
                        result: model.result
                    )
                }
                var codableModel: DieDataCodableModel {
                    DieDataCodableModel(
                        id: id,
                        index: index,
                        die: die,
                        color: color,
                        rotation: rotation,
                        result: result
                    )
                }
                func replace(_ model: DieDataCodableModel) {
                    id = model.id
                    index = model.index
                    die = model.die
                    color = model.color
                    rotation = model.rotation
                    result = model.result
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testCodableModelWithMinimalProperties() throws {
        #if canImport(CodableModelMacros)
        assertMacroExpansion(
            """
            @CodableModel
            @Model
            final class SimpleModel {
                var name: String = ""
                var value: Int = 0
            }
            """,
            expandedSource: """
            @Model
            final class SimpleModel {
                var name: String = ""
                var value: Int = 0
            }
            
            struct SimpleCodableModel: Equatable, Hashable, Codable, Sendable {
                init(name: String = "", value: Int = 0) {
                    self.name = name
                    self.value = value
                }
                var name: String = ""
                var value: Int = 0
            }
            
            extension SimpleModel {
                convenience init(_ model: SimpleCodableModel) {
                    self.init(
                        name: model.name,
                        value: model.value,
                        parent: nil
                    )
                }
                var codableModel: SimpleCodableModel {
                    SimpleCodableModel(
                        name: name,
                        value: value
                    )
                }
                func replace(_ model: SimpleCodableModel) {
                    name = model.name
                    value = model.value
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testCodableModelSkipsRelationships() throws {
        #if canImport(CodableModelMacros)
        assertMacroExpansion(
            """
            @CodableModel
            @Model
            final class ModelWithRelationships {
                var id: UUID = UUID()
                var name: String = ""
                var parent: ParentDataModel? = nil
                var children: [ChildDataModel] = []
            }
            """,
            expandedSource: """
            @Model
            final class ModelWithRelationships {
                var id: UUID = UUID()
                var name: String = ""
                var parent: ParentDataModel? = nil
                var children: [ChildDataModel] = []
            }
            
            struct ModelWithRelationshipsCodableModel: Equatable, Hashable, Codable, Sendable {
                init(id: UUID = UUID(), name: String = "") {
                    self.id = id
                    self.name = name
                }
                var id: UUID = UUID()
                var name: String = ""
            }
            
            extension ModelWithRelationships {
                convenience init(_ model: ModelWithRelationshipsCodableModel) {
                    self.init(
                        id: model.id,
                        name: model.name,
                        parent: nil
                    )
                }
                var codableModel: ModelWithRelationshipsCodableModel {
                    ModelWithRelationshipsCodableModel(
                        id: id,
                        name: name
                    )
                }
                func replace(_ model: ModelWithRelationshipsCodableModel) {
                    id = model.id
                    name = model.name
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testCodableModelErrorOnNonClass() throws {
        #if canImport(CodableModelMacros)
        assertMacroExpansion(
            """
            @CodableModel
            struct NotAClass {
                var name: String = ""
            }
            """,
            expandedSource: """
            struct NotAClass {
                var name: String = ""
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@CodableModel can only be applied to classes", line: 1, column: 1)
            ],
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
    
    func testCodableModelWithIgnoredProperties() throws {
        #if canImport(CodableModelMacros)
        assertMacroExpansion(
            """
            @CodableModel
            @Model
            final class ModelWithIgnoredProps {
                var id: UUID = UUID()
                var name: String = ""
                
                @CodableIgnored
                var temporaryData: String = ""
                
                @CodableIgnored
                var internalState: Int = 0
            }
            """,
            expandedSource: """
            @Model
            final class ModelWithIgnoredProps {
                var id: UUID = UUID()
                var name: String = ""
                
                @CodableIgnored
                var temporaryData: String = ""
                
                @CodableIgnored
                var internalState: Int = 0

                struct ModelWithIgnoredPropsCodable: Equatable, Hashable, Codable, Sendable {
                    init(id: UUID = UUID(), name: String = "") {
                        self.id = id
                        self.name = name
                    }
                    var id: UUID = UUID()
                    var name: String = ""
                }

                convenience init(_ model: ModelWithIgnoredPropsCodable) {
                    self.init()
                    self.id = model.id
                    self.name = model.name
                }

                var codableModel: ModelWithIgnoredPropsCodable {
                    ModelWithIgnoredPropsCodable(
                        id: id,
                        name: name
                    )
                }

                func replace(_ model: ModelWithIgnoredPropsCodable) {
                    id = model.id
                    name = model.name
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
