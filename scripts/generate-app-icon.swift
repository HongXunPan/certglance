import AppKit
import Foundation

@main
struct AppIconGenerator {
  @MainActor
  static func main() throws {
    let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(
      at: folder, withIntermediateDirectories: true)

    let variants: [(String, String, Int)] = [
      ("16x16", "1x", 16), ("16x16", "2x", 32),
      ("32x32", "1x", 32), ("32x32", "2x", 64),
      ("128x128", "1x", 128), ("128x128", "2x", 256),
      ("256x256", "1x", 256), ("256x256", "2x", 512),
      ("512x512", "1x", 512), ("512x512", "2x", 1024),
    ]
    var images: [[String: String]] = []
    for (size, scale, pixels) in variants {
      let filename = "icon-\(size)-\(scale).png"
      try render(pixels: pixels).write(to: folder.appendingPathComponent(filename))
      images.append([
        "filename": filename, "idiom": "mac", "size": size, "scale": scale,
      ])
    }
    let contents: [String: Any] = [
      "images": images,
      "info": ["author": "xcode", "version": 1],
    ]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
      .write(to: folder.appendingPathComponent("Contents.json"))
  }

  @MainActor
  private static func render(pixels: Int) throws -> Data {
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
      throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let background = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    NSGradient(
      starting: NSColor(calibratedRed: 0.03, green: 0.25, blue: 0.43, alpha: 1),
      ending: NSColor(calibratedRed: 0.10, green: 0.48, blue: 0.71, alpha: 1)
    )?.draw(in: background, angle: 30)

    let paper = NSBezierPath(
      roundedRect: NSRect(x: 220, y: 166, width: 570, height: 692),
      xRadius: 92, yRadius: 92)
    NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
    paper.fill()

    NSColor(calibratedRed: 0.13, green: 0.39, blue: 0.57, alpha: 1).setFill()
    NSBezierPath(
      roundedRect: NSRect(x: 320, y: 650, width: 370, height: 56),
      xRadius: 28, yRadius: 28
    ).fill()
    NSColor(calibratedRed: 0.59, green: 0.75, blue: 0.84, alpha: 1).setFill()
    NSBezierPath(
      roundedRect: NSRect(x: 320, y: 530, width: 275, height: 36),
      xRadius: 18, yRadius: 18
    ).fill()
    NSBezierPath(
      roundedRect: NSRect(x: 320, y: 450, width: 220, height: 36),
      xRadius: 18, yRadius: 18
    ).fill()

    let clock = NSBezierPath(ovalIn: NSRect(x: 555, y: 146, width: 280, height: 280))
    NSColor(calibratedRed: 0.96, green: 0.42, blue: 0.12, alpha: 1).setFill()
    clock.fill()
    NSColor.white.setStroke()
    let hand = NSBezierPath()
    hand.lineWidth = 28
    hand.lineCapStyle = .round
    hand.move(to: NSPoint(x: 695, y: 337))
    hand.line(to: NSPoint(x: 695, y: 286))
    hand.line(to: NSPoint(x: 743, y: 255))
    hand.stroke()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    return png
  }
}
