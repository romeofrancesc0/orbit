#!/usr/bin/env swift
// Disegna il livello dell'icona: la mezzaluna che pende dal bordo in alto.
// Il fondo e il vetro li aggiunge il documento Resources/AppIcon.icon.
//
//   swift scripts/make-icon.swift

import AppKit

let side: CGFloat = 1024
let output = URL(fileURLWithPath: "Resources/AppIcon.icon/Assets/lunetta.png")

guard let context = CGContext(
    data: nil,
    width: Int(side),
    height: Int(side),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.displayP3)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("contesto non disponibile") }

// Attaccata al bordo in alto: è la notch, vista come una mezzaluna.
let radius: CGFloat = 345
let center = CGPoint(x: side / 2, y: side)

let moon = CGMutablePath()
moon.addArc(center: center, radius: radius, startAngle: .pi, endAngle: 0, clockwise: false)
moon.closeSubpath()

context.saveGState()
context.addPath(moon)
context.clip()
let colors = [
    CGColor(srgbRed: 1.00, green: 0.91, blue: 0.70, alpha: 1),
    CGColor(srgbRed: 1.00, green: 0.66, blue: 0.42, alpha: 1),
    CGColor(srgbRed: 0.91, green: 0.36, blue: 0.56, alpha: 1)
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 0.55, 1])!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: side / 2, y: center.y),
    end: CGPoint(x: side / 2, y: center.y - radius),
    options: []
)
context.restoreGState()

guard let image = context.makeImage() else { fatalError("immagine non disponibile") }
let bitmap = NSBitmapImageRep(cgImage: image)
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("png non disponibile") }
try png.write(to: output)
print("scritto \(output.path)")
