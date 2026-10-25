import Foundation

/// 把电控系统的原始记录算成指标 —— 口径和 Windows 版 `Get-PowerData` 完全一致。
enum PowerService {

    /// 一次查询的产出：指标 + 顺带查到的 roomId（供缓存）
    struct FetchResult {
        var data: PowerData
        var roomId: String
    }

    /// 查一次电表数据
    static func fetch(config: AppConfig) async throws -> FetchResult {
        let client = config.campus.client

        // roomId 可以缓存；没有就先查楼栋列表换出来
        var roomId = config.roomId
        var resolvedConfig = config
        if roomId.isEmpty {
            let buildings = try await SimsClient.buildings(client: client)
            guard let building = buildings.first(where: { $0.name == config.buildingName }) else {
                throw SimsError.buildingNotFound(config.buildingName)
            }
            roomId = try await SimsClient.resolveRoomId(
                client: client,
                buildingId: building.id,
                building: config.buildingName,
                room: config.room
            )
            resolvedConfig.roomId = roomId
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // 服务端一次最多回 20 条：先抓最近 20 天，再补往前 15 天，凑够一个月
        var rows = try await SimsClient.rows(
            client: client, roomId: roomId, room: config.room,
            from: cal.date(byAdding: .day, value: -19, to: today)!,
            to: today
        )
        if rows.count >= 18 {
            let older = try await SimsClient.rows(
                client: client, roomId: roomId, room: config.room,
                from: cal.date(byAdding: .day, value: -34, to: today)!,
                to: cal.date(byAdding: .day, value: -20, to: today)!
            )
            rows += older
        }

        // 按日期去重 + 升序
        var byDate: [Date: PowerReading] = [:]
        for row in rows { byDate[row.date] = row }
        let sorted = byDate.values.sorted { $0.date < $1.date }

        guard !sorted.isEmpty else {
            throw SimsError.noUsage(config.room)
        }

        let last = sorted[sorted.count - 1]
        let prev = sorted.count >= 2 ? sorted[sorted.count - 2] : nil

        // 逐日用电：相邻两天「总用电量」相减，按间隔天数摊平
        var daily: [(date: Date, value: Double)] = []
        for i in 1..<sorted.count {
            let gap = cal.dateComponents([.day], from: sorted[i - 1].date, to: sorted[i].date).day ?? 0
            if gap < 1 || gap > 3 { continue }
            let value = Num.round2((sorted[i].used - sorted[i - 1].used) / Double(gap))
            daily.append((sorted[i].date, value))
        }

        // 折线图：最近 5 天
        let series = daily.suffix(5).map {
            SeriesPoint(label: DateFormats.shortDay.string(from: $0.date), value: max($0.value, 0))
        }

        // 平均：剔掉电表归零（<=0）和异常跳变（>80 度/天）后的日均
        var valid = daily.filter { $0.value > 0 && $0.value <= 80 }
        if valid.isEmpty {
            valid = daily.filter { $0.value > 0 }
        }
        let avg = valid.isEmpty
            ? 0
            : Num.round2(valid.reduce(0) { $0 + $1.value } / Double(valid.count))

        let dayUse: Double? = {
            if let d = daily.last { return d.value }
            if let prev { return Num.round2(last.used - prev.used) }
            return nil
        }()

        let recharge = prev.map { Num.round2(last.bought - $0.bought) } ?? 0

        return FetchResult(
            data: PowerData(
                last: last,
                prev: prev,
                series: series,
                dayUse: dayUse,
                recharge: recharge,
                avg: avg,
                daysLeft: avg > 0 ? Int(floor(last.remain / avg)) : nil
            ),
            roomId: roomId
        )
    }
}
