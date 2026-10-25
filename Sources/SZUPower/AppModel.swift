import Foundation
import Combine
import AppKit

/// 全局状态：配置、数据、加载状态。
@MainActor
final class AppModel: ObservableObject {

    enum Status: Equatable {
        case idle
        case loading
        case ok
        case failed(String)
    }

    @Published var config: AppConfig {
        didSet { Store.shared.saveConfig(config) }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var data: PowerData?
    @Published private(set) var buildings: [Building] = []
    @Published private(set) var isLoadingBuildings = false

    private var hotKeyManager: HotKeyManager?
    private var autoRefreshTimer: AnyCancellable?
    private var started = false

    /// 按下全局快捷键时的额外动作（AppDelegate 用它弹出卡片）
    var onHotKey: (() -> Void)?

    init() {
        config = Store.shared.loadConfig()
        // 先把上次的结果摆出来，别让卡片空着
        if let cache = Store.shared.loadCache() {
            data = cache.data
            status = .ok
        }
        // 等 App 起来之后再挂钩子 / 定时器
        DispatchQueue.main.async { [weak self] in
            self?.ensureStarted()
        }
    }

    // MARK: - 启动

    /// 幂等启动：菜单栏图标和设置窗口都可能先触发
    func ensureStarted() {
        guard !started else { return }
        started = true
        start()
    }

    func start() {
        hotKeyManager = HotKeyManager { [weak self] in
            Task { @MainActor in
                await self?.refresh()
                self?.onHotKey?()
            }
        }
        applyHotKey()
        scheduleAutoRefresh()
        if config.isConfigured {
            Task { await refresh() }
        }
    }

    private func applyHotKey() {
        guard let manager = hotKeyManager else { return }
        guard !config.hotkey.isEmpty, let combo = HotKeyManager.parse(config.hotkey) else {
            manager.unregister()
            return
        }
        manager.register(combo)
    }

    private func scheduleAutoRefresh() {
        autoRefreshTimer?.cancel()
        autoRefreshTimer = nil
        let minutes = config.autoRefreshMinutes
        guard minutes > 0, config.isConfigured else { return }
        autoRefreshTimer = Timer.publish(every: Double(minutes) * 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refresh(silent: true) }
            }
    }

    // MARK: - 查询

    func refresh(silent: Bool = false) async {
        guard config.isConfigured else {
            status = .idle
            return
        }
        if !silent { status = .loading }
        do {
            let result = try await PowerService.fetch(config: config)
            data = result.data
            status = .ok
            Store.shared.saveCache(result.data)
            Store.shared.appendHistory(result.data)
            // roomId 查到了就存下来，下次跳过楼栋列表请求
            if config.roomId.isEmpty { config.roomId = result.roomId }
            checkLowBattery(result.data)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = .failed(message)
        }
    }

    private func resolveRoomIdIfNeeded() async throws -> String {
        let client = config.campus.client
        let list = try await SimsClient.buildings(client: client)
        guard let building = list.first(where: { $0.name == config.buildingName }) else {
            throw SimsError.buildingNotFound(config.buildingName)
        }
        return try await SimsClient.resolveRoomId(
            client: client,
            buildingId: building.id,
            building: config.buildingName,
            room: config.room
        )
    }

    /// 设置页用：换校区时重新拉楼栋列表
    func refreshBuildings(for campus: Campus) async {
        await loadBuildings(for: campus)
    }

    /// 低电量：提醒一次，之后电量回升到阈值以上才会重新武装
    private func checkLowBattery(_ result: PowerData) {
        if result.last.remain > config.warnBelow {
            config.lowWarned = false
        } else if !config.lowWarned {
            config.lowWarned = true
        }
    }

    // MARK: - 设置

    func loadBuildings(for campus: Campus) async {
        isLoadingBuildings = true
        defer { isLoadingBuildings = false }
        do {
            buildings = try await SimsClient.buildings(client: campus.client)
        } catch {
            buildings = []
            status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func save(newConfig: AppConfig) {
        let changedCampus = newConfig.campusName != config.campusName
        config = newConfig
        applyHotKey()
        scheduleAutoRefresh()
        if changedCampus {
            Task { await loadBuildings(for: newConfig.campus) }
        }
        Task { await refresh() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAgent.setEnabled(enabled)
            config.launchAtLogin = enabled
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - 菜单栏图标

    var menuBarSymbol: String {
        switch status {
        case .loading: return "bolt.horizontal.circle"
        case .failed:  return "exclamationmark.circle"
        case .idle, .ok:
            if let d = data, d.last.remain < config.warnBelow {
                return "exclamationmark.triangle.fill"
            }
            return "bolt.fill"
        }
    }

    var isLow: Bool {
        guard let d = data else { return false }
        return d.last.remain < config.warnBelow
    }
}
