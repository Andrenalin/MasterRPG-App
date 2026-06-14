//
//  SwiftUIView.swift
//  
//
//  Created by Andre Trettin on 13/11/2566 BE.
//

import SwiftUI

struct AnimatorView: View {
    @State private var showOne = false
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
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { showOne = false }
                }
            }
        }
        .animation(.easeInOut(duration: 2).delay(1), value: showOne)
        .onAppear {
            withAnimation { showOne = true }
        }
    }
}

#Preview {
    AnimatorView()
}
