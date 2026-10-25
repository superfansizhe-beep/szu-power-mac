import AppKit
import Combine

/// 菜单栏点开后弹出的那张卡片
final class CardPopoverController: NSViewController {

    private let model: AppModel
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    /// 打开设置窗口
    var onOpenSettings: (() -> Void)?

    // MARK: - 界面元素

    private let titleField = NSTextField(labelWithString: "")
    private let boltView = NSImageView()
    private let gearButton = NSButton()
    private let bodyStack = NSStackView()
    private let refreshButton = NSButton()
    private let copyButton = NSButton()

    private var scale: CGFloat { model.config.cardScale }

    // MARK: - 生命周期

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 300))
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        bind()
        renderNow()
    }

    // MARK: - 组装界面

    private func buildUI() {
        // 头部
        boltView.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        boltView.contentTintColor = .systemOrange
        boltView.symbolConfiguration = .init(pointSize: 12 * scale, weight: .semibold)

        titleField.font = .systemFont(ofSize: 12 * scale, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        gearButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")
        gearButton.isBordered = false
        gearButton.contentTintColor = .secondaryLabelColor
        gearButton.target = self
        gearButton.action = #selector(openSettings)
        gearButton.toolTip = "设置"

        let header = NSStackView(views: [boltView, titleField, NSView(), gearButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 7
        header.edgeInsets = NSEdgeInsets(top: 11, left: 14, bottom: 11, right: 12)

        // 主体
        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 9
        bodyStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        // 底部
        configureFooterButton(refreshButton, title: "刷新", symbol: "arrow.clockwise", action: #selector(refresh))
        configureFooterButton(copyButton, title: "复制全部", symbol: "doc.on.doc", action: #selector(copyAll))

        let quitButton = NSButton(title: "退出", target: self, action: #selector(quit))
        quitButton.bezelStyle = .inline
        quitButton.contentTintColor = .secondaryLabelColor
        quitButton.font = .systemFont(ofSize: 11 * scale)

        let footer = NSStackView(views: [refreshButton, copyButton, NSView(), quitButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        footer.edgeInsets = NSEdgeInsets(top: 9, left: 14, bottom: 9, right: 14)

        let stack = NSStackView(views: [header, separator(), bodyStack, separator(), footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func configureFooterButton(_ button: NSButton, title: String, symbol: String, action: Selector) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.bezelStyle = .inline
        button.contentTintColor = .labelColor
        button.font = .systemFont(ofSize: 11 * scale)
        button.target = self
        button.action = action
    }

    // MARK: - 数据绑定

    private func bind() {
        model.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.renderNow() }
            .store(in: &cancellables)

        model.$data
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.renderNow() }
            .store(in: &cancellables)

        model.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.titleField.stringValue = self?.titleText ?? ""
                self?.renderNow()
            }
            .store(in: &cancellables)
    }

    // MARK: - 渲染

    private var titleText: String {
        guard model.config.isConfigured else { return "深大电量 · 未设置" }
        let c = model.config
        return "深大电量 · \(c.campusName) \(c.buildingName) \(c.room)"
    }

    func renderNow() {
        titleField.stringValue = titleText
        boltView.symbolConfiguration = .init(pointSize: 12 * scale, weight: .semibold)
        titleField.font = .systemFont(ofSize: 12 * scale, weight: .medium)

        for view in bodyStack.arrangedSubviews {
            bodyStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch model.status {
        case .idle:
            bodyStack.addArrangedSubview(emptyState())
        case .loading:
            bodyStack.addArrangedSubview(loadingState())
        case .failed(let message):
            bodyStack.addArrangedSubview(errorState(message))
        case .ok:
            if let data = model.data {
                bodyStack.addArrangedSubview(metrics(data))
            } else {
                bodyStack.addArrangedSubview(loadingState())
            }
        }

        refreshButton.isEnabled = model.status != .loading
        copyButton.isEnabled = model.data != nil

        popover.contentSize = cardSize()
    }

    /// 按当前内容算卡片高度
    func cardSize() -> NSSize {
        let width: CGFloat = 340
        view.layoutSubtreeIfNeeded()
        var height: CGFloat = 0
        for sub in bodyStack.arrangedSubviews {
            height += sub.fittingSize.height
        }
        height += bodyStack.spacing * CGFloat(max(bodyStack.arrangedSubviews.count - 1, 0))
        height += 24                                    // body 的上下 padding
        height += 40 + 34                              // 头部 + 底部
        return NSSize(width: width, height: max(height, 200))
    }

    // MARK: - 各种状态

    private func emptyState() -> NSView {
        let box = NSStackView()
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 6

        let title = NSTextField(labelWithString: "还没设置宿舍信息")
        title.font = .systemFont(ofSize: 14 * scale, weight: .semibold)

        let hint = NSTextField(labelWithString: "选好校区、楼栋和房间号就能查")
        hint.font = .systemFont(ofSize: 11 * scale)
        hint.textColor = .secondaryLabelColor

        let button = NSButton(title: "去设置", target: self, action: #selector(openSettings))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11 * scale)

        box.addArrangedSubview(title)
        box.addArrangedSubview(hint)
        box.addArrangedSubview(button)
        return box
    }

    private func loadingState() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let text = NSTextField(labelWithString: "查询中…")
        text.font = .systemFont(ofSize: 12 * scale)
        text.textColor = .secondaryLabelColor

        row.addArrangedSubview(spinner)
        row.addArrangedSubview(text)
        row.heightAnchor.constraint(equalToConstant: 100).isActive = true
        return row
    }

    private func errorState(_ message: String) -> NSView {
        let box = NSStackView()
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 7

        let title = NSTextField(labelWithString: "查询失败")
        title.font = .systemFont(ofSize: 13 * scale, weight: .semibold)
        title.textColor = .systemRed

        let detail = NSTextField(wrappingLabelWithString: message)
        detail.font = .systemFont(ofSize: 11 * scale)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 6
        detail.preferredMaxLayoutWidth = 310

        let button = NSButton(title: "重试", target: self, action: #selector(refresh))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11 * scale)

        box.addArrangedSubview(title)
        box.addArrangedSubview(detail)
        box.addArrangedSubview(button)
        return box
    }

    private func metrics(_ data: PowerData) -> NSView {
        let box = NSStackView()
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 9

        // 低电量横幅
        if model.isLow {
            let banner = NSStackView()
            banner.orientation = .horizontal
            banner.spacing = 5
            banner.alignment = .centerY
            banner.edgeInsets = NSEdgeInsets(top: 6, left: 9, bottom: 6, right: 9)
            banner.wantsLayer = true
            banner.layer?.cornerRadius = 7
            banner.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.16).cgColor

            let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)!)
            icon.contentTintColor = .systemOrange
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10 * scale, weight: .regular)

            let text = NSTextField(labelWithString: "剩余电量偏低，注意及时充值")
            text.font = .systemFont(ofSize: 11 * scale, weight: .medium)
            text.textColor = .systemOrange

            banner.addArrangedSubview(icon)
            banner.addArrangedSubview(text)
            box.addArrangedSubview(banner)
        }

        // 剩余电量
        let remainCaption = NSTextField(labelWithString: "剩余电量")
        remainCaption.font = .systemFont(ofSize: 11 * scale)
        remainCaption.textColor = .secondaryLabelColor

        let remainRow = NSStackView()
        remainRow.orientation = .horizontal
        remainRow.alignment = .firstBaseline
        remainRow.spacing = 4

        let remainNumber = NSTextField(labelWithString: String(format: "%.2f", data.last.remain))
        remainNumber.font = .systemFont(ofSize: 32 * scale, weight: .semibold)
        remainNumber.textColor = .labelColor

        let remainUnit = NSTextField(labelWithString: "度")
        remainUnit.font = .systemFont(ofSize: 12 * scale)
        remainUnit.textColor = .secondaryLabelColor

        remainRow.addArrangedSubview(remainNumber)
        remainRow.addArrangedSubview(remainUnit)

        box.addArrangedSubview(remainCaption)
        box.addArrangedSubview(remainRow)

        // 两个指标
        let metricsRow = NSStackView()
        metricsRow.orientation = .horizontal
        metricsRow.spacing = 24

        let dayUse = metricBlock("昨日用电", data.dayUse.map { String(format: "%.2f 度", $0) } ?? "—")
        let avgUse = metricBlock("平均用电", String(format: "%.2f 度", data.avg))
        metricsRow.addArrangedSubview(dayUse)
        metricsRow.addArrangedSubview(avgUse)

        box.addArrangedSubview(metricsRow)

        // 折线图
        let chart = UsageChartView()
        chart.points = data.series
        chart.translatesAutoresizingMaskIntoConstraints = false
        chart.heightAnchor.constraint(equalToConstant: 74 * scale).isActive = true
        chart.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        box.addArrangedSubview(chart)

        // 底部说明
        let footerText = NSStackView()
        footerText.orientation = .horizontal
        footerText.spacing = 4
        footerText.alignment = .firstBaseline

        let dateLabel = NSTextField(labelWithString: "数据 \(data.last.dateText)")
        dateLabel.font = .systemFont(ofSize: 11 * scale)
        dateLabel.textColor = .secondaryLabelColor

        footerText.addArrangedSubview(dateLabel)

        if let left = data.daysLeft {
            let dot = NSTextField(labelWithString: "·")
            dot.font = .systemFont(ofSize: 11 * scale)
            dot.textColor = .secondaryLabelColor

            let daysLabel = NSTextField(labelWithString: "约还可用 \(left) 天")
            daysLabel.font = .systemFont(ofSize: 11 * scale)
            if left <= 3 {
                daysLabel.textColor = .systemOrange
                daysLabel.font = .systemFont(ofSize: 11 * scale, weight: .semibold)
            } else {
                daysLabel.textColor = .secondaryLabelColor
            }

            footerText.addArrangedSubview(dot)
            footerText.addArrangedSubview(daysLabel)
        }

        box.addArrangedSubview(footerText)
        return box
    }

    private func metricBlock(_ title: String, _ value: String) -> NSView {
        let box = NSStackView()
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 1

        let caption = NSTextField(labelWithString: title)
        caption.font = .systemFont(ofSize: 10 * scale)
        caption.textColor = .secondaryLabelColor

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 13 * scale, weight: .medium)

        box.addArrangedSubview(caption)
        box.addArrangedSubview(valueLabel)
        return box
    }

    // MARK: - 动作

    @objc private func refresh() {
        Task { await model.refresh() }
    }

    @objc private func copyAll() {
        guard let data = model.data else { return }
        let c = model.config
        var lines: [String] = []
        lines.append("深大电量 · \(c.campusName) \(c.buildingName) \(c.room)")
        lines.append(String(format: "剩余 %.2f 度", data.last.remain))
        if let dayUse = data.dayUse {
            lines.append(String(format: "昨日用电 %.2f 度", dayUse))
        }
        lines.append(String(format: "平均用电 %.2f 度", data.avg))
        var tail = "数据 \(data.last.dateText)"
        if let left = data.daysLeft { tail += " · 约还可用 \(left) 天" }
        lines.append(tail)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 弹出

    var popoverIsShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSView) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.contentSize = cardSize()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func close() {
        popover.performClose(nil)
    }
}
