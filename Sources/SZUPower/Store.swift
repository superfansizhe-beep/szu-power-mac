import Foundation

/// 一行历史流水
struct HistoryEntry: Identifiable {
    var queryTime: Date
    var dataDate: String
    var remain: Double
    var usedTotal: Double
    var boughtTotal: Double
    var avgPerDay: Double
    var daysLeft: String
    var id: String { "\(queryTime.timeIntervalSince1970)" }
}

/// 配置 / 缓存 / 历史流水的落盘位置。
///
/// 对应 Windows 版的 `%LOCALAPPDATA%\szu-power`，这里是
/// `~/Library/Application Support/szu-power`。
final class Store {
    static let shared = Store()

    let directory: URL
    private let configURL: URL
    private let cacheURL: URL
    private let historyURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("szu-power", isDirectory: true)
        configURL = directory.appendingPathComponent("config.json")
        cacheURL = directory.appendingPathComponent("cache.json")
        historyURL = directory.appendingPathComponent("history.csv")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - 配置

    func loadConfig() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return cfg
    }

    func saveConfig(_ cfg: AppConfig) {
        guard let data = try? JSONEncoder().encode(cfg) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    // MARK: - 缓存（秒开用）

    struct Cache: Codable {
        var ts: Date
        var remain: Double
        var used: Double
        var bought: Double
        var date: Date
        var dayUse: Double?
        var recharge: Double
        var avg: Double
        var series: [SeriesPoint]

        var data: PowerData {
            PowerData(
                last: PowerReading(remain: remain, used: used, bought: bought, date: date),
                prev: nil,
                series: series,
                dayUse: dayUse,
                recharge: recharge,
                avg: avg,
                daysLeft: avg > 0 ? Int(floor(remain / avg)) : nil
            )
        }
    }

    func saveCache(_ data: PowerData) {
        let cache = Cache(
            ts: Date(),
            remain: data.last.remain,
            used: data.last.used,
            bought: data.last.bought,
            date: data.last.date,
            dayUse: data.dayUse,
            recharge: data.recharge,
            avg: data.avg,
            series: data.series
        )
        guard let encoded = try? JSONEncoder().encode(cache) else { return }
        try? encoded.write(to: cacheURL, options: .atomic)
    }

    func loadCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    // MARK: - 历史流水

    static let historyHeader = "query_time,data_date,remain,used_total,bought_total,avg_per_day,days_left"

    func appendHistory(_ data: PowerData) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: historyURL.path) {
            try? (Self.historyHeader + "\n").write(to: historyURL, atomically: true, encoding: .utf8)
        }
        let left = data.avg > 0 ? String(Int(floor(data.last.remain / data.avg))) : ""
        let line = [
            DateFormats.stamp.string(from: Date()),
            DateFormats.day.string(from: data.last.date),
            String(format: "%.2f", data.last.remain),
            String(format: "%.2f", data.last.used),
            String(format: "%.2f", data.last.bought),
            String(format: "%.2f", data.avg),
            left,
        ].joined(separator: ",")
        if let handle = try? FileHandle(forWritingTo: historyURL) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        }
    }

    func readHistory(limit: Int = 200) -> [HistoryEntry] {
        guard let text = try? String(contentsOf: historyURL, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n").dropFirst()
        return lines.reversed().prefix(limit).compactMap { line in
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 7 else { return nil }
            return HistoryEntry(
                queryTime: DateFormats.stamp.date(from: cols[0]) ?? Date(),
                dataDate: cols[1],
                remain: Double(cols[2]) ?? 0,
                usedTotal: Double(cols[3]) ?? 0,
                boughtTotal: Double(cols[4]) ?? 0,
                avgPerDay: Double(cols[5]) ?? 0,
                daysLeft: cols[6]
            )
        }
    }
}
