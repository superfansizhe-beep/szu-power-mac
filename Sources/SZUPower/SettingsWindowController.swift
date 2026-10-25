import AppKit
import Combine

/// 设置窗口
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private let model: AppModel
    private var draft = AppConfig()
    private var cancellables = Set<AnyCancellable>()

    // 控件
    private let campusPopUp = NSPopUpButton()
    private let buildingPopUp = NSPopUpButton()
    private let buildingSpinner = NSProgressIndicator()
    private let roomField = NSTextField()
    private let themePopUp = NSPopUpButton()
    private let scalePopUp = NSPopUpButton()
    private let warnField = NSTextField()
    private let autoRefreshPopUp = NSPopUpButton()
    private let hotkeyField = NSTextField()
    private let hotkeyStatus = NSTextField(labelWithString: "")
    private let launchCheckbox = NSButton(checkboxWithTitle: "登录后自动运行", target: nil, action: nil)
    private let pathLabel = NSTextField(labelWithString: "")
    private let testButton = NSButton(title: "测试查询", target: nil, action: nil)

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "深大电量 · 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        loadDraft()
        bind()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - 组装界面

    private func buildUI() {
        for campus in Campus.all {
            campusPopUp.addItem(withTitle: campus.name)
        }
        campusPopUp.target = self
        campusPopUp.action = #selector(campusChanged)

        buildingPopUp.target = self
        buildingPopUp.action = #selector(buildingChanged)

        buildingSpinner.style = .spinning
        buildingSpinner.controlSize = .small

        roomField.placeholderString = "三位房间号，如 301"

        for mode in ThemeMode.allCases {
            themePopUp.addItem(withTitle: mode.label)
        }
        themePopUp.target = self
        themePopUp.action = #selector(fieldChanged)

        for (title, value) in [("小", 0.85), ("标准", 1.0), ("大", 1.25)] {
            scalePopUp.addItem(withTitle: title)
            scalePopUp.lastItem?.tag = Int(value * 100)
        }
        scalePopUp.target = self
        scalePopUp.action = #selector(fieldChanged)

        warnField.placeholderString = "20"

        autoRefreshPopUp.addItems(withTitles: ["关闭", "每 15 分钟", "每 30 分钟", "每 60 分钟"])
        for (index, minutes) in [0, 15, 30, 60].enumerated() {
            autoRefreshPopUp.item(at: index)?.tag = minutes
        }
        autoRefreshPopUp.target = self
        autoRefreshPopUp.action = #selector(fieldChanged)

        hotkeyField.placeholderString = "Ctrl + Alt + E"
        hotkeyField.target = self
        hotkeyField.action = #selector(hotkeyChanged)

        launchCheckbox.target = self
        launchCheckbox.action = #selector(fieldChanged)

        pathLabel.stringValue = Store.shared.directory.path
        pathLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.isSelectable = true

        testButton.target = self
        testButton.action = #selector(testQuery)
        testButton.bezelStyle = .rounded
        testButton.controlSize = .small

        let grid = NSGridView(views: [
            [label("校区"), campusPopUp],
            [label("楼栋"), buildingStack()],
            [label("房间号"), roomField],
            [label("主题"), themePopUp],
            [label("卡片大小"), scalePopUp],
            [label("低电量预警"), warnStack()],
            [label("自动刷新"), autoRefreshPopUp],
            [label("快捷键"), hotkeyStack()],
            [NSGridCell.emptyContentView, launchCheckbox],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.column(at: 1).width = 260

        let pathRow = NSStackView(views: [label("配置文件"), pathLabel])
        pathRow.orientation = .horizontal
        pathRow.spacing = 12
        pathRow.alignment = .firstBaseline

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let saveButton = NSButton(title: "保存", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let footer = NSStackView(views: [testButton, NSView(), cancelButton, saveButton])
        footer.orientation = .horizontal
        footer.spacing = 10

        let root = NSStackView(views: [grid, pathRow, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let clip = NSView()
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(root)
        scroll.documentView = clip

        guard let content = window?.contentView else { return }
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            root.topAnchor.constraint(equalTo: clip.topAnchor),
            root.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            clip.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    private func buildingStack() -> NSView {
        let row = NSStackView(views: [buildingPopUp, buildingSpinner])
        row.orientation = .horizontal
        row.spacing = 6
        return row
    }

    private func warnStack() -> NSView {
        let unit = NSTextField(labelWithString: "度以下")
        unit.font = .systemFont(ofSize: 11)
        unit.textColor = .secondaryLabelColor
        let row = NSStackView(views: [warnField, unit])
        row.orientation = .horizontal
        row.spacing = 5
        return row
    }

    private func hotkeyStack() -> NSView {
        hotkeyStatus.font = .systemFont(ofSize: 11)
        hotkeyStatus.textColor = .secondaryLabelColor
        let row = NSStackView(views: [hotkeyField, hotkeyStatus])
        row.orientation = .horizontal
        row.spacing = 6
        return row
    }

    // MARK: - 读写草稿

    private func loadDraft() {
        draft = model.config
        campusPopUp.selectItem(withTitle: draft.campusName)
        themePopUp.selectItem(withTitle: draft.theme.label)
        scalePopUp.selectItem(withTag: Int(draft.cardScale * 100))
        autoRefreshPopUp.selectItem(withTag: draft.autoRefreshMinutes)
        roomField.stringValue = draft.room
        warnField.stringValue = String(format: "%.0f", draft.warnBelow)
        hotkeyField.stringValue = draft.hotkey
        launchCheckbox.state = draft.launchAtLogin ? .on : .off
        hotkeyChanged()
    }

    private func bind() {
        model.$buildings
            .receive(on: RunLoop.main)
            .sink { [weak self] buildings in self?.reloadBuildings(buildings) }
            .store(in: &cancellables)
    }

    private func reloadBuildings(_ buildings: [Building]) {
        buildingPopUp.removeAllItems()
        buildingPopUp.addItem(withTitle: "请选择")
        for b in buildings {
            buildingPopUp.addItem(withTitle: b.name)
        }
        if let index = buildings.firstIndex(where: { $0.name == draft.buildingName }) {
            buildingPopUp.selectItem(at: index + 1)
        }
    }

    // MARK: - 动作

    @objc private func campusChanged() {
        guard let title = campusPopUp.titleOfSelectedItem,
              let campus = Campus.all.first(where: { $0.name == title }) else { return }
        draft.campusName = campus.name
        buildingPopUp.removeAllItems()
        Task { await model.refreshBuildings(for: campus) }
    }

    @objc private func buildingChanged() {
        let title = buildingPopUp.titleOfSelectedItem ?? ""
        draft.buildingName = title == "请选择" ? "" : title
        updateTestButton()
    }

    @objc private func fieldChanged() {
        draft.theme = ThemeMode.allCases.first { $0.label == themePopUp.titleOfSelectedItem } ?? .system
        draft.cardScale = Double(scalePopUp.selectedTag()) / 100
        draft.autoRefreshMinutes = autoRefreshPopUp.selectedTag()
        draft.warnBelow = Double(warnField.stringValue) ?? draft.warnBelow
        draft.launchAtLogin = launchCheckbox.state == .on
        draft.room = roomField.stringValue
        updateTestButton()
    }

    @objc private func hotkeyChanged() {
        let text = hotkeyField.stringValue
        draft.hotkey = text
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            hotkeyStatus.stringValue = "不设"
            hotkeyStatus.textColor = .secondaryLabelColor
        } else if HotKeyManager.isAvailable(text) {
            hotkeyStatus.stringValue = "可用"
            hotkeyStatus.textColor = .systemGreen
        } else {
            hotkeyStatus.stringValue = "被占用"
            hotkeyStatus.textColor = .systemOrange
        }
    }

    private func updateTestButton() {
        testButton.isEnabled = !draft.buildingName.isEmpty && !draft.room.isEmpty
    }

    @objc private func testQuery() {
        fieldChanged()
        buildingChanged()
        model.save(newConfig: draft)
        Task { await model.refresh() }
    }

    @objc private func save() {
        fieldChanged()
        buildingChanged()
        hotkeyChanged()
        model.save(newConfig: draft)
        if draft.launchAtLogin != LaunchAgent.isEnabled {
            model.setLaunchAtLogin(draft.launchAtLogin)
        }
        close()
    }

    @objc private func cancel() {
        close()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
