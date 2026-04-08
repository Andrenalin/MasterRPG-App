// @copyright André Trettin

import SwiftUI

@Observable
final class HeaderScrollModel {
    var headerOffset: CGFloat = 0
    var headerSize: CGFloat = 0
    var scrollUp: Bool = false
}

struct HeaderContentScrollView<Header: View, Content: View, Background: View>: View {
    init(model: HeaderScrollModel, @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content, @ViewBuilder background: () -> Background) {
        self.model = model
        self.header = header()
        self.content = content()
        self.background = background()
    }

    let model: HeaderScrollModel

    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var background: Background

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) {
                max($0.contentOffset.y + $0.contentInsets.top, 0)
            } action: { oldValue, newValue in
                let direction = (newValue - oldValue) > 0 ? true : false
                if abs(newValue - oldValue) > 20 && model.scrollUp != direction {
                    model.scrollUp = direction
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if model.scrollUp {
                            model.headerOffset = model.headerSize
                        } else {
                            model.headerOffset = 0
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                headerView
            }
    }

    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: { newValue in
                    model.headerSize = newValue
                }
        }
        .offset(y: -model.headerOffset)
        .clipped()
        .background {
            background
                .ignoresSafeArea()
                .offset(y: -model.headerOffset)
        }
    }
}

#Preview {
    @Previewable @State var model = HeaderScrollModel()

    HeaderContentScrollView(model: model) {
        HStack(spacing: 15) {
            Button {

            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            Text("Apple Store")
                .fontWeight(.semibold)
        }
        .padding(15)
    } content: {
        Group {
#if os(macOS)
            ScrollView {
                Form {
                    VStack(spacing: 15) {
                        ForEach(1...100, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 15)
                                .fill(.gray.opacity(0.35))
                                .frame(height: 50)
                        }
                    }
                    .padding(15)
                }
            }
#else
            Form {
                VStack(spacing: 15) {
                    ForEach(1...100, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 15)
                            .fill(.gray.opacity(0.35))
                            .frame(height: 50)
                    }
                }
                .padding(15)
            }
#endif
        }
    } background: {
        Rectangle().fill(Color.orange.gradient)
    }
}
