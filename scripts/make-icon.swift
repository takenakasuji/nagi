#!/usr/bin/env swift
//
// Draw Nagi's app icon and assemble Resources/AppIcon.icns.
//
//   ./scripts/make-icon.swift            # -> Resources/AppIcon.icns
//   ./scripts/make-icon.swift out.icns   # somewhere else
//
// The mark is the one on the site — three lines of wind crossing still water,
// `docs/favicon.svg` and the hero in `docs/index.html`. There is no SVG
// rasteriser on a machine with only the Command Line Tools (no rsvg-convert, no
// ImageMagick), so the three paths are re-drawn here with CoreGraphics instead
// of converted. Keep the coordinates below in step with the SVG: it is still
// the drawing of record, this is a second copy of it.
//
// The result is committed as Resources/AppIcon.icns. build-app.sh does not run
// this — assembling the bundle has to keep working with the Command Line Tools
// alone, and an icon changes about once a year.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - The mark

// The SVG's three paths, in its 48×48 coordinate space (y grows downwards).
//
//   M4 16 h24 a6 6 0 1 0 -6 -6
//   M4 24 h30 a6 6 0 1 1 -6  6
//   M4 32 h18
//
// Each arc is a 270° sweep of radius 6; the SVG endpoint form is resolved to a
// centre here. Path 1 ends at (22,10) turning anticlockwise about (28,10), so
// it reaches y=4; path 2 ends at (28,30) turning clockwise about (34,30) and
// reaches x=40. The centrelines therefore span x 4…40 and y 4…36.
private let markBounds = CGRect(x: 4, y: 4, width: 36, height: 32)

private func makeMarkPath() -> CGPath {
    let path = CGMutablePath()

    // Top line, curling up and back over itself.
    path.move(to: CGPoint(x: 4, y: 16))
    path.addLine(to: CGPoint(x: 28, y: 16))
    path.addArc(center: CGPoint(x: 28, y: 10), radius: 6,
                startAngle: .pi / 2, endAngle: .pi, clockwise: true)

    // Middle line, curling down and back.
    path.move(to: CGPoint(x: 4, y: 24))
    path.addLine(to: CGPoint(x: 34, y: 24))
    path.addArc(center: CGPoint(x: 34, y: 30), radius: 6,
                startAngle: -.pi / 2, endAngle: .pi, clockwise: false)

    // Bottom line, plain.
    path.move(to: CGPoint(x: 4, y: 32))
    path.addLine(to: CGPoint(x: 22, y: 32))

    return path
}

// MARK: - The rounded square

/// macOS draws app icons on a rounded square inset inside the canvas: 824
/// points of artwork in a 1024 point image, corners rounded by 22.5% of the
/// body.
///
/// The corner is a plain **circular** arc, not the continuous "squircle" corner
/// iOS uses — measured, because assuming the continuous corner here produced a
/// noticeably rounder blob than everything next to it in the Dock. Tracing the
/// alpha edge of Notes, Reminders and Calculator gives the same profile to the
/// pixel, and it matches `r - √(r² - (r-d)²)` at r = 0.225 within a thousandth
/// of the body at every depth d. A continuous corner of the same radius reaches
/// 0.344 of the body along each edge; these reach 0.21.
private let bodyFraction: CGFloat = 824.0 / 1024.0
private let cornerFraction: CGFloat = 0.225

// MARK: - Colours

private func srgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

/// The site's accent, `--accent: #0060DF`, lifted slightly at the top so the
/// square does not read as a flat sticker.
private let fillTop = srgb(0x2E7DE5)
private let fillBottom = srgb(0x0060DF)
private let markColor = srgb(0xFFFFFF)

// MARK: - Optical sizing

/// The mark cannot keep the same proportions all the way down. Its three lines
/// sit 8 units apart, so a stroke that reads well at 512pt closes the gaps into
/// a smear once the icon is an inch across. Small sizes get a slightly thinner
/// stroke on a proportionally larger mark, which keeps the gaps open.
///
/// Tuning is by *point* size, not pixels: `icon_16x16@2x.png` is 32 pixels but
/// is displayed at 16 points, so it is tuned as a 16pt icon — unlike
/// `icon_32x32.png`, which happens to be the same number of pixels.
private struct Tuning {
    /// Width of the mark, including its stroke, as a fraction of the body.
    let markFraction: CGFloat
    /// Stroke width in the SVG's 48-unit space.
    let strokeUnits: CGFloat
}

private func tuning(forPointSize points: Int) -> Tuning {
    switch points {
    case ..<32: Tuning(markFraction: 0.80, strokeUnits: 4.0)
    case ..<128: Tuning(markFraction: 0.72, strokeUnits: 4.2)
    default: Tuning(markFraction: 0.62, strokeUnits: 4.4)
    }
}

/// Below 32 pixels the curls stop being drawable: each is 4 pixels across with
/// a 2 pixel hole, which antialiases into a grey smudge, and making them big
/// enough to survive pushes the mark past the edge of the rounded square. The
/// only raster this affects is `icon_16x16.png` — 16pt @2x is 32 pixels and
/// keeps the real mark — so the one place it shows is a non-Retina Finder list.
///
/// What is left is the three lines on the pixel grid: one pixel of line, one of
/// gap, and the lengths kept in the proportion the full mark's silhouette has
/// (30 : 36 : 18 units, counting each curl's reach).
private func drawTinyMark(in context: CGContext, side: CGFloat) {
    // Columns 3…12 of 16 leave the same 1.4px of body either side. The body is
    // twelve rows and the group of lines is five, so it cannot sit dead centre;
    // rows 6, 8 and 10 put the extra row above, which balances the short bottom
    // line better than the other way round.
    let lines = [(row: 6, width: 8), (row: 8, width: 10), (row: 10, width: 5)]

    context.setFillColor(markColor)
    for line in lines {
        // Rows count from the top; the context's y grows upwards.
        context.fill(CGRect(x: 3, y: side - CGFloat(line.row) - 1,
                            width: CGFloat(line.width), height: 1))
    }
}

// MARK: - Rendering

private func renderIcon(points: Int, scale: Int) throws -> CGImage {
    let pixels = points * scale
    let side = CGFloat(pixels)

    guard let context = CGContext(
        data: nil,
        width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw Failure("could not create a \(pixels)×\(pixels) bitmap")
    }

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)

    // The rounded square, filled with the vertical gradient.
    let body = CGFloat(pixels) * bodyFraction
    let bodyRect = CGRect(x: (side - body) / 2, y: (side - body) / 2, width: body, height: body)
    let radius = body * cornerFraction
    let roundedSquare = CGPath(roundedRect: bodyRect, cornerWidth: radius, cornerHeight: radius,
                               transform: nil)

    context.saveGState()
    context.addPath(roundedSquare)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [fillTop, fillBottom] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: bodyRect.maxY),
                               end: CGPoint(x: 0, y: bodyRect.minY),
                               options: [])
    context.restoreGState()

    if pixels <= 16 {
        drawTinyMark(in: context, side: side)
    } else {
        // The mark, centred on the body. `k` scales the SVG's 48-unit space to
        // pixels; the transform also flips y, because the SVG's grows downwards.
        let tune = tuning(forPointSize: points)
        let k = (tune.markFraction * body) / (markBounds.width + tune.strokeUnits)
        let centre = CGPoint(x: markBounds.midX, y: markBounds.midY)
        let transform = CGAffineTransform(translationX: -centre.x, y: -centre.y)
            .concatenating(CGAffineTransform(scaleX: k, y: -k))
            .concatenating(CGAffineTransform(translationX: side / 2, y: side / 2))

        let mark = CGMutablePath()
        mark.addPath(makeMarkPath(), transform: transform)

        context.setStrokeColor(markColor)
        context.setLineWidth(tune.strokeUnits * k)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(mark)
        context.strokePath()
    }

    guard let image = context.makeImage() else {
        throw Failure("could not read back the \(pixels)×\(pixels) bitmap")
    }
    return image
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        throw Failure("could not open \(url.path) for writing")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw Failure("could not write \(url.path)")
    }
}

// MARK: - Driver

private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func run(_ launchPath: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw Failure("\(launchPath) exited with \(process.terminationStatus)")
    }
}

do {
    // An output path given on the command line means what the caller typed, so
    // resolve it before moving to the repository root that everything else is
    // relative to.
    let output = CommandLine.arguments.count > 1
        ? URL(fileURLWithPath: CommandLine.arguments[1]).absoluteURL
        : nil

    let root = URL(fileURLWithPath: CommandLine.arguments[0])
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()   // scripts/
        .deletingLastPathComponent()   // repository root
    FileManager.default.changeCurrentDirectoryPath(root.path)

    let destination = output ?? URL(fileURLWithPath: "Resources/AppIcon.icns")

    let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    // `points` is what the icon is displayed at, and drives the optical sizing;
    // the @2x file for 16pt is 32 pixels but still a 16pt icon, so it is tuned
    // as one — unlike icon_32x32.png, which happens to be the same pixel size.
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1
                ? "icon_\(points)x\(points).png"
                : "icon_\(points)x\(points)@2x.png"
            try writePNG(try renderIcon(points: points, scale: scale),
                         to: iconset.appendingPathComponent(name))
        }
    }

    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try run("/usr/bin/iconutil",
            ["--convert", "icns", "--output", destination.path, iconset.path])

    print("Wrote \(destination.path)")
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
