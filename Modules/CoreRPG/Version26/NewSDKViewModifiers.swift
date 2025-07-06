//
//  NewSDKViewModifiers.swift
//  MasterRPG
//
//  Created by Andre Trettin on 06.07.25.
//

import SwiftUI

public extension View {
    func backgroundExtensionEffect26() -> some View {
        modifier(BackgroundExtensionEffect())
    }
}
 
private struct BackgroundExtensionEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            content.backgroundExtensionEffect()
        } else {
            content
        }
    }
}
