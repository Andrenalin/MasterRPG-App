// @copyright André Trettin

import SwiftUI

public enum TextInputAutocapitalizationAll: Int, Sendable {
    case never = 0
    case words = 1
    case sentences = 2
    case characters = 3
}

public enum TextContentTypeAll: Sendable {
    case name
}

public extension View {
    nonisolated func textInputAutocapitalizationAll(_ autocapitalization: TextInputAutocapitalizationAll) -> some View {
        self.modifier(TextInputAutocapitalizationAllViewModifier(type: autocapitalization))
    }
    
}

struct TextInputAutocapitalizationAllViewModifier: ViewModifier {
    let type: TextInputAutocapitalizationAll
    
    func body(content: Content) -> some View {
#if os(macOS)
        content
#else
        content
            .textInputAutocapitalization(typeConvert)
#endif
    }
    
#if !os(macOS)
    var typeConvert: TextInputAutocapitalization {
        switch type {
        case .never:
            return .never
        case .words:
            return .words
        case .sentences:
            return .sentences
        case .characters:
            return .characters
        }
    }
#endif
}

nonisolated public struct TextContentTypeAllViewModifier: ViewModifier {
    public init(type: TextContentTypeAll? = nil) {
        self.type = type
    }
    
    let type: TextContentTypeAll?
    
    public func body(content: Content) -> some View {
#if os(iOS)
        content
            .textContentType(typeConvert)
#else
        content
#endif
    }
    
#if os(iOS)
    var typeConvert: UITextContentType? {
        guard let type else { return nil }
        switch type {
        case .name:
            return .name
        }
    }
#endif
}
