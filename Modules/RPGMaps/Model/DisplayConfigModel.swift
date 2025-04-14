// @copyright André Trettin

import AndrenalinKit
import CoreGraphics
import SwiftUI

struct DisplayConfigModel: Identifiable, Equatable, Hashable {
    let id: UUID
    var tileCoordinates: [CGPoint]
    var color: Color = .black
    var border: DisplayBorderViewModel

    var borderColor: Color {
        get { border.color }
        set { border.color = newValue }
    }

    var borderThickness: CGFloat {
        get { border.thickness }
        set { border.thickness = newValue }
    }

    var borderThicknessDouble: Double {
        get { Double(border.thickness) }
        set { border.thickness = CGFloat(newValue) }
    }

    var borderText: String {
        get { String("\(border.thickness)") }
        set {
            let value = Double(newValue) ?? 0
            border.thickness = CGFloat(value)
        }
    }

    var hasBorder: Bool {
        get { borderThickness > 0 }
        set {
            if newValue {
                if borderThickness == 0 {
                    borderThickness = 4
                }
            } else {
                borderThickness = 0
            }
        }
    }
}

extension DisplayConfigModel: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case tileCoordinates
        case color
        case border
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tileCoordinates, forKey: .tileCoordinates)
        try container.encode(CodableColor(color), forKey: .color)
        try container.encode(border, forKey: .border)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        tileCoordinates = try values.decode([CGPoint].self, forKey: .tileCoordinates)
        let ccolor = try values.decode(CodableColor.self, forKey: .color)
        color = ccolor.color
        border = try values.decode(DisplayBorderViewModel.self, forKey: .border)
    }
}

struct DisplayBorderViewModel: Identifiable, Equatable, Hashable {
    let id: UUID
    var thickness: CGFloat = 0
    var color: Color = .red
}

extension DisplayBorderViewModel: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case thickness
        case color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(thickness, forKey: .thickness)
        try container.encode(CodableColor(color), forKey: .color)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        thickness = try values.decode(CGFloat.self, forKey: .thickness)
        let ccolor = try values.decode(CodableColor.self, forKey: .color)
        color = ccolor.color
    }
}
