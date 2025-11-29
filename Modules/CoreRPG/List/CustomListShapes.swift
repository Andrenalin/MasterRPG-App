// @copyright André Trettin

import SwiftUI

struct ListChildShape: Shape {
    let thickness: Double
    let isHalf: Bool
    let upOffset: CGFloat
    var downOffset: CGFloat = 0
    let withoutChild: Bool
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        path.move(to: CGPoint(x: rect.minX + thickness, y: rect.minY - upOffset))
        path.addLine(to: CGPoint(x: rect.minX + thickness, y: rect.midY + thickness))
        
        if withoutChild {
            path.addLine(to: CGPoint(x: rect.minX + thickness * 2, y: rect.midY + thickness))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + thickness / 2))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - thickness / 2))
        }
        
        path.addLine(to: CGPoint(x: rect.minX + thickness * 2, y: rect.midY - thickness))
        path.addLine(to: CGPoint(x: rect.minX + thickness * 2, y: rect.minY - upOffset))
        
        if !isHalf {
            path.move(to: CGPoint(x: rect.minX + thickness, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + thickness, y: rect.maxY + downOffset))
            path.addLine(to: CGPoint(x: rect.minX + thickness * 2, y: rect.maxY + downOffset))
            path.addLine(to: CGPoint(x: rect.minX + thickness * 2, y: rect.midY))
        }
        return path
    }
}

#Preview {
    VStack {
        HStack {
            ListChildShape(thickness: 10, isHalf: false, upOffset: 20, withoutChild: true)
                .fill(.blue)
                .frame(width: 80, height: 200)
                .border(.black, width: 1)
            
            Divider()
            Color.blue
        }
    }
}
