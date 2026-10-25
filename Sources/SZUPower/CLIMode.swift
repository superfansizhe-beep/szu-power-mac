import Foundation

/// 命令行模式：不进图形界面，查一次打印结果就退出。
///
///   SZUPower --dump                          用已保存的配置查一次
///   SZUPower --query <校区> <楼栋> <房间号>    临时查一次
///   SZUPower --help
enum CLIMode {

    static func handle(_ args: [String]) -> Bool {
        guard let first = args.first else { return false }
        switch first {
        case "--help", "-h":
            printUsage()
            return true
        case "--version":
            print("深大电量 for macOS \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
            return true
        case "--dump":
            dump()
            return true
        case "--query":
            query(Array(args.dropFirst()))
            return true
        default:
            return false
        }
    }

    private static func printUsage() {
        print("""
        深大电量 · 命令行模式

          SZUPower --dump                           用已保存的配置查一次并打印
          SZUPower --query <校区> <楼栋> <房间号>     临时查一次并打印
          SZUPower --help

        查不到数据通常是两个原因：
          1. 不在校内网 —— 电控系统是 192.168.84.3 内网地址
          2. 楼栋名 / 房间号不对
        """)
    }

    // MARK: - 用已保存的配置

    private static func dump() {
        let config = Store.shared.loadConfig()
        guard config.isConfigured else {
            print("还没配置过宿舍信息。先跑一次图形界面设置，或者用：")
            print("  SZUPower --query <校区> <楼栋> <房间号>")
            exit(1)
        }
        run(config: config)
    }

    // MARK: - 临时查一次

    private static func query(_ args: [String]) {
        guard args.count >= 3 else {
            print("用法：SZUPower --query <校区> <楼栋> <房间号>")
            print("例如：SZUPower --query 南校区 冬筑3-6楼 301")
            exit(1)
        }
        var config = AppConfig()
        config.campusName = args[0]
        config.buildingName = args[1]
        config.room = args[2]
        run(config: config)
    }

    // MARK: - 执行

    private static func run(config: AppConfig) {
        print("正在查询：\(config.campusName) \(config.buildingName) \(config.room)")
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<PowerData, Error> = .failure(SimsError.noUsage(config.room))

        Task {
            do {
                let fetched = try await PowerService.fetch(config: config)
                result = .success(fetched.data)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()

        switch result {
        case .success(let data):
            print("")
            print(String(format: "剩余电量    %.2f 度", data.last.remain))
            if let dayUse = data.dayUse {
                print(String(format: "昨日用电    %.2f 度", dayUse))
            }
            print(String(format: "平均用电    %.2f 度", data.avg))
            print("数据日期    \(data.last.dateText)")
            if let left = data.daysLeft {
                print("约还可用    \(left) 天")
            }
            if !data.series.isEmpty {
                let points = data.series.map { "\($0.label) \(String(format: "%.2f", $0.value))" }.joined(separator: " / ")
                print("近 5 天     \(points)")
            }
        case .failure(let error):
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print("")
            print("查询失败：\(message)")
            exit(1)
        }
    }
}
