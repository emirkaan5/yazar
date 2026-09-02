#!/usr/bin/env swift
// Renders the installer window backdrop used by scripts/create-dmg.sh.
// Writes scripts/dmg-background.png (640x400) and scripts/dmg-background@2x.png.
// The window size and the gap the arrow sits in must stay in sync with the
// Finder geometry in create-dmg.sh.
// Usage: scripts/make-dmg-background.swift

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width = 640.0
let height = 400.0
let iconCenterY = 180.0   // Finder icon centers, measured from the window top
let arrowCenterX = 320.0

func color(_ hex: UInt32, alpha: Double = 1) -> CGColor {
    CGColor(
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// Draws into a top-left origin space so the numbers match Finder's coordinates.
func render(scale: Double) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil,
        width: Int(width * scale),
        height: Int(height * scale),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)
    context.setAllowsAntialiasing(true)

    let gradient = CGGradient(
        colorsSpace: space,
        colors: [color(0xFFFFFF), color(0xF7F7F8), color(0xEFEFF1)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 0, y: height),
        options: []
    )

    // Arrow pointing from the app to the Applications alias.
    let shaftLength = 74.0
    let headLength = 26.0
    let headHalfHeight = 17.0
    let shaftHalfHeight = 5.0
    let arrowStart = arrowCenterX - (shaftLength + headLength) / 2
    let shaftEnd = arrowStart + shaftLength
    let arrow = CGMutablePath()
    arrow.addRoundedRect(
        in: CGRect(
            x: arrowStart,
            y: iconCenterY - shaftHalfHeight,
            width: shaftLength + 4,
            height: shaftHalfHeight * 2
        ),
        cornerWidth: shaftHalfHeight,
        cornerHeight: shaftHalfHeight
    )
    arrow.move(to: CGPoint(x: shaftEnd, y: iconCenterY - headHalfHeight))
    arrow.addLine(to: CGPoint(x: shaftEnd + headLength, y: iconCenterY))
    arrow.addLine(to: CGPoint(x: shaftEnd, y: iconCenterY + headHalfHeight))
    arrow.closeSubpath()
    context.addPath(arrow)
    context.setFillColor(color(0x000000, alpha: 0.22))
    context.fillPath()

    draw(
        text: "Drag Yazar to your Applications folder",
        size: 13,
        weight: 0.23,
        color: color(0x8A8A8F),
        centerX: width / 2,
        baselineFromTop: 336,
        in: context
    )

    return context.makeImage()!
}

func draw(
    text: String,
    size: Double,
    weight: Double,
    color textColor: CGColor,
    centerX: Double,
    baselineFromTop: Double,
    in context: CGContext
) {
    let descriptor = CTFontDescriptorCreateWithAttributes([
        kCTFontTraitsAttribute: [kCTFontWeightTrait: weight],
    ] as CFDictionary)
    let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
    let font = CTFontCreateCopyWithAttributes(base, size, nil, descriptor)
    let attributed = CFAttributedStringCreate(nil, text as CFString, [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: textColor,
        kCTKernAttributeName: 0.2,
    ] as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributed)
    let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)

    context.saveGState()
    // Undo the top-left flip so glyphs are not drawn upside down.
    context.translateBy(x: centerX - textWidth / 2, y: baselineFromTop)
    context.scaleBy(x: 1, y: -1)
    context.textPosition = .zero
    CTLineDraw(line, context)
    context.restoreGState()
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fatalError("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("cannot encode \(url.path)")
    }
    print("wrote \(url.path)")
}

let scriptsDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
write(render(scale: 1), to: scriptsDirectory.appendingPathComponent("dmg-background.png"))
write(render(scale: 2), to: scriptsDirectory.appendingPathComponent("dmg-background@2x.png"))
