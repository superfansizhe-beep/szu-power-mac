import Foundation

// MARK: - 校区

/// 校区 → 校内网 IP。电控系统按 client 参数区分校区。
struct Campus: Identifiable, Hashable {
    let name: String
    let client: String

    var id: String { client }

    static let all: [Campus] = [
        Campus(name: "北校区",     client: "192.168.84.1"),
        Campus(name: "南校区",     client: "192.168.84.110"),
        Campus(name: "西丽校区",   client: "172.21.101.11"),
        Campus(name: "深大新斋区", client: "192.168.84.87"),
    ]
}

// MARK: - 楼栋

struct Building: Identifiable, Hashable {
    /// 电控系统内部的楼栋 id
    let id: String
    let name: String
}

// MARK: - 设置

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }
}

struct AppConfig: Codable, Equatable {
    var campusName: String = "南校区"
    var buildingName: String = ""
    var room: String = ""
    /// 电控系统内部 roomId，查到后缓存下来，之后可以跳过楼栋列表请求
    var roomId: String = ""

    var hotkey: String = "Ctrl + Alt + E"
    var launchAtLogin: Bool = false
    var theme: ThemeMode = .system
    /// 卡片缩放：0.85 / 1.0 / 1.25
    var cardScale: Double = 1.0
    /// 低电量预警阈值（度）
    var warnBelow: Double = 20
    /// 本轮低电量是否已经提醒过，避免每次刷新都弹
    var lowWarned: Bool = false
    /// 自动刷新间隔（分钟），0 = 关闭
    var autoRefreshMinutes: Int = 30

    var campus: Campus {
        Campus.all.first { $0.name == campusName } ?? Campus.all[1]
    }

    var isConfigured: Bool {
        !buildingName.isEmpty && !room.isEmpty
    }
}

// MARK: - 数据

/// 电表一天的读数
struct PowerReading {
    /// 剩余电量（度）
    var remain: Double
    /// 累计总用电量（度）
    var used: Double
    /// 累计总购电量（度）
    var bought: Double
    /// 数据日期
    var date: Date
}

/// 折线图上的一个点
struct SeriesPoint: Identifiable, Hashable, Codable {
    /// MM-dd
    var label: String
    var value: Double
    var id: String { label }
}

/// 折线图 + 指标
struct PowerData {
    var last: PowerReading
    var prev: PowerReading?
    /// 最近 5 天逐日用电
    var series: [SeriesPoint]
    /// 昨日用电
    var dayUse: Double?
    /// 昨日充值
    var recharge: Double
    /// 近 30 天日均用电
    var avg: Double
    /// 约还可用几天
    var daysLeft: Int?

    /// 完整文案，「复制全部」用
    var summary: String {
        var lines: [String] = []
        lines.append("深大电量 · \(last.dateText)")
        lines.append(String(format: "剩余 %.2f 度", last.remain))
        if let dayUse {
            lines.append(String(format: "昨日用电 %.2f 度", dayUse))
        }
        lines.append(String(format: "平均用电 %.2f 度", avg))
        var tail = "数据 \(last.dateText)"
        if let daysLeft {
            tail += " · 约还可用 \(daysLeft) 天"
        }
        lines.append(tail)
        return lines.joined(separator: "\n")
    }
}

extension PowerReading {
    /// yyyy-MM-dd
    var dateText: String {
        DateFormats.day.string(from: date)
    }
}

// MARK: - 日期

enum DateFormats {
    /// 服务端要的是 yyyy-MM-dd，按本机时区算「今天」
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 折线图上的 MM-dd
    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd"
        return f
    }()

    /// 历史流水的时间戳
    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()
}

// MARK: - 数值处理

enum Num {
    /// 保留两位小数，四舍六入五成双 —— 和 PowerShell 的 [math]::Round(x, 2) 口径一致
    static func round2(_ x: Double) -> Double {
        let scaled = x * 100
        let lower = scaled.rounded(.down)
        let diff = scaled - lower
        var result = lower
        if abs(diff - 0.5) < 1e-9 {
            // 正好 .5：取偶
            result = lower.truncatingRemainder(dividingBy: 2) == 0 ? lower : lower + 1
        } else if diff > 0.5 {
            result = lower + 1
        }
        return result / 100
    }
}
