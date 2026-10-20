// Генерирует иконку Leaflog (1024×1024) собственной графикой: листик на зелёном фоне.
// Запуск: swift Tools/make_icon.swift Leaflog/Assets.xcassets/AppIcon.appiconset/icon.png
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let bg = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.20, green: 0.38, blue: 0.24, alpha: 1), CGColor(red: 0.07, green: 0.13, blue: 0.10, alpha: 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])

func leaf(rotation: CGFloat, color: CGColor, vein: CGColor, scale: CGFloat, dx: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: 512 + dx, y: 500)
    ctx.rotate(by: rotation)
    ctx.scaleBy(x: scale, y: scale)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: -330))
    p.addCurve(to: CGPoint(x: 0, y: 330), control1: CGPoint(x: 210, y: -170), control2: CGPoint(x: 200, y: 160))
    p.addCurve(to: CGPoint(x: 0, y: -330), control1: CGPoint(x: -200, y: 160), control2: CGPoint(x: -210, y: -170))
    ctx.addPath(p)
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.setStrokeColor(vein)
    ctx.setLineWidth(14); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 0, y: -250)); ctx.addLine(to: CGPoint(x: 0, y: 300)); ctx.strokePath()
    ctx.restoreGState()
}
let dark = CGColor(red: 0.20, green: 0.38, blue: 0.24, alpha: 1)
leaf(rotation: -0.62, color: CGColor(red: 0.55, green: 0.74, blue: 0.42, alpha: 1), vein: dark, scale: 0.8, dx: -70)
leaf(rotation: 0.45, color: CGColor(red: 0.93, green: 0.95, blue: 0.86, alpha: 1), vein: dark, scale: 0.95, dx: 60)
ctx.setFillColor(CGColor(red: 0.96, green: 0.64, blue: 0.35, alpha: 1))
ctx.fillEllipse(in: CGRect(x: 690, y: 150, width: 110, height: 110))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))
