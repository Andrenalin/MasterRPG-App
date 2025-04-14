// @copyright André Trettin

import SwiftUI

public extension View {
    func animatableFont(size: Double, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(AnimatableFontModifier(size: size, weight: weight, design: design))
    }
}

struct AnimatableFontModifier: AnimatableModifier, ViewModifier, @preconcurrency Animatable {
    var size: Double
    var weight: Font.Weight = .regular
    var design: Font.Design = .default

    @MainActor @preconcurrency
    var animatableData: Double {
        get { size }
        set { size = newValue }
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight, design: design))
    }
}
