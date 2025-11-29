// @copyright André Trettin

import CoreRPG
import CoreGraphics
import SwiftUI

public struct DisplayConfigModel: Identifiable, Equatable, Hashable {
    public init(id: UUID = UUID(), tileCoordinates: [CGPoint], color: Color = .black, border: DisplayBorderViewModel) {
        self.id = id
        self.tileCoordinates = tileCoordinates
        self.color = color
        self.border = border
    }
    
    public let id: UUID
    public var tileCoordinates: [CGPoint]
    public var color: Color = .black
    public var border: DisplayBorderViewModel

    public var borderColor: Color {
        get { border.color }
        set { border.color = newValue }
    }

    public var borderThickness: CGFloat {
        get { border.thickness }
        set { border.thickness = newValue }
    }

    public var borderThicknessDouble: Double {
        get { Double(border.thickness) }
        set { border.thickness = CGFloat(newValue) }
    }

    public var borderText: String {
        get { String("\(border.thickness)") }
        set {
            let value = Double(newValue) ?? 0
            border.thickness = CGFloat(value)
        }
    }

    public var hasBorder: Bool {
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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tileCoordinates, forKey: .tileCoordinates)
        try container.encode(CodableColor(color), forKey: .color)
        try container.encode(border, forKey: .border)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        tileCoordinates = try values.decode([CGPoint].self, forKey: .tileCoordinates)
        let ccolor = try values.decode(CodableColor.self, forKey: .color)
        color = ccolor.color
        border = try values.decode(DisplayBorderViewModel.self, forKey: .border)
    }
}

public struct DisplayBorderViewModel: Identifiable, Equatable, Hashable {
    public init(id: UUID = UUID(), thickness: CGFloat = 0, color: Color = .red) {
        self.id = id
        self.thickness = thickness
        self.color = color
    }
    
    public let id: UUID
    public var thickness: CGFloat = 0
    public var color: Color = .red
}

extension DisplayBorderViewModel: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case thickness
        case color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(thickness, forKey: .thickness)
        try container.encode(CodableColor(color), forKey: .color)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        thickness = try values.decode(CGFloat.self, forKey: .thickness)
        let ccolor = try values.decode(CodableColor.self, forKey: .color)
        color = ccolor.color
    }
}
