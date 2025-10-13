// @copyright André Trettin

import SwiftUI

struct HeaderFooterContentScrollView<Header: View, Content: View, Footer: View, Background: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @ViewBuilder var background: Background
    
    @State private var headerOffset: CGFloat = 0
    @State private var footerOffset: CGFloat = 0
    @State private var headerSize: CGFloat = 0
    @State private var footerSize: CGFloat = 0
    
    @State private var scrollUp: Bool = false
    
    var body: some View {
        //let _ = Self._printChanges()
        
        content
            .frame(maxWidth: .infinity)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) {
                max($0.contentOffset.y + $0.contentInsets.top, 0)
            } action: { oldValue, newValue in
                let direction = (newValue - oldValue) > 0 ? true : false
                if abs(newValue - oldValue) > 20 && scrollUp != direction {
                    scrollUp = direction
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if scrollUp {
                            headerOffset = headerSize
                            footerOffset = footerSize
                        } else {
                            headerOffset = 0
                            footerOffset = 0
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                headerView
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footerView
            }
    }
    
    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: { newValue in
                    headerSize = newValue
                }
        }
        .offset(y: -headerOffset)
        .clipped()
        .background {
            background
                .ignoresSafeArea()
                .offset(y: -headerOffset)
        }
    }
    
    @ViewBuilder
    private var footerView: some View {
        VStack(spacing: 0) {
            footer
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: { newValue in
                    footerSize = newValue
                }
        }
        .offset(y: +footerOffset)
        .clipped()
        .background {
            background
                .rotationEffect(Angle(degrees: 180))
                .ignoresSafeArea()
                .offset(y: +footerOffset)
        }
    }
}

#Preview {
    HeaderFooterContentScrollView {
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
    } footer: {
        VStack {
            Label {
                Text("Mage")
                    .font(.largeTitle)
            } icon: {
                Image(systemName: "gear")
                    .font(.largeTitle)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
    } background: {
        Rectangle().fill(Color.orange.gradient)
    }
}
