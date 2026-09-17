import AppKit

/// Two allowance windows surrounding a meter needle. Shared by the app and icon exporter.
enum TokenMeterLogo {
    static func image(size: CGFloat, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.scaleBy(x: rect.width / 128, y: rect.height / 128)
            if !template {
                let tile = NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 120, height: 120), xRadius: 27, yRadius: 27)
                NSColor(srgbRed: 0.055, green: 0.10, blue: 0.17, alpha: 1).setFill()
                tile.fill()
            }
            let teal = template ? NSColor.black : NSColor(srgbRed: 0.23, green: 0.88, blue: 0.76, alpha: 1)
            let blue = template ? NSColor.black : NSColor(srgbRed: 0.36, green: 0.65, blue: 1, alpha: 1)
            func arc(radius: CGFloat, end: CGFloat, color: NSColor, width: CGFloat) {
                let path = NSBezierPath()
                path.appendArc(withCenter: NSPoint(x: 64, y: 61), radius: radius, startAngle: 220, endAngle: end, clockwise: true)
                path.lineWidth = width
                path.lineCapStyle = .round
                color.setStroke()
                path.stroke()
            }
            if !template {
                let track = NSColor.white.withAlphaComponent(0.12)
                arc(radius: 40, end: -40, color: track, width: 9)
                arc(radius: 26, end: -40, color: track, width: 7)
            }
            arc(radius: 40, end: 15, color: teal, width: 9)
            arc(radius: 26, end: 65, color: blue, width: 7)
            let needle = NSBezierPath()
            needle.move(to: NSPoint(x: 64, y: 61))
            needle.line(to: NSPoint(x: 82, y: 79))
            needle.lineWidth = 6
            needle.lineCapStyle = .round
            (template ? NSColor.black : NSColor.white).setStroke()
            needle.stroke()
            (template ? NSColor.black : NSColor.white).setFill()
            NSBezierPath(ovalIn: NSRect(x: 59, y: 56, width: 10, height: 10)).fill()
            return true
        }
        image.isTemplate = template
        return image
    }
}
