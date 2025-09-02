
import Foundation

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `@CodableIgnored` macro that marks properties to be excluded from Codable generation.
public struct CodableIgnoredMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // This macro doesn't generate any code, it's just a marker
        return []
    }
}

/// Implementation of the `@CodableModel` macro that generates a Codable companion struct
/// for SwiftData models and adds conversion methods to the original model.
public struct CodableModelMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw MacroError.notAClass
        }
        
        // Extract class name
        let className = classDecl.name.text
        let codableStructName: String = "\(className)Codable"

        // Extract stored properties (excluding computed properties, functions, etc.)
        let storedProperties = extractStoredProperties(from: classDecl)
        
        // Process properties to handle private relationship properties with public getters
        let allProperties = processRelationshipProperties(storedProperties)
        
        // Generate the Codable struct as a nested type
        let codableStruct = generateCodableStruct(
            name: codableStructName,
            properties: allProperties
        )
        
        // Generate conversion methods
        let conversionMethods = generateConversionMethods(
            className: className,
            codableStructName: codableStructName,
            properties: allProperties
        )
        
        return [DeclSyntax(codableStruct)] + conversionMethods
    }
    
    private static func extractStoredProperties(from classDecl: ClassDeclSyntax) -> [PropertyInfo] {
        var properties: [PropertyInfo] = []
        
        for member in classDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self),
               !varDecl.modifiers.contains(where: { $0.name.text == "static" }) {
                
                for binding in varDecl.bindings {
                    if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        let name = pattern.identifier.text
                        
                        // Skip SwiftData internal properties (ending with underscore) except for relationship properties
                        if name.hasSuffix("_") && !isSwiftDataRelationshipProperty(varDecl) {
                            continue
                        }
                        
                        let type = extractType(from: binding)
                        let isTransient = varDecl.attributes.contains { attr in
                            if case .attribute(let attribute) = attr,
                               let identifierType = attribute.attributeName.as(IdentifierTypeSyntax.self) {
                                return identifierType.name.text == "Transient"
                            }
                            return false
                        }
                        
                        let isCodableIgnored = varDecl.attributes.contains { attr in
                            if case .attribute(let attribute) = attr,
                               let identifierType = attribute.attributeName.as(IdentifierTypeSyntax.self) {
                                return identifierType.name.text == "CodableIgnored"
                            }
                            return false
                        }
                        let hasRelationshipAttribute = isSwiftDataRelationshipProperty(varDecl)
                        let isRelationship = isSwiftDataRelationship(type: type)
                        let isCodableArray = isCodableModelArray(type: type)
                        let defaultValue = binding.initializer?.value.description
                        
                        // Skip properties marked with @CodableIgnored
                        if !isCodableIgnored {
                            // Include all other properties - relationships will be processed later
                            properties.append(PropertyInfo(
                                name: name,
                                type: type,
                                isTransient: isTransient,
                                isRelationship: isRelationship,
                                defaultValue: defaultValue,
                                isCodableArray: isCodableArray,
                                originalType: type,
                                hasRelationshipAttribute: hasRelationshipAttribute
                            ))
                        }
                    }
                }
            }
        }
        
        return properties
    }
    
    private static func processRelationshipProperties(_ properties: [PropertyInfo]) -> [PropertyInfo] {
        var result: [PropertyInfo] = []
        
        for property in properties {
            // Check if this is a private relationship property ending with underscore that has @Relationship attribute
            if property.name.hasSuffix("_") && property.hasRelationshipAttribute {
                // Convert private relationship property to public getter name
                let publicName = String(property.name.dropLast()) // Remove the underscore
                
                // Convert optional type to non-optional for the public interface
                let nonOptionalType = property.originalType.replacingOccurrences(of: "?", with: "")
                let isCodableArray = isCodableModelArray(type: nonOptionalType)
                let codableType = isCodableArray ? getCodableArrayType(nonOptionalType) : nonOptionalType
                
                // Add as public property with proper type
                result.append(PropertyInfo(
                    name: publicName,
                    type: codableType,
                    isTransient: false,
                    isRelationship: true,
                    defaultValue: isCodableArray ? "[]" : nil,
                    isCodableArray: isCodableArray,
                    originalType: nonOptionalType
                ))
            } else if property.isRelationship && !property.name.hasSuffix("_") {
                // Skip direct relationships that aren't arrays (like parent: DiceDataModel?)
                continue
            } else {
                // Keep non-relationship properties as-is
                result.append(property)
            }
        }
        
        return result
    }
    

    
    private static func extractType(from binding: PatternBindingSyntax) -> String {
        if let typeAnnotation = binding.typeAnnotation {
            return typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
        }
        
        // Try to infer from initializer
        if let initializer = binding.initializer {
            let initValue = initializer.value.description.trimmingCharacters(in: .whitespaces)
            
            // Common type inference patterns
            if initValue == "UUID()" { return "UUID" }
            if initValue.contains("[]") { return "[\(inferArrayType(from: initValue))]" }
            if initValue.contains("\"") { return "String" }
            if initValue.contains(".") && !initValue.contains("\"") { return "Double" }
            if initValue == "true" || initValue == "false" { return "Bool" }
            if Int(initValue) != nil { return "Int" }
        }
        
        return "Any" // Fallback
    }
    
    private static func inferArrayType(from initializer: String) -> String {
        if initializer.contains("[Int]") { return "Int" }
        if initializer.contains("[String]") { return "String" }
        return "Any"
    }
    
    private static func isSwiftDataRelationship(type: String) -> Bool {
        // Check for optional relationships that should be excluded
        return type.hasSuffix("DataModel?") || 
               (type.hasSuffix("DataModel") && !type.hasPrefix("["))
    }
    
    private static func isSwiftDataRelationshipProperty(_ varDecl: VariableDeclSyntax) -> Bool {
        // Check if this variable has the @Relationship attribute
        return varDecl.attributes.contains { attr in
            if case .attribute(let attribute) = attr,
               let identifierType = attribute.attributeName.as(IdentifierTypeSyntax.self) {
                return identifierType.name.text == "Relationship"
            }
            return false
        }
    }
    
    private static func isSwiftDataRelationshipProperty(_ property: PropertyInfo) -> Bool {
        // For PropertyInfo, we need to check if it's a relationship based on type patterns
        // This is a simplified check - in a real implementation, we'd need to track the @Relationship attribute
        return property.isRelationship || 
               property.type.contains("DataModel") ||
               property.originalType.contains("DataModel")
    }
    
    private static func isCodableModelArray(type: String) -> Bool {
        // Check if this is an array of models that have Codable companions
        return type.hasPrefix("[") && type.contains("DataModel") && type.hasSuffix("]")
    }
    
    private static func getCodableArrayType(_ type: String) -> String {
        // Convert [DieDataModel] to [DieDataModelCodable]
        if type.hasPrefix("[") && type.hasSuffix("]") {
            let innerType = String(type.dropFirst().dropLast())
            if innerType.hasSuffix("DataModel") {
                return "[\(innerType)Codable]"
            }
        }
        return type
    }
    
    private static func generateCodableStruct(name: String, properties: [PropertyInfo]) -> StructDeclSyntax {
        let structDecl = try! StructDeclSyntax("struct \(raw: name): Equatable, Hashable, Codable, Sendable") {
            // Generate initializer
            generateInitializer(properties: properties)
            
            // Generate properties
            for property in properties {
                if let defaultValue = property.defaultValue {
                    "var \(raw: property.name): \(raw: property.type) = \(raw: defaultValue)"
                } else {
                    "var \(raw: property.name): \(raw: property.type)"
                }
            }
        }
        
        return structDecl
    }
    
    private static func generateInitializer(properties: [PropertyInfo]) -> InitializerDeclSyntax {
        let parameters = properties.map { property in
            if let defaultValue = property.defaultValue {
                return "\(property.name): \(property.type) = \(defaultValue)"
            } else {
                return "\(property.name): \(property.type)"
            }
        }.joined(separator: ", ")
        
        let assignments = properties.map { property in
            return "self.\(property.name) = \(property.name)"
        }.joined(separator: "\n        ")
        
        return try! InitializerDeclSyntax("init(\(raw: parameters))") {
            "\(raw: assignments)"
        }
    }
    
    private static func generateConversionMethods(
        className: String,
        codableStructName: String,
        properties: [PropertyInfo]
    ) -> [DeclSyntax] {
        
        // Unused for now, but kept for potential future use
        // let propertyAssignments = properties.map { "\($0.name): model.\($0.name)" }.joined(separator: ",\n            ")
        
        let codableAssignments = properties.map { property in
            if property.isCodableArray {
                // Convert array of SwiftData models to Codable models
                return "\(property.name): \(property.name).map { $0.codableModel }"
            } else {
                return "\(property.name): \(property.name)"
            }
        }.joined(separator: ",\n            ")
        
        let replaceAssignments = properties.map { property in
            if property.isCodableArray {
                // Convert array of Codable models back to SwiftData models
                let innerType = property.originalType.dropFirst().dropLast() // Remove [ ]
                return "\(property.name) = model.\(property.name).map { \(innerType)($0) }"
            } else {
                return "\(property.name) = model.\(property.name)"
            }
        }.joined(separator: "\n        ")
        
        // Generate assignments for the convenience initializer body
        let assignmentStatements = properties.map { property in
            if property.isCodableArray {
                // Convert array of Codable models back to SwiftData models
                let innerType = property.originalType.dropFirst().dropLast() // Remove [ ]
                return "self.\(property.name) = model.\(property.name).map { \(innerType)($0) }"
            } else {
                return "self.\(property.name) = model.\(property.name)"
            }
        }.joined(separator: "\n        ")
        
        let convenienceInit = try! InitializerDeclSyntax("convenience init(_ model: \(raw: codableStructName))") {
            """
            self.init()
            \(raw: assignmentStatements)
            """
        }
        
        let codableProperty = try! VariableDeclSyntax("var codableModel: \(raw: codableStructName)") {
            """
            \(raw: codableStructName)(
                \(raw: codableAssignments)
            )
            """
        }
        
        let replaceMethod = try! FunctionDeclSyntax("func replace(_ model: \(raw: codableStructName))") {
            """
            \(raw: replaceAssignments)
            """
        }
        
        return [
            DeclSyntax(convenienceInit),
            DeclSyntax(codableProperty),
            DeclSyntax(replaceMethod)
        ]
    }
}

// Helper struct to store property information
private struct PropertyInfo {
    let name: String
    let type: String
    let isTransient: Bool
    let isRelationship: Bool
    let defaultValue: String?
    let isCodableArray: Bool
    let originalType: String
    let hasRelationshipAttribute: Bool
    
    init(name: String, type: String, isTransient: Bool, isRelationship: Bool, defaultValue: String?, isCodableArray: Bool = false, originalType: String? = nil, hasRelationshipAttribute: Bool = false) {
        self.name = name
        self.type = type
        self.isTransient = isTransient
        self.isRelationship = isRelationship
        self.defaultValue = defaultValue
        self.isCodableArray = isCodableArray
        self.originalType = originalType ?? type
        self.hasRelationshipAttribute = hasRelationshipAttribute
    }
}



// Error types for the macro
enum MacroError: Error, CustomStringConvertible {
    case notAClass
    
    var description: String {
        switch self {
        case .notAClass:
            return "@CodableModel can only be applied to classes"
        }
    }
}

@main
struct CodableModelPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        CodableModelMacro.self,
        CodableIgnoredMacro.self,
    ]
}
