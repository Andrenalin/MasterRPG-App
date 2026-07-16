//
//  SwiftUIView.swift
//  
//
//  Created by Andre Trettin on 13/11/2566 BE.
//

import SwiftUI

struct AnimatorView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    init(animates: Bool = true) {
        self.animates = animates
        self._showOne = State(initialValue: !animates)
    }

    private let animates: Bool
    @State private var showOne: Bool

    var body: some View {
        VStack {
            if showOne {
                VStack {
                    Image(systemName: "plus")
                        .resizable()
                        .frame(width: 200)
                        .font(.largeTitle)
                        .padding()
                        .background(Color.red)
                }
                .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)))
                .task {
                    guard animates else { return }
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(accessibilityReduceMotion ? nil : .default) { showOne = false }
                }
            }
        }
        .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 2).delay(1), value: showOne)
        .onAppear {
            guard animates else { return }
            withAnimation(accessibilityReduceMotion ? nil : .default) { showOne = true }
        }
    }
}

#Preview {
    AnimatorView(animates: false)
}
