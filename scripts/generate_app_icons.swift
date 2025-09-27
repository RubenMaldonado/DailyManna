import Foundation
import CoreGraphics
import ImageIO
import AppKit

// MARK: - Colors

enum IconVariant: String {
    case `default`
    case dark
    case tinted
}

struct IconColors {
    let backgroundTop: NSColor
    let backgroundBottom: NSColor
    let bread: NSColor
    let breadShadow: NSColor
    let checkmark: NSColor

    static let warm: IconColors = .init(
        backgroundTop: NSColor(calibratedRed: 1.00, green: 0.91, blue: 0.68, alpha: 1.0),   // light wheat
        backgroundBottom: NSColor(calibratedRed: 0.96, green: 0.74, blue: 0.33, alpha: 1.0),// warm amber
        bread: NSColor(calibratedRed: 0.58, green: 0.36, blue: 0.16, alpha: 1.0),           // baked crust
        breadShadow: NSColor(calibratedRed: 0.00, green: 0.00, blue: 0.00, alpha: 0.18),    // subtle shadow
        checkmark: NSColor.white
    )

    static let warmDark: IconColors = .init(
        backgroundTop: NSColor(calibratedRed: 0.15, green: 0.14, blue: 0.12, alpha: 1.0),
        backgroundBottom: NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.07, alpha: 1.0),
        bread: NSColor(calibratedRed: 0.82, green: 0.60, blue: 0.36, alpha: 1.0),
        breadShadow: NSColor(calibratedWhite: 0.0, alpha: 0.30),
        checkmark: NSColor.white
    )

    static let warmTinted: IconColors = .init(
        backgroundTop: NSColor(calibratedRed: 0.97, green: 0.90, blue: 0.76, alpha: 1.0),
        backgroundBottom: NSColor(calibratedRed: 0.88, green: 0.74, blue: 0.48, alpha: 1.0),
        bread: NSColor(calibratedRed: 0.52, green: 0.34, blue: 0.18, alpha: 1.0),
        breadShadow: NSColor(calibratedWhite: 0.0, alpha: 0.16),
        checkmark: NSColor.white
    )
}

// MARK: - Palette decoding without extending NSColor
private func colorFromHex(_ hex: String) throws -> NSColor {
    var string = hex.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    if string.hasPrefix("#") { string.removeFirst() }
    let scanner = Scanner(string: string)
    var value: UInt64 = 0
    guard scanner.scanHexInt64(&value) else {
        throw NSError(domain: "DailyMannaIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid hex color: \(hex)"])
    }
    let r, g, b, a: CGFloat
    if string.count == 8 {
        r = CGFloat((value & 0xFF000000) >> 24) / 255.0
        g = CGFloat((value & 0x00FF0000) >> 16) / 255.0
        b = CGFloat((value & 0x0000FF00) >> 8) / 255.0
        a = CGFloat(value & 0x000000FF) / 255.0
    } else if string.count == 6 {
        r = CGFloat((value & 0xFF0000) >> 16) / 255.0
        g = CGFloat((value & 0x00FF00) >> 8) / 255.0
        b = CGFloat(value & 0x0000FF) / 255.0
        a = 1.0
    } else {
        throw NSError(domain: "DailyMannaIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unsupported hex format: \(hex)"])
    }
    return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

private struct PaletteFile: Decodable {
    struct Variant: Decodable {
        let backgroundTop: String
        let backgroundBottom: String
        let bread: String
        let breadShadow: String
        let checkmark: String
    }
    let `default`: Variant
    let dark: Variant
    let tinted: Variant
}

private func loadColors(from url: URL?, variant: IconVariant) -> IconColors {
    guard let url else { return colorsForVariant(variant) }
    do {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let palette = try decoder.decode(PaletteFile.self, from: data)
        let v: PaletteFile.Variant
        switch variant {
        case .default: v = palette.default
        case .dark: v = palette.dark
        case .tinted: v = palette.tinted
        }
        return IconColors(
            backgroundTop: try colorFromHex(v.backgroundTop),
            backgroundBottom: try colorFromHex(v.backgroundBottom),
            bread: try colorFromHex(v.bread),
            breadShadow: try colorFromHex(v.breadShadow),
            checkmark: try colorFromHex(v.checkmark)
        )
    } catch {
        fputs("Failed to load palette: \(error). Falling back to built-ins.\n", stderr)
        return colorsForVariant(variant)
    }
}

private func colorsForVariant(_ variant: IconVariant) -> IconColors {
    switch variant {
    case .default: return .warm
    case .dark: return .warmDark
    case .tinted: return .warmTinted
    }
}

// MARK: - Icon Renderer

final class DailyMannaIconRenderer {
    private let colors: IconColors

    init(colors: IconColors) {
        self.colors = colors
    }

    func renderIcon(pixels: Int) -> CGImage? {
        precondition(pixels > 0)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let width = pixels
        let height = pixels

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw background gradient
        drawBackground(in: context, width: width, height: height)

        // Draw bread with checkmark
        drawBreadAndCheck(in: context, width: width, height: height)

        return context.makeImage()
    }

    // MARK: Drawing Helpers

    private func drawBackground(in context: CGContext, width: Int, height: Int) {
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.saveGState()
        defer { context.restoreGState() }

        let gradientColors = [colors.backgroundTop.cgColor, colors.backgroundBottom.cgColor] as CFArray
        let locations: [CGFloat] = [0.0, 1.0]
        guard let gradient = CGGradient(colorsSpace: context.colorSpace, colors: gradientColors, locations: locations) else {
            context.setFillColor(colors.backgroundBottom.cgColor)
            context.fill(rect)
            return
        }

        // Fill with a smooth top-to-bottom gradient
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: []
        )
    }

    private func drawBreadAndCheck(in context: CGContext, width: Int, height: Int) {
        let w = CGFloat(width)
        let h = CGFloat(height)

        // Bread geometry
        let breadWidth = w * 0.62
        let breadHeight = h * 0.44
        let breadX = (w - breadWidth) / 2.0
        let breadY = h * 0.34
        let breadRect = CGRect(x: breadX, y: breadY, width: breadWidth, height: breadHeight)
        let breadRadius = min(breadRect.width, breadRect.height) * 0.28

        // Shadow under bread for lift
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: max(1, Int(h * 0.012))), blur: h * 0.04, color: colors.breadShadow.cgColor)
        fillRoundedRect(in: context, rect: breadRect, radius: breadRadius, color: colors.bread)
        context.restoreGState()

        // Surface score cuts (three arcs)
        let cutColor = NSColor(calibratedWhite: 1.0, alpha: 0.18).cgColor
        let cutLineWidth = max(1.0, h * 0.02)
        let cutsCenterY = breadRect.maxY - breadRect.height * 0.32
        let cutSpacing = breadRect.width * 0.18
        let firstCutX = breadRect.midX - cutSpacing
        let secondCutX = breadRect.midX
        let thirdCutX = breadRect.midX + cutSpacing
        let cutRadius = breadRect.height * 0.65
        let cutAngle: CGFloat = .pi * 0.18

        drawScoreArc(in: context, center: CGPoint(x: firstCutX, y: cutsCenterY), radius: cutRadius, angle: cutAngle, lineWidth: cutLineWidth, color: cutColor)
        drawScoreArc(in: context, center: CGPoint(x: secondCutX, y: cutsCenterY), radius: cutRadius, angle: cutAngle, lineWidth: cutLineWidth, color: cutColor)
        drawScoreArc(in: context, center: CGPoint(x: thirdCutX, y: cutsCenterY), radius: cutRadius, angle: cutAngle, lineWidth: cutLineWidth, color: cutColor)

        // Checkmark carved onto bread
        let checkWidth = max(1.5, h * 0.065)
        drawCheckmark(in: context,
                      from: CGPoint(x: breadRect.minX + breadRect.width * 0.20, y: breadRect.midY),
                      mid: CGPoint(x: breadRect.minX + breadRect.width * 0.38, y: breadRect.minY + breadRect.height * 0.34),
                      to: CGPoint(x: breadRect.minX + breadRect.width * 0.78, y: breadRect.minY + breadRect.height * 0.70),
                      lineWidth: checkWidth,
                      color: colors.checkmark.cgColor,
                      cap: .round)
    }

    private func fillRoundedRect(in context: CGContext, rect: CGRect, radius: CGFloat, color: NSColor) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    private func drawScoreArc(in context: CGContext, center: CGPoint, radius: CGFloat, angle: CGFloat, lineWidth: CGFloat, color: CGColor) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        // Arc tilted slightly upwards to the right
        let startAngle: CGFloat = .pi * (1.0 - angle)
        let endAngle: CGFloat = .pi * (1.0 + angle)
        context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        context.strokePath()
    }

    private func drawCheckmark(in context: CGContext, from a: CGPoint, mid b: CGPoint, to c: CGPoint, lineWidth: CGFloat, color: CGColor, cap: CGLineCap) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(cap)
        context.setLineJoin(.round)
        context.move(to: a)
        context.addLine(to: b)
        context.addLine(to: c)
        context.strokePath()
    }
}

// MARK: - PNG Writing

func writePNG(_ image: CGImage, to url: URL) throws {
    // Use public.png UTI to avoid deprecated constants
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "DailyMannaIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "DailyMannaIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image destination"])
    }
}

// MARK: - Main

struct IconSpec {
    let filename: String
    let pixels: Int
    let variant: IconVariant
}

func buildIconSpecs() -> [IconSpec] {
    return [
        // iOS marketing (light, dark, tinted variants)
        IconSpec(filename: "AppIcon-iOS-1024.png", pixels: 1024, variant: .default),
        IconSpec(filename: "AppIcon-iOS-1024-dark.png", pixels: 1024, variant: .dark),
        IconSpec(filename: "AppIcon-iOS-1024-tinted.png", pixels: 1024, variant: .tinted),
        // iPhone notification, settings, spotlight, app
        IconSpec(filename: "AppIcon-iphone-20@2x.png", pixels: 40, variant: .default),
        IconSpec(filename: "AppIcon-iphone-20@3x.png", pixels: 60, variant: .default),
        IconSpec(filename: "AppIcon-iphone-29@2x.png", pixels: 58, variant: .default),
        IconSpec(filename: "AppIcon-iphone-29@3x.png", pixels: 87, variant: .default),
        IconSpec(filename: "AppIcon-iphone-40@2x.png", pixels: 80, variant: .default),
        IconSpec(filename: "AppIcon-iphone-40@3x.png", pixels: 120, variant: .default),
        IconSpec(filename: "AppIcon-iphone-60@2x.png", pixels: 120, variant: .default),
        IconSpec(filename: "AppIcon-iphone-60@3x.png", pixels: 180, variant: .default),
        // iPad notification, settings, spotlight, app
        IconSpec(filename: "AppIcon-ipad-20@1x.png", pixels: 20, variant: .default),
        IconSpec(filename: "AppIcon-ipad-20@2x.png", pixels: 40, variant: .default),
        IconSpec(filename: "AppIcon-ipad-29@1x.png", pixels: 29, variant: .default),
        IconSpec(filename: "AppIcon-ipad-29@2x.png", pixels: 58, variant: .default),
        IconSpec(filename: "AppIcon-ipad-40@1x.png", pixels: 40, variant: .default),
        IconSpec(filename: "AppIcon-ipad-40@2x.png", pixels: 80, variant: .default),
        IconSpec(filename: "AppIcon-ipad-76@1x.png", pixels: 76, variant: .default),
        IconSpec(filename: "AppIcon-ipad-76@2x.png", pixels: 152, variant: .default),
        IconSpec(filename: "AppIcon-ipad-83.5@2x.png", pixels: 167, variant: .default),
        // macOS icon set (default palette only)
        IconSpec(filename: "AppIcon-mac-16@1x.png", pixels: 16, variant: .default),
        IconSpec(filename: "AppIcon-mac-16@2x.png", pixels: 32, variant: .default),
        IconSpec(filename: "AppIcon-mac-32@1x.png", pixels: 32, variant: .default),
        IconSpec(filename: "AppIcon-mac-32@2x.png", pixels: 64, variant: .default),
        IconSpec(filename: "AppIcon-mac-128@1x.png", pixels: 128, variant: .default),
        IconSpec(filename: "AppIcon-mac-128@2x.png", pixels: 256, variant: .default),
        IconSpec(filename: "AppIcon-mac-256@1x.png", pixels: 256, variant: .default),
        IconSpec(filename: "AppIcon-mac-256@2x.png", pixels: 512, variant: .default),
        IconSpec(filename: "AppIcon-mac-512@1x.png", pixels: 512, variant: .default),
        IconSpec(filename: "AppIcon-mac-512@2x.png", pixels: 1024, variant: .default),
    ]
}

func main() throws {
    let args = CommandLine.arguments
    var outputPath: String?
    var configPath: String?
    var index = 1
    while index < args.count {
        let arg = args[index]
        if arg == "--config", index + 1 < args.count {
            configPath = args[index + 1]
            index += 2
        } else {
            outputPath = arg
            index += 1
        }
    }
    guard let outputPath else {
        fputs("Usage: swift generate_app_icons.swift [--config palette.json] <output_appiconset_directory>\n", stderr)
        exit(2)
    }
    let outputDir = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

    let specs = buildIconSpecs()

    for spec in specs {
        autoreleasepool {
            let paletteURL = configPath.map { URL(fileURLWithPath: $0) }
            let colors = loadColors(from: paletteURL, variant: spec.variant)
            let renderer = DailyMannaIconRenderer(colors: colors)
            if let image = renderer.renderIcon(pixels: spec.pixels) {
                let url = outputDir.appendingPathComponent(spec.filename)
                do {
                    try writePNG(image, to: url)
                    print("Wrote \(url.path)")
                } catch {
                    fputs("Failed to write \(spec.filename): \(error)\n", stderr)
                }
            } else {
                fputs("Failed to render image: \(spec.filename)\n", stderr)
            }
        }
    }
}

try main()


