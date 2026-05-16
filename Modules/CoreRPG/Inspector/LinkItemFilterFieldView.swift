// @copyright André Trettin

import SwiftUI

/// Filter field subview — @Bindable allocation and Text prompt construction are scoped here,
/// not recomputed on every parent body update.
struct LinkItemFilterFieldView: View {
    @Bindable var searchModel: SearchModel
    let prompt: Text
    let onSearchChange: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            TextField(text: $searchModel.searchText, prompt: prompt) {
                prompt
            }
            .textInputAutocapitalizationAll(.never)
            .textContentTypeAll(.name)
            .disableAutocorrection(true)
            .labelsHidden()
            .submitLabel(.return)
            .textFieldStyle(.plain)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.secondary, lineWidth: 1)
        }
        .padding(.horizontal)
        .onChange(of: searchModel.searchText) {
            withAnimation {
                onSearchChange()
            }
        }
    }
}
