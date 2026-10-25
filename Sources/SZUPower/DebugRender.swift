import AppKit

/// 调试辅助：把卡片离屏渲染成 PNG。
///
///   SZU_RENDER_CARD=/tmp/card.png ./SZUPower
///
/// 用于没有显示器 / 无法截图的环境（CI、远程 shell）做视觉检查。
@MainActor
enum DebugRender {

    static func run(path: String) async {
        NSApplication.shared.setActivationPolicy(.accessory)
        // SZU_APPEARANCE=light|dark 可以指定渲染外观
        switch ProcessInfo.processInfo.environment["SZU_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }

        let model = AppModel()
        let card = CardPopoverController(model: model)
        _ = card.view                      // 触发 loadView / viewDidLoad

        await model.refresh()
        card.renderNow()

        let size = card.cardSize()
        card.view.frame = NSRect(origin: .zero, size: size)
        card.view.layoutSubtreeIfNeeded()
        card.view.displayIfNeeded()

        guard let rep = card.view.bitmapImageRepForCachingDisplay(in: card.view.bounds) else {
            fail("拿不到 bitmap")
        }
        card.view.cacheDisplay(in: card.view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            fail("转 PNG 失败")
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("已渲染到 \(path)（\(Int(size.width))×\(Int(size.height))）")
        } catch {
            fail("写文件失败：\(error)")
        }
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("渲染失败：\(message)\n".utf8))
        exit(1)
    }
}
