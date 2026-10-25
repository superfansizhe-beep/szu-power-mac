#!/usr/bin/env swift
//
// 生成 App 图标：蓝色圆角底 + 白色闪电。
//
//   swift scripts/make-icon.swift [输出目录]
//
// 输出一个 .iconset 目录，再用 iconutil 转成 .icns：
//   iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

/// 画一张指定尺寸的图标
func renderIcon(pixels: CGFloat) -> Data? {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSColor.clear.setFill()
    bounds.fill()

    // 圆角底板
    let inset = pixels * 0.06
    let body = bounds.insetBy(dx: inset, dy: inset)
    let corner = body.width * 0.225
    let shape = NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner)

    let gradient = NSGradient(
        colors: [
            NSColor(srgbRed: 0.36, green: 0.65, blue: 0.99, alpha: 1),
            NSColor(srgbRed: 0.12, green: 0.34, blue: 0.86, alpha: 1),
        ]
    )!
    gradient.draw(in: shape, angle: -90)

    // 细高光边
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.18).setStroke()
    shape.lineWidth = max(pixels * 0.008, 0.5)
    shape.stroke()

    // 闪电（手绘路径，不依赖 SF Symbol 的渲染行为）
    let bolt = NSBezierPath()
    let points: [(CGFloat, CGFloat)] = [
        (60, 4), (26, 54), (45, 54), (38, 96), (76, 40), (55, 40),
    ]
    let unit = pixels / 100
    let boltScale: CGFloat = 0.62
    for (index, point) in points.enumerated() {
        // 以画布中心为基准缩放，保证闪电稳稳落在圆角底板里
        let x = (point.0 - 50) * boltScale + 50
        let y = (point.1 - 50) * boltScale + 50
        let p = NSPoint(x: (x - 50) * unit + pixels / 2, y: (y - 50) * unit + pixels / 2)
        if index == 0 { bolt.move(to: p) } else { bolt.line(to: p) }
    }
    bolt.close()
    NSColor.white.setFill()
    bolt.fill()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        return nil
    }
    return png
}

// iconset 需要的规格
let specs: [(name: String, pixels: CGFloat)] = [
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

var cache: [CGFloat: Data] = [:]
for spec in specs {
    if let data = cache[spec.pixels] {
        try? data.write(to: URL(fileURLWithPath: "\(outputDir)/\(spec.name).png"))
        continue
    }
    guard let data = renderIcon(pixels: spec.pixels) else {
        FileHandle.standardError.write(Data("渲染 \(spec.name) 失败\n".utf8))
        exit(1)
    }
    cache[spec.pixels] = data
    try? data.write(to: URL(fileURLWithPath: "\(outputDir)/\(spec.name).png"))
}

print("已生成 \(outputDir)")
