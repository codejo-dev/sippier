// Renders an SVG to PNG.
//   render in.svg out.png width height            plain render, transparent background
//   render in.svg out.png size size inset shadow   app-icon render: artwork inset by `inset`
//                                                  (fraction of size) with a soft drop shadow
import AppKit

let args = CommandLine.arguments
guard args.count >= 5, let w = Int(args[3]), let h = Int(args[4]),
      let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("usage: render in.svg out.png width height [inset shadow]\n".data(using: .utf8)!)
    exit(1)
}
let inset = args.count > 5 ? (Double(args[5]) ?? 0) : 0
let shadow = args.count > 6 && args[6] == "shadow"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
if shadow {
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(0.3)
    s.shadowOffset = NSSize(width: 0, height: -Double(h) * 10 / 1024)
    s.shadowBlurRadius = Double(h) * 20 / 1024
    s.set()
}
let dx = Double(w) * inset, dy = Double(h) * inset
image.draw(in: NSRect(x: dx, y: dy, width: Double(w) - 2 * dx, height: Double(h) - 2 * dy))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
