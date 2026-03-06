import AppKit

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

let iconsetPath = "AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for entry in sizes {
    let s = CGFloat(entry.size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Background: rounded rect with gradient
    let radius = s * 0.2
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // Gradient background (blue to darker blue)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1.0),
        CGColor(red: 0.15, green: 0.35, blue: 0.75, alpha: 1.0),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // Helper to draw a tinted SF Symbol
    func drawSymbol(_ name: String, pointSize: CGFloat, color: NSColor, in rect: NSRect) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        let configured = symbol.withSymbolConfiguration(config)!
        let tinted = NSImage(size: configured.size)
        tinted.lockFocus()
        color.set()
        let tintRect = NSRect(origin: .zero, size: configured.size)
        configured.draw(in: tintRect)
        tintRect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: rect)
    }

    // Draw cloud symbol
    if let cloudSymbol = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: s * 0.45, weight: .bold)
        let configured = cloudSymbol.withSymbolConfiguration(config)!
        let symbolSize = configured.size
        let cloudX = (s - symbolSize.width) / 2
        let cloudY = (s - symbolSize.height) / 2 + s * 0.08
        drawSymbol("cloud.fill", pointSize: s * 0.45, color: NSColor.white.withAlphaComponent(0.95),
                   in: NSRect(x: cloudX, y: cloudY, width: symbolSize.width, height: symbolSize.height))
    }

    // Draw key symbol (smaller, bottom-right area)
    if let keySymbol = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: s * 0.22, weight: .bold)
        let configured = keySymbol.withSymbolConfiguration(config)!
        let symbolSize = configured.size
        let keyX = (s - symbolSize.width) / 2 + s * 0.12
        let keyY = (s - symbolSize.height) / 2 - s * 0.12
        // Draw a small background circle
        let circleSize = max(symbolSize.width, symbolSize.height) * 1.4
        let circleX = keyX + (symbolSize.width - circleSize) / 2
        let circleY = keyY + (symbolSize.height - circleSize) / 2
        NSColor(red: 0.1, green: 0.25, blue: 0.6, alpha: 0.7).setFill()
        NSBezierPath(ovalIn: NSRect(x: circleX, y: circleY, width: circleSize, height: circleSize)).fill()

        drawSymbol("key.fill", pointSize: s * 0.22, color: NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1.0),
                   in: NSRect(x: keyX, y: keyY, width: symbolSize.width, height: symbolSize.height))
    }

    image.unlockFocus()

    // Save as PNG
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Failed to create PNG for \(entry.name)\n", stderr)
        continue
    }
    let filePath = "\(iconsetPath)/\(entry.name).png"
    try! pngData.write(to: URL(fileURLWithPath: filePath))
}

print("Iconset created at \(iconsetPath)")
