import AppKit

/// 近 5 天逐日用电折线图（自绘，矢量不糊）
final class UsageChartView: NSView {

    var points: [SeriesPoint] = [] {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard points.count >= 2 else {
            let msg = "数据点不足，画不出曲线" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let size = msg.size(withAttributes: attrs)
            msg.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                    withAttributes: attrs)
            return
        }

        let inset: CGFloat = 10
        let labelSpace: CGFloat = 14          // 底部留给 x 轴标签
        let plot = NSRect(
            x: bounds.minX + inset,
            y: bounds.minY + labelSpace,
            width: max(bounds.width - inset * 2, 1),
            height: max(bounds.height - inset - labelSpace, 1)
        )

        let values = points.map { $0.value }
        let maxValue = max(values.max() ?? 1, 1)

        func position(_ i: Int) -> NSPoint {
            let x = plot.minX + plot.width * CGFloat(i) / CGFloat(points.count - 1)
            let ratio = CGFloat(points[i].value / maxValue)
            let y = plot.maxY - plot.height * ratio
            return NSPoint(x: x, y: y)
        }

        // 面积填充
        let area = NSBezierPath()
        area.move(to: NSPoint(x: plot.minX, y: plot.minY))
        for i in points.indices { area.line(to: position(i)) }
        area.line(to: NSPoint(x: plot.maxX, y: plot.minY))
        area.close()
        if let gradient = NSGradient(
            colors: [
                NSColor.controlAccentColor.withAlphaComponent(0.26),
                NSColor.controlAccentColor.withAlphaComponent(0.02),
            ]
        ) {
            gradient.draw(in: area, angle: -90)
        }

        // 折线
        let line = NSBezierPath()
        for i in points.indices {
            let p = position(i)
            if i == 0 { line.move(to: p) } else { line.line(to: p) }
        }
        line.lineWidth = 2
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        NSColor.controlAccentColor.setStroke()
        line.stroke()

        // 数据点
        for i in points.indices {
            let p = position(i)
            let r: CGFloat = 3
            let outer = NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            NSColor.controlAccentColor.setFill()
            outer.fill()
            let inner = NSBezierPath(ovalIn: NSRect(x: p.x - r + 1.2, y: p.y - r + 1.2, width: (r - 1.2) * 2, height: (r - 1.2) * 2))
            NSColor.windowBackgroundColor.setFill()
            inner.fill()
        }

        // x 轴日期标签
        let xAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        for i in points.indices {
            let p = position(i)
            let text = points[i].label as NSString
            let size = text.size(withAttributes: xAttrs)
            var x = p.x - size.width / 2
            x = min(max(x, 0), bounds.width - size.width)
            text.draw(at: NSPoint(x: x, y: bounds.minY + 1), withAttributes: xAttrs)
        }

        // y 轴：左上角标一下峰值，单位跟着走，免得看成一个孤零零的数
        let yAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let yText = String(format: "峰值 %.1f 度", maxValue) as NSString
        yText.draw(at: NSPoint(x: 1, y: plot.maxY - 11), withAttributes: yAttrs)
    }
}
