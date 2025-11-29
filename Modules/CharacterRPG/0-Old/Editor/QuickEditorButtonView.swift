// @copyright André Trettin

import CoreRPG
import SwiftUI

struct QuickEditorDoubleView: View {
    @Binding var number: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
                rowMinusButtonsView
                rowPlusButtonsView
                    .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private var rowMinusButtonsView: some View {
        HStack(spacing: 12) {
            ForEach([10.0, 5.0, 2.0, 1.0], id: \.self) { value in
                QuickEditorButtonView(number: $number, value: value, title: "\(value.formatted(.number))", isAddition: false)
            }
        }
    }

    private var rowPlusButtonsView: some View {
        HStack(spacing: 12) {
            ForEach([1.0, 2.0, 5.0, 10.0], id: \.self) { value in
                QuickEditorButtonView(number: $number, value: value, title: "\(value.formatted(.number))", isAddition: true)
            }
        }
    }
}

struct QuickEditorIntView: View {
    @Binding var number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            rowMinusButtonsView
            rowPlusButtonsView
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private var rowMinusButtonsView: some View {
        HStack(spacing: 12) {
            ForEach([10, 5, 2, 1], id: \.self) { value in
                QuickEditorButtonView(number: $number, value: value, title: "\(value)", isAddition: false)
            }
        }
    }

    private var rowPlusButtonsView: some View {
        HStack(spacing: 12) {
            ForEach([1, 2, 5, 10], id: \.self) { value in
                QuickEditorButtonView(number: $number, value: value, title: "\(value)", isAddition: true)
            }
        }
    }
}

#Preview {
    @Previewable @State var intNumber = 34
    @Previewable @State var doubleNumber = 2.0

    Group {
        QuickEditorIntView(number: $intNumber)

        QuickEditorDoubleView(number: $doubleNumber)
    }
}
