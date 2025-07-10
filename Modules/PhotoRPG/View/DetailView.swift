// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailView: View {
    @Environment(\.isSearching) private var isSearching
    
    let model: PhotoDataModel

    @State private var name = ""
    
    var body: some View {
        @Bindable var model = model
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 8) {
                PlainPhotoView(model: model)
                    .stretchy()

                MainRowView(model: model)
                
                TextField(text: $name) {
                    Text("Name:")
                }
                .onSubmit {
                    if model.name != name {
                        withAnimation { model.reset(name: name) }
                    }
                }
                .onAppear {
                    name = model.name
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .ignoresSafeArea(edges: .top)
        .toolbar(removing: .title)
    }
}

struct ImageHeaderView: View {
    var body: some View {
        Image(decorative: "1022")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
            .backgroundExtensionEffect26()
            .overlay(alignment: .bottom) {
                VStack {
                    Text("Featured Landmark", comment: "Big headline in the main image of featured landmarks.")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .opacity(0.8)
                    Text("Kirchenberg")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Button("Learn More") {
                        
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 6)
                }
                .padding([.bottom], 40)
            }
    }
}
