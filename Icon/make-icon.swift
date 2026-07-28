// Renders the Find App icon.
//   swift Icon/make-icon.swift [output.png]   (default: build/icon_1024.png)
import AppKit

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "build/icon_1024.png"

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError() }

// macOS-style squircle with standard transparent margin (~100px at 1024).
let margin: CGFloat = 100
let rect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

// Background gradient: deep indigo -> vivid blue.
squircle.setClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.10, blue: 0.52, alpha: 1),
    NSColor(calibratedRed: 0.22, green: 0.45, blue: 0.98, alpha: 1),
])!
gradient.draw(in: rect, angle: 90)

// Subtle grid of "app" tiles behind the glass.
let tileSize: CGFloat = 148
let gap: CGFloat = 56
let gridW = 3 * tileSize + 2 * gap
let gx = rect.midX - gridW / 2
let gy = rect.midY - gridW / 2
for row in 0..<3 {
    for col in 0..<3 {
        let tile = CGRect(x: gx + CGFloat(col) * (tileSize + gap),
                          y: gy + CGFloat(row) * (tileSize + gap),
                          width: tileSize, height: tileSize)
        let path = NSBezierPath(roundedRect: tile, xRadius: 36, yRadius: 36)
        NSColor.white.withAlphaComponent(0.22).setFill()
        path.fill()
    }
}

// Magnifying glass: lens ring + handle unioned into ONE path so the
// shadow renders as a single clean silhouette.
let lensCenter = CGPoint(x: rect.midX - 40, y: rect.midY + 40)
let lensRadius: CGFloat = 200
let strokeW: CGFloat = 58

// Lens glass fill (slight frosted tint), no shadow.
NSColor.white.withAlphaComponent(0.14).setFill()
NSBezierPath(ovalIn: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
                            width: lensRadius * 2, height: lensRadius * 2)).fill()

let ring = CGPath(ellipseIn: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
                                    width: lensRadius * 2, height: lensRadius * 2),
                  transform: nil)
    .copy(strokingWithWidth: strokeW, lineCap: .butt, lineJoin: .miter, miterLimit: 10)

// The handle starts far enough out that its round cap stays within the ring
// band and never intrudes into the lens glass, while still overlapping the
// ring enough to union into one solid shape.
let handleWidth: CGFloat = 84
let ringInner = lensRadius - strokeW / 2
let ringOuter = lensRadius + strokeW / 2
let handleStart = max(ringInner + handleWidth / 2 + 8, ringOuter - 12)

let dir = CGVector(dx: cos(-CGFloat.pi / 4), dy: sin(-CGFloat.pi / 4))
let handleLine = CGMutablePath()
handleLine.move(to: CGPoint(x: lensCenter.x + dir.dx * handleStart,
                            y: lensCenter.y + dir.dy * handleStart))
handleLine.addLine(to: CGPoint(x: lensCenter.x + dir.dx * (lensRadius + 210),
                               y: lensCenter.y + dir.dy * (lensRadius + 210)))
let handle = handleLine.copy(strokingWithWidth: handleWidth, lineCap: .round,
                             lineJoin: .round, miterLimit: 10)

let glass = ring.union(handle)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40,
              color: NSColor.black.withAlphaComponent(0.45).cgColor)
ctx.addPath(glass)
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillPath(using: .winding)
ctx.restoreGState()

image.unlockFocus()

let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
rep.size = NSSize(width: size, height: size)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
