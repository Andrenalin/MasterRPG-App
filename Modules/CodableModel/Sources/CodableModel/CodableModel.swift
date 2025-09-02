// The Swift Programming Language
// https://docs.swift.org/swift-book

/// A macro that automatically generates a Codable companion struct for SwiftData models
/// and adds conversion methods to the original model.
///
/// When applied to a SwiftData model class, this macro will:
/// - Generate a companion struct with the same properties (excluding relationships)
/// - Add Codable, Equatable, Hashable, and Sendable conformance to the struct
/// - Add a convenience initializer to create the SwiftData model from the Codable struct
/// - Add a computed property to get the Codable representation
/// - Add a replace method to update the SwiftData model from a Codable struct
///
/// Example usage:
///
///     @CodableModel
///     @Model
///     public final class DieDataModel {
///         public var id: UUID = UUID()
///         var index: Int = 0
///         var die: RawDie = RawDie.twenty
///         var color: String = ""
///         
///         @Transient
///         var rotation: Double = 0
///         
///         var parent: DiceDataModel? = nil
///     }
///
/// This will generate:
/// - `DieDataCodableModel` struct with all non-relationship properties
/// - Extension on `DieDataModel` with conversion methods
@attached(member, names: arbitrary)
public macro CodableModel() = #externalMacro(module: "CodableModelMacros", type: "CodableModelMacro")

/// A property wrapper that excludes properties from Codable generation.
/// 
/// Use this attribute on properties that should not be included in the generated
/// Codable companion struct. The property will be skipped during serialization.
///
/// Example usage:
///
///     @CodableModel
///     @Model
///     class MyModel {
///         var id: UUID = UUID()
///         
///         @CodableIgnored
///         var temporaryData: String = ""  // This won't be in the Codable struct
///         
///         @CodableIgnored
///         var computedValue: Int { id.hashValue }  // This won't be in the Codable struct
///     }
@attached(peer)
public macro CodableIgnored() = #externalMacro(module: "CodableModelMacros", type: "CodableIgnoredMacro")
