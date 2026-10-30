#!/usr/bin/env swift

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Resources/DMGBackground.png")
let size = NSSize(width: 660, height: 400)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { fatalError("Could not allocate the DMG background") }
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create the DMG drawing context")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
defer { NSGraphicsContext.restoreGraphicsState() }

let canvas = NSRect(origin: .zero, size: size)
NSGradient(colors: [
    NSColor(calibratedRed: 0.95, green: 0.99, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.95, alpha: 1)
])!.draw(in: canvas, angle: -90)

let glowPath = NSBezierPath(ovalIn: NSRect(x: 420, y: 220, width: 330, height: 260))
NSColor(calibratedRed: 0.15, green: 0.72, blue: 0.68, alpha: 0.13).setFill()
glowPath.fill()

let header = NSBezierPath(roundedRect: NSRect(x: 28, y: 316, width: 604, height: 58), xRadius: 18, yRadius: 18)
NSGradient(colors: [
    NSColor(calibratedRed: 0.03, green: 0.43, blue: 0.42, alpha: 1),
    NSColor(calibratedRed: 0.03, green: 0.58, blue: 0.55, alpha: 1)
])!.draw(in: header, angle: 0)

let titleStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 23, weight: .semibold),
    .foregroundColor: NSColor.white
]
let subtitleStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.82)
]
"SmartClip".draw(at: NSPoint(x: 52, y: 340), withAttributes: titleStyle)
"Local. Encrypted. Yours.".draw(at: NSPoint(x: 52, y: 323), withAttributes: subtitleStyle)

let line = NSBezierPath()
line.move(to: NSPoint(x: 255, y: 210))
line.line(to: NSPoint(x: 405, y: 210))
line.lineWidth = 4
line.lineCapStyle = .round
NSColor(calibratedRed: 0.03, green: 0.48, blue: 0.46, alpha: 0.55).setStroke()
line.stroke()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 390, y: 224))
arrow.line(to: NSPoint(x: 407, y: 210))
arrow.line(to: NSPoint(x: 390, y: 196))
arrow.lineWidth = 4
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.stroke()

let labelStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1)
]
let hintStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.33, alpha: 1)
]

let install = NSMutableParagraphStyle()
install.alignment = .center
var centeredLabel = labelStyle
centeredLabel[.paragraphStyle] = install
var centeredHint = hintStyle
centeredHint[.paragraphStyle] = install

"Drag SmartClip to Applications".draw(in: NSRect(x: 190, y: 78, width: 280, height: 18), withAttributes: centeredLabel)
"First launch: System Settings → Privacy & Security → Open Anyway".draw(
    in: NSRect(x: 95, y: 48, width: 470, height: 18),
    withAttributes: centeredHint
)

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render the DMG background")
}
try png.write(to: output, options: .atomic)
print("Generated \(output.path)")
