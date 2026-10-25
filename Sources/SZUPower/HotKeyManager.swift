import Foundation
import Carbon.HIToolbox

/// 全局快捷键（Carbon RegisterEventHotKey）。
///
/// 用 Carbon 而不是 CGEventTap，是因为它不需要辅助功能权限，
/// 普通用户点一下授权弹窗就能用。
final class HotKeyManager {

    /// 解析出来的组合键
    struct Combo {
        var keyCode: UInt32
        var modifiers: UInt32
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var current: Combo?
    private var onFire: (() -> Void)?

    // Carbon 回调是 C 函数指针，捕获不了上下文，所以走一个全局闭包
    private static var globalHandler: (() -> Void)?

    init(onFire: @escaping () -> Void) {
        self.onFire = onFire
        Self.globalHandler = onFire

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                HotKeyManager.globalHandler?()
                return noErr
            },
            1,
            &spec,
            nil,
            &eventHandlerRef
        )
    }

    deinit {
        unregister()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// 注册（会先注销旧的）
    func register(_ combo: Combo) {
        unregister()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x535A5550), id: 1)   // "SZUP"
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
            current = combo
        } else {
            hotKeyRef = nil
            current = nil
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        current = nil
    }

    var isRegistered: Bool { hotKeyRef != nil }

    // MARK: - 字符串解析

    /// "Ctrl + Alt + E" → Combo
    static func parse(_ text: String) -> Combo? {
        let parts = text
            .replacingOccurrences(of: "+", with: "\u{0}")
            .split(separator: "\u{0}")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let keyPart = parts.last else { return nil }

        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            switch part.lowercased() {
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            case "alt", "option":   modifiers |= UInt32(optionKey)
            case "shift":           modifiers |= UInt32(shiftKey)
            case "cmd", "command", "super", "win": modifiers |= UInt32(cmdKey)
            default: return nil
            }
        }
        if modifiers == 0 { return nil }   // 至少要有一个修饰键，否则会抢占普通输入

        guard let keyCode = keyCode(for: keyPart) else { return nil }
        return Combo(keyCode: keyCode, modifiers: modifiers)
    }

    private static func keyCode(for token: String) -> UInt32? {
        let upper = token.uppercased()
        // F1 - F12
        if upper.hasPrefix("F"), let n = Int(upper.dropFirst()), (1...12).contains(n) {
            return UInt32(0x7A + (n - 1))   // kVK_F1 = 0x7A
        }
        // 数字 0-9
        if upper.count == 1, let n = upper.first?.wholeNumberValue, (0...9).contains(n) {
            return UInt32(0x1B + n)         // kVK_ANSI_0 = 0x1B
        }
        // 字母 A-Z
        if upper.count == 1, let scalar = upper.unicodeScalars.first,
           scalar.value >= 65, scalar.value <= 90 {
            return UInt32(scalar.value - 65)   // kVK_ANSI_A = 0x00
        }
        return nil
    }

    /// 当前配置的组合键能不能注册成功（录入时就试一次）
    static func isAvailable(_ text: String) -> Bool {
        guard let combo = parse(text) else { return false }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x535A5550), id: 99)
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, id,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref {
            UnregisterEventHotKey(ref)
            return true
        }
        return false
    }
}
