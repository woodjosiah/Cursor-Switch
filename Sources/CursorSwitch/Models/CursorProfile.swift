import Foundation

struct CursorProfile: Codable, Equatable {
    var kind: CursorKind = .shape
    var shape: CursorShape = .arrow
    var size: Double = 36
    var fill: CursorColor = .coral
    var outline: CursorColor = .white
    var symbolName = "star.fill"
    var emoji = "✨"
    var imagePNG: Data?
    var imageName: String?
    var hotspot: CursorHotspot = .automatic
    var preservesContextualCursors = false

    init() {}

    // Missing fields from older versions keep their defaults.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decodeIfPresent(CursorKind.self, forKey: .kind) ?? .shape
        shape = try values.decodeIfPresent(CursorShape.self, forKey: .shape) ?? .arrow
        size = try values.decodeIfPresent(Double.self, forKey: .size) ?? 36
        fill = try values.decodeIfPresent(CursorColor.self, forKey: .fill) ?? .coral
        outline = try values.decodeIfPresent(CursorColor.self, forKey: .outline) ?? .white
        symbolName = try values.decodeIfPresent(String.self, forKey: .symbolName) ?? "star.fill"
        emoji = try values.decodeIfPresent(String.self, forKey: .emoji) ?? "✨"
        imagePNG = try values.decodeIfPresent(Data.self, forKey: .imagePNG)
        imageName = try values.decodeIfPresent(String.self, forKey: .imageName)
        hotspot = try values.decodeIfPresent(CursorHotspot.self, forKey: .hotspot) ?? .automatic
        preservesContextualCursors = try values.decodeIfPresent(Bool.self, forKey: .preservesContextualCursors) ?? false
    }

    static let sizeRange = 18.0...120.0

    var sanitized: Self {
        var copy = self
        copy.size = size.isFinite ? min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound) : 36
        copy.fill = fill.sanitized
        copy.outline = outline.sanitized
        copy.symbolName = String(symbolName.prefix(120))
        copy.emoji = String(emoji.prefix(1))
        return copy
    }
}
