import Foundation

/// 开机自启：往 `~/Library/LaunchAgents` 丢一个 plist，用 launchctl 装载。
///
/// 不用 SMAppService —— 那套要 App Sandbox + 正式签名才稳，
/// 而这个工具是给自己随手装的，直接写 LaunchAgent 最省事。
enum LaunchAgent {

    static let label = "com.szu.power"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// 当前正在运行的这个可执行文件的路径
    private static var executablePath: String {
        if let url = Bundle.main.executableURL, FileManager.default.fileExists(atPath: url.path) {
            return url.path
        }
        return CommandLine.arguments[0]
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// 装 / 卸开机自启
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try install()
        } else {
            remove()
        }
    }

    private static func install() throws {
        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)

        // 先卸再装，保证指向最新路径
        bootout()
        let status = bootstrap()
        if status != 0 {
            throw LaunchAgentError.failed("launchctl bootstrap 返回 \(status)")
        }
    }

    static func remove() {
        bootout()
        try? FileManager.default.removeItem(at: plistURL)
    }

    private static func bootstrap() -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootstrap", "gui/\(getuid())", plistURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private static func bootout() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // 没装过就算了
        }
    }

    enum LaunchAgentError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let m): return "设置开机自启失败：\(m)"
            }
        }
    }
}
