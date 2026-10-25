import Foundation

enum SimsError: LocalizedError {
    case network(String)
    case encoding
    case buildingNotFound(String)
    case roomNotFound(String)
    case noUsage(String)
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .network(let m):
            return "连不上电控系统：\(m)\n（宿舍电控是校内网地址 \(SimsClient.base)，校外 / 手机热点查不到）"
        case .encoding:
            return "电控系统返回的数据不是 GBK 编码，无法解析"
        case .buildingNotFound(let b):
            return "电控系统里没有楼栋「\(b)」，可能是系统更新了楼栋列表"
        case .roomNotFound(let r):
            return "房间「\(r)」没查到，确认是楼栋里的三位房间号"
        case .noUsage(let r):
            return "房间 \(r) 查到了，但没有用电数据（系统还没更新，或房间号不对）"
        case .server(let code):
            return "电控系统返回 HTTP \(code)"
        }
    }
}

/// 深大 SIMS 电控网上查询系统的 HTTP 客户端。
///
/// 系统是 GBK 编码的老式表单接口，没有登录态，三步走：
///   1. GET  /login.do?task=station&client=<校区IP>  → 楼栋列表
///   2. POST /login.do                               → 楼栋 id + 房间号换 roomId
///   3. POST /selectList.do                          → 用电记录（HTML 表格）
struct SimsClient {

    static let base = "http://192.168.84.3:9090/cgcSims"

    /// GB18030 是 GBK 的超集，直接用它解码更稳
    static let gbk: String.Encoding = {
        let cf = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        return String.Encoding(rawValue: cf)
    }()

    /// 把字符串按 GBK 编码后逐字节做百分号转义。
    /// 不能用 addingPercentEncoding —— 它按 UTF-8 转，中文楼栋名会错。
    static func percentEncodeGBK(_ s: String) -> String {
        var out = ""
        let bytes = Array(s.data(using: gbk) ?? Data())
        for byte in bytes {
            let ch = Character(UnicodeScalar(byte))
            if ch.isASCII && (ch.isLetter || ch.isNumber || "-._~".contains(ch)) {
                out.append(ch)
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    // MARK: - 底层请求

    static func request(path: String, body: String? = nil, timeout: TimeInterval = 20) async throws -> String {
        guard let url = URL(string: base + path) else {
            throw SimsError.network("URL 拼装失败：\(path)")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue(base + "/login.do", forHTTPHeaderField: "Referer")
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(body.utf8)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch let err as URLError {
            throw SimsError.network(err.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SimsError.server(http.statusCode)
        }
        guard let text = String(data: data, encoding: gbk) else {
            throw SimsError.encoding
        }
        return text
    }

    // MARK: - 1. 楼栋列表

    static func buildings(client: String) async throws -> [Building] {
        let html = try await request(path: "/login.do?task=station&client=\(client)")
        let pattern = "<option value=\"(\\d+)\">([^<]+)</option>"
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = html as NSString
        var out: [Building] = []
        regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let id = ns.substring(with: match.range(at: 1))
            let name = ns.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                out.append(Building(id: id, name: name))
            }
        }
        return out
    }

    // MARK: - 2. 房间号 → roomId

    static func resolveRoomId(client: String, buildingId: String, building: String, room: String) async throws -> String {
        let body = "client=\(client)&buildingId=\(buildingId)"
            + "&buildingName=\(percentEncodeGBK(building))"
            + "&roomName=\(percentEncodeGBK(room))"
            + "&select=%20%B2%E9%D1%AF%20"   // “查询” 的 GBK 字节
        let html = try await request(path: "/login.do", body: body)
        let regex = try! NSRegularExpression(pattern: "name=\"roomId\"\\s+value=\"(\\d+)\"")
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: html, range: range), match.numberOfRanges >= 2 else {
            throw SimsError.roomNotFound(room)
        }
        return ns.substring(with: match.range(at: 1))
    }

    // MARK: - 3. 用电记录

    /// 抓一段时间的用电记录。服务端单次最多返回 20 条，所以要分段抓。
    static func rows(client: String, roomId: String, room: String, from: Date, to: Date) async throws -> [PowerReading] {
        let body = "hiddenType=&isHost="
            + "&beginTime=\(DateFormats.day.string(from: from))"
            + "&endTime=\(DateFormats.day.string(from: to))"
            + "&type=2&client=\(client)&roomId=\(roomId)"
            + "&roomName=\(percentEncodeGBK(room))&building="
        let html = try await request(path: "/selectList.do", body: body)

        // 表格列：序号 | 房间 | 剩余电量 | 总用电量 | 总购电量 | 日期
        let pattern = "(?s)<tr[^>]*>\\s*<td width=\"13%\"[^>]*>\\s*(\\d+)\\s*</td>\\s*"
            + "<td width=\"13%\"[^>]*>\\s*([^<]*?)\\s*</td>\\s*"
            + "<td width=\"13%\"[^>]*>\\s*([\\d.]+)\\s*</td>\\s*"
            + "<td width=\"13%\"[^>]*>\\s*([\\d.]+)\\s*</td>\\s*"
            + "<td width=\"13%\"[^>]*>\\s*([\\d.]+)\\s*</td>\\s*"
            + "<td width=\"22%\"[^>]*>\\s*(\\d{4}-\\d{2}-\\d{2})"
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = html as NSString
        var out: [PowerReading] = []
        regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 7 else { return }
            func num(_ idx: Int) -> Double {
                Double(ns.substring(with: match.range(at: idx))) ?? 0
            }
            let dateText = ns.substring(with: match.range(at: 6))
            guard let date = DateFormats.day.date(from: dateText) else { return }
            out.append(PowerReading(
                remain: num(3),
                used: num(4),
                bought: num(5),
                date: date
            ))
        }
        return out
    }
}
