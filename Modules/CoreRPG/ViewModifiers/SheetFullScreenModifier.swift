// @copyright André Trettin

import SwiftUI

public extension View {
    func sizedSheet<Content: View>(isPresented: Binding<Bool>, idealSize: CGSize = CGSize(width: 1000, height: 800), onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(SizedSheetViewModifier(isPresented: isPresented, idealSize: idealSize, sheetContent: content, onDismiss: onDismiss))
    }
}

/// Ideal sizes for `sizedSheet`. They apply only on macOS, where a sheet takes its content's ideal
/// size and the window can still be resized; other platforms size sheets themselves.
/// See CODE_AUDIT_Since_3.0.1 §8.1.
public extension CGSize {
    /// A sheet with a short panel of choices, such as the affected-links panel.
    static let panelSheet = CGSize(width: 400, height: 600)
    /// A sheet that lists items to pick from, such as the Quick Link table picker.
    static let pickerSheet = CGSize(width: 500, height: 700)
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
                ManagedPresentationView {
                    sheetContent()
                        .frame(idealWidth: idealSize.width, idealHeight: idealSize.height)
                        .environment(\.colorScheme, colorScheme)
                }
            }
#elseif os(tvOS)
            .fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
                ManagedPresentationView {
                    sheetContent()
                        .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
                        .environment(\.colorScheme, colorScheme)
                }
            }
#else
            .sheet(isPresented: isPresented, onDismiss: onDismiss) {
                ManagedPresentationView {
                    sheetContent()
                        .environment(\.colorScheme, colorScheme)
                }
            }
#endif
    }
}
