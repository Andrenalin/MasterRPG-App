import AppKit
import Foundation

// usage: render spec.json shotsDir out.pdf
let args = CommandLine.arguments
let specUrl = URL(fileURLWithPath: args[1])
let shotsDir = URL(fileURLWithPath: args[2])
let outUrl = URL(fileURLWithPath: args[3])

struct Mark: Decodable { let x: Double; let y: Double; let text: String }
struct Page: Decodable {
    let cover: Bool?
    let title: String
    let subtitle: String?
    let text: String?
    let kicker: String?
    let intro: String?
    let image: String
    let marks: [Mark]?
    let tip: String?
}

let pages = try JSONDecoder().decode([Page].self, from: Data(contentsOf: specUrl))

let W: CGFloat = 1400, H: CGFloat = 880
let accent = NSColor(srgbRed: 0.43, green: 0.34, blue: 0.81, alpha: 1)
let ink = NSColor(srgbRed: 0.12, green: 0.11, blue: 0.16, alpha: 1)
let muted = NSColor(srgbRed: 0.38, green: 0.37, blue: 0.43, alpha: 1)
let paper = NSColor(srgbRed: 0.965, green: 0.955, blue: 0.94, alpha: 1)

func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: size, weight: weight) }

func attr(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = ink, line: CGFloat = 1.25) -> NSAttributedString {
    let p = NSMutableParagraphStyle()
    p.lineHeightMultiple = line
    return NSAttributedString(string: s, attributes: [.font: font(size, weight), .foregroundColor: color, .paragraphStyle: p])
}

func height(_ a: NSAttributedString, width: CGFloat) -> CGFloat {
    ceil(a.boundingRect(with: NSSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
}

var mediaBox = CGRect(x: 0, y: 0, width: W, height: H)
guard let ctx = CGContext(outUrl as CFURL, mediaBox: &mediaBox, [kCGPDFContextTitle: "MasterRPG Guide" as CFString, kCGPDFContextAuthor: "MasterRPG" as CFString] as CFDictionary) else { fatalError("pdf") }

func draw(_ a: NSAttributedString, in rect: CGRect) {
    a.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
}

for (index, page) in pages.enumerated() {
    ctx.beginPDFPage(nil)
    // flip so we can lay out from the top
    ctx.translateBy(x: 0, y: H)
    ctx.scaleBy(x: 1, y: -1)
    let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc

    paper.setFill()
    CGRect(x: 0, y: 0, width: W, height: H).fill()

    let image = NSImage(contentsOf: shotsDir.appending(path: "\(page.image).jpg"))!
    let imgSize = image.size
    let colX: CGFloat = 64, colW: CGFloat = 430
    let areaX: CGFloat = 560, areaW: CGFloat = W - 560 - 56
    let aspect = imgSize.width / imgSize.height
    let drawW = min(areaW, (H - 140) * aspect)
    let drawH = drawW / aspect
    let imgRect = CGRect(x: areaX + (areaW - drawW) / 2, y: (H - drawH) / 2, width: drawW, height: drawH)

    // image with shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    let clip = NSBezierPath(roundedRect: imgRect, xRadius: 22, yRadius: 22)
    NSColor.black.setFill()
    clip.fill()
    ctx.restoreGState()
    ctx.saveGState()
    clip.addClip()
    // images are drawn upside down in a flipped context unless respectFlipped
    image.draw(in: imgRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    ctx.restoreGState()

    if page.cover == true {
        draw(attr("MASTERRPG", size: 15, weight: .bold, color: accent), in: CGRect(x: colX, y: 250, width: colW, height: 24))
        draw(attr(page.title, size: 76, weight: .heavy, line: 1.0), in: CGRect(x: colX, y: 280, width: colW + 60, height: 100))
        draw(attr(page.subtitle ?? "", size: 30, weight: .semibold, color: accent, line: 1.1), in: CGRect(x: colX, y: 380, width: colW, height: 80))
        draw(attr(page.text ?? "", size: 18, color: muted, line: 1.35), in: CGRect(x: colX, y: 470, width: colW, height: 140))
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        continue
    }

    // numbered markers on the screenshot
    let scaleX = drawW / 1180, scaleY = drawH / 820
    for (i, m) in (page.marks ?? []).enumerated() {
        let c = CGPoint(x: imgRect.minX + m.x * scaleX, y: imgRect.minY + m.y * scaleY)
        let r: CGFloat = 15
        let circle = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        accent.setFill()
        NSBezierPath(ovalIn: circle).fill()
        ctx.restoreGState()
        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 1, dy: 1))
        ring.lineWidth = 2
        ring.stroke()
        let n = attr("\(i + 1)", size: 15, weight: .bold, color: .white, line: 1.0)
        let sz = n.size()
        n.draw(at: NSPoint(x: c.x - sz.width / 2, y: c.y - sz.height / 2))
    }

    // text column, shrink until it fits
    let marks = page.marks ?? []
    var scale: CGFloat = 1.0
    var layout: (kicker: NSAttributedString, title: NSAttributedString, intro: NSAttributedString, caps: [NSAttributedString], tip: NSAttributedString?, total: CGFloat)!
    func build(_ s: CGFloat) {
        let kicker = attr((page.kicker ?? "").uppercased(), size: 13 * s, weight: .bold, color: accent)
        let title = attr(page.title, size: 38 * s, weight: .heavy, line: 1.05)
        let intro = attr(page.intro ?? "", size: 17 * s, color: muted, line: 1.35)
        let caps = marks.map { attr($0.text, size: 15 * s, color: ink, line: 1.3) }
        let tip = page.tip.map { attr($0, size: 14 * s, color: ink, line: 1.3) }
        var total = height(kicker, width: colW) + 8 + height(title, width: colW) + 14 + height(intro, width: colW) + 26
        for c in caps { total += max(height(c, width: colW - 44), 30) + 12 }
        if let tip { total += 18 + height(tip, width: colW - 36) + 24 }
        layout = (kicker, title, intro, caps, tip, total)
    }
    build(scale)
    while layout.total > H - 150 && scale > 0.7 { scale -= 0.04; build(scale) }

    var y: CGFloat = max(64, (H - layout.total) / 2 - 10)
    draw(layout.kicker, in: CGRect(x: colX, y: y, width: colW, height: 20)); y += height(layout.kicker, width: colW) + 8
    draw(layout.title, in: CGRect(x: colX, y: y, width: colW, height: 200)); y += height(layout.title, width: colW) + 14
    draw(layout.intro, in: CGRect(x: colX, y: y, width: colW, height: 400)); y += height(layout.intro, width: colW) + 26
    for (i, c) in layout.caps.enumerated() {
        let h = max(height(c, width: colW - 44), 30)
        let circle = CGRect(x: colX, y: y, width: 28, height: 28)
        accent.setFill()
        NSBezierPath(ovalIn: circle).fill()
        let n = attr("\(i + 1)", size: 14, weight: .bold, color: .white, line: 1.0)
        let sz = n.size()
        n.draw(at: NSPoint(x: circle.midX - sz.width / 2, y: circle.midY - sz.height / 2))
        draw(c, in: CGRect(x: colX + 44, y: y + 3, width: colW - 44, height: h))
        y += h + 12
    }
    if let tip = layout.tip {
        y += 18
        let h = height(tip, width: colW - 36)
        let box = CGRect(x: colX, y: y, width: colW, height: h + 24)
        accent.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        draw(tip, in: CGRect(x: colX + 18, y: y + 12, width: colW - 36, height: h))
    }

    // footer
    draw(attr("MasterRPG Guide", size: 11, weight: .medium, color: muted), in: CGRect(x: colX, y: H - 40, width: 300, height: 16))
    let num = attr("\(index + 1)", size: 11, weight: .medium, color: muted)
    draw(num, in: CGRect(x: W - 56 - 40, y: H - 40, width: 40, height: 16))

    NSGraphicsContext.restoreGraphicsState()
    ctx.endPDFPage()
}
ctx.closePDF()
print("wrote \(outUrl.path)")
