// @copyright André Trettin

import SwiftUI

public extension View {
    func sheetFullScreen<Content: View>(isPresented: Binding<Bool>, idealSize: CGSize = CGSize(width: 1000, height: 800), onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(SheetFullScreenViewModifier(isPresented: isPresented, idealSize: idealSize, sheetContent: content, onDismiss: onDismiss))
    }

    func sizedSheet<Content: View>(isPresented: Binding<Bool>, idealSize: CGSize = CGSize(width: 1000, height: 800), onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(SizedSheetViewModifier(isPresented: isPresented, idealSize: idealSize, sheetContent: content, onDismiss: onDismiss))
    }
}

struct SizedSheetViewModifier<SheetContent: View>: ViewModifier {
    let isPresented: Binding<Bool>
    let idealSize: CGSize
    let sheetContent: () -> SheetContent
    let onDismiss: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
#if os(macOS)
            .sheet(isPresented: isPresented, onDismiss: onDismiss) {
                sheetContent()
                    .frame(idealWidth: idealSize.width, idealHeight: idealSize.height)
                    .environment(\.colorScheme, colorScheme)
            }
#elseif os(tvOS)
            .fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
                sheetContent()
                    .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
                    .environment(\.colorScheme, colorScheme)
            }
#else
            .sheet(isPresented: isPresented, onDismiss: onDismiss) {
                sheetContent()
                    .environment(\.colorScheme, colorScheme)
            }
#endif
    }
}

struct SheetFullScreenViewModifier<SheetContent: View>: ViewModifier {
    let isPresented: Binding<Bool>
    let idealSize: CGSize
    let sheetContent: () -> SheetContent
    let onDismiss: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
#if os(macOS)
            .sheet(isPresented: isPresented, onDismiss: onDismiss) {
                sheetContent()
                    .frame(idealWidth: idealSize.width, idealHeight: idealSize.height)
                    .environment(\.colorScheme, colorScheme)
            }
#else
            .fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
                sheetContent()
#if os(tvOS)
                    .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
#endif
                    .environment(\.colorScheme, colorScheme)
            }
#endif
    }
}
