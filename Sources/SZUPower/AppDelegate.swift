import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let model = AppModel()
    private var card: CardPopoverController!
    private var settings: SettingsWindowController!
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 调试模式：离屏渲染卡片成 PNG，不进正常流程
        if let path = ProcessInfo.processInfo.environment["SZU_RENDER_CARD"] {
            Task { await DebugRender.run(path: path) }
            return
        }

        card = CardPopoverController(model: model)
        card.onOpenSettings = { [weak self] in self?.openSettings() }

        settings = SettingsWindowController(model: model)

        model.onHotKey = { [weak self] in self?.showCard() }
        model.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyTheme() }
            .store(in: &cancellables)

        setupStatusItem()
        applyTheme()
        model.ensureStarted()

        // 调试用：SZU_OPEN_CARD=1 启动就自动弹出卡片，方便截图 / 自动化验证
        if ProcessInfo.processInfo.environment["SZU_OPEN_CARD"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.showCard()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "深大电量")
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "深大电量"
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent, let button = statusItem.button else { return }
        if event.type == .rightMouseUp {
            popUpMenu()
        } else {
            card.toggle(relativeTo: button)
        }
    }

    private func popUpMenu() {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "立即查询", action: #selector(refreshNow), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let autoStart = NSMenuItem(title: "开机自启", action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStart.target = self
        autoStart.state = LaunchAgent.isEnabled ? .on : .off
        menu.addItem(autoStart)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: statusItem.button!)
        }
    }

    // MARK: - 动作

    @objc private func refreshNow() {
        Task { await model.refresh() }
    }

    @objc private func openSettings() {
        card.close()
        settings.show()
    }

    @objc private func toggleAutoStart() {
        model.setLaunchAtLogin(!LaunchAgent.isEnabled)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showCard() {
        guard let button = statusItem.button else { return }
        if !card.popoverIsShown {
            card.toggle(relativeTo: button)
        }
    }

    // MARK: - 主题

    private func applyTheme() {
        switch model.config.theme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// 程序入口
@main
enum SZUPowerMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        // 命令行模式：查一次就退出，不起图形界面
        if CLIMode.handle(args) { return }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
