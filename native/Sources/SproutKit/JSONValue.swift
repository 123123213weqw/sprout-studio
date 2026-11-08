// 有序 JSON 值 + 解析器 + JS 风格序列化器。
// 关键约束:.sprout 是 JSON.stringify(project, null, 2) 的产物,
// key 顺序 = JS 对象插入顺序、数字格式 = JS 最短往返表示,两者都必须逐字节复刻。

import Foundation

public enum JSONValue {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)
}

/// 保持插入顺序的 JSON 对象(dict 语义 + JS key 顺序)。
public struct JSONObject {
    public private(set) var keys: [String] = []
    var map: [String: JSONValue] = [:]

    public init() {}

    public init(_ pairs: [(String, JSONValue)]) {
        for (k, v) in pairs { self[k] = v }
    }

    /// 键存在即为 true(null 也算存在,对应 JS 的 !== undefined 判断)。
    public func has(_ key: String) -> Bool { map[key] != nil }

    public subscript(_ key: String) -> JSONValue? {
        get { map[key] }
        set {
            if let v = newValue {
                if map[key] == nil { keys.append(key) }
                map[key] = v
            } else if map[key] != nil {
                map[key] = nil
                keys.removeAll { $0 == key }
            }
        }
    }

    public var pairs: [(String, JSONValue)] { keys.map { ($0, map[$0]!) } }
}

public extension JSONValue {
    var isObject: Bool { if case .object = self { return true }; return false }
    var isArray: Bool { if case .array = self { return true }; return false }
    var asObject: JSONObject? { if case .object(let o) = self { return o }; return nil }
    var asArray: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var asString: String? { if case .string(let s) = self { return s }; return nil }
    var asNumber: Double? { if case .number(let n) = self { return n }; return nil }
    var asBool: Bool? { if case .bool(let b) = self { return b }; return nil }

    /// 深比较;数字按 Double 精确相等(对拍数据是拷贝语义,理应完全一致)。
    func deepEquals(_ other: JSONValue) -> Bool {
        switch (self, other) {
        case (.null, .null): return true
        case (.bool(let a), .bool(let b)): return a == b
        case (.number(let a), .number(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.array(let a), .array(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.deepEquals($1) }
        case (.object(let a), .object(let b)):
            return a.keys == b.keys
                && a.keys.allSatisfy { a.map[$0]!.deepEquals(b.map[$0] ?? .null) }
        default: return false
        }
    }
}

// MARK: - 解析

public enum JSONParseError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String {
        if case .invalid(let m) = self { return m }
        return "invalid JSON"
    }
}

public func parseJSON(_ text: String) throws -> JSONValue {
    var parser = Parser(Array(text.utf8))
    let value = try parser.parseRoot()
    return value
}

private struct Parser {
    let bytes: [UInt8]
    var i = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func parseRoot() throws -> JSONValue {
        skipWhitespace()
        let v = try parseValue()
        skipWhitespace()
        guard i >= bytes.count else { throw JSONParseError.invalid("trailing characters") }
        return v
    }

    mutating func skipWhitespace() {
        while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x09 || bytes[i] == 0x0a || bytes[i] == 0x0d { i += 1 }
    }

    mutating func parseValue() throws -> JSONValue {
        guard i < bytes.count else { throw JSONParseError.invalid("unexpected end") }
        switch bytes[i] {
        case 0x7b: return .object(try parseObject())   // {
        case 0x5b: return .array(try parseArray())     // [
        case 0x22: return .string(try parseString())   // "
        case 0x74: try expect("true"); return .bool(true)
        case 0x66: try expect("false"); return .bool(false)
        case 0x6e: try expect("null"); return .null
        default: return .number(try parseNumber())
        }
    }

    mutating func expect(_ word: String) throws {
        for b in word.utf8 {
            guard i < bytes.count, bytes[i] == b else { throw JSONParseError.invalid("bad literal") }
            i += 1
        }
    }

    mutating func parseObject() throws -> JSONObject {
        i += 1 // {
        var obj = JSONObject()
        skipWhitespace()
        if i < bytes.count, bytes[i] == 0x7d { i += 1; return obj }
        while true {
            skipWhitespace()
            guard i < bytes.count, bytes[i] == 0x22 else { throw JSONParseError.invalid("expected key") }
            let key = try parseString()
            skipWhitespace()
            guard i < bytes.count, bytes[i] == 0x3a else { throw JSONParseError.invalid("expected :") }
            i += 1
            skipWhitespace()
            obj[key] = try parseValue()
            skipWhitespace()
            guard i < bytes.count else { throw JSONParseError.invalid("unexpected end in object") }
            if bytes[i] == 0x2c { i += 1; continue }
            if bytes[i] == 0x7d { i += 1; return obj }
            throw JSONParseError.invalid("expected , or }")
        }
    }

    mutating func parseArray() throws -> [JSONValue] {
        i += 1 // [
        var items: [JSONValue] = []
        skipWhitespace()
        if i < bytes.count, bytes[i] == 0x5d { i += 1; return items }
        while true {
            skipWhitespace()
            items.append(try parseValue())
            skipWhitespace()
            guard i < bytes.count else { throw JSONParseError.invalid("unexpected end in array") }
            if bytes[i] == 0x2c { i += 1; continue }
            if bytes[i] == 0x5d { i += 1; return items }
            throw JSONParseError.invalid("expected , or ]")
        }
    }

    mutating func parseString() throws -> String {
        i += 1 // opening quote
        var out: [UInt8] = []
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x22 { i += 1; guard let s = String(bytes: out, encoding: .utf8) else { throw JSONParseError.invalid("bad utf8") }; return s }
            if b == 0x5c { // backslash
                i += 1
                guard i < bytes.count else { throw JSONParseError.invalid("bad escape") }
                switch bytes[i] {
                case 0x22: out.append(0x22)
                case 0x5c: out.append(0x5c)
                case 0x2f: out.append(0x2f)
                case 0x62: out.append(0x08)
                case 0x66: out.append(0x0c)
                case 0x6e: out.append(0x0a)
                case 0x72: out.append(0x0d)
                case 0x74: out.append(0x09)
                case 0x75: // \uXXXX(含代理对)
                    let hi = try parseHex4()
                    var scalar: UInt32
                    if hi >= 0xD800 && hi <= 0xDBFF {
                        guard i + 6 < bytes.count + 1, bytes[i + 1] == 0x5c, bytes[i + 2] == 0x75 else {
                            throw JSONParseError.invalid("lone surrogate")
                        }
                        i += 2
                        let lo = try parseHex4()
                        guard lo >= 0xDC00 && lo <= 0xDFFF else { throw JSONParseError.invalid("bad surrogate pair") }
                        scalar = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
                    } else {
                        scalar = hi
                    }
                    guard let u = Unicode.Scalar(scalar) else { throw JSONParseError.invalid("bad scalar") }
                    out.append(contentsOf: Array(String(Character(u)).utf8))
                default: throw JSONParseError.invalid("bad escape char")
                }
                i += 1
            } else if b < 0x20 {
                throw JSONParseError.invalid("control char in string")
            } else {
                out.append(b)
            }
            i += 1
        }
        throw JSONParseError.invalid("unterminated string")
    }

    /// 调用方保证当前位置是 \uXXXX 的第一个 hex,i 指向首 hex;返回后 i 停在第 4 个 hex 上。
    mutating func parseHex4() throws -> UInt32 {
        var v: UInt32 = 0
        for k in 1...4 {
            guard i + k < bytes.count else { throw JSONParseError.invalid("bad \\u escape") }
            guard let d = hexDigit(bytes[i + k]) else { throw JSONParseError.invalid("bad \\u escape") }
            v = v << 4 | d
        }
        i += 4
        return v
    }

    func hexDigit(_ b: UInt8) -> UInt32? {
        switch b {
        case 0x30...0x39: return UInt32(b - 0x30)
        case 0x61...0x66: return UInt32(b - 0x61 + 10)
        case 0x41...0x46: return UInt32(b - 0x41 + 10)
        default: return nil
        }
    }

    mutating func parseNumber() throws -> Double {
        let start = i
        if i < bytes.count, bytes[i] == 0x2d { i += 1 }
        while i < bytes.count, (0x30...0x39).contains(bytes[i]) { i += 1 }
        if i < bytes.count, bytes[i] == 0x2e {
            i += 1
            while i < bytes.count, (0x30...0x39).contains(bytes[i]) { i += 1 }
        }
        if i < bytes.count, bytes[i] == 0x65 || bytes[i] == 0x45 {
            i += 1
            if i < bytes.count, bytes[i] == 0x2b || bytes[i] == 0x2d { i += 1 }
            while i < bytes.count, (0x30...0x39).contains(bytes[i]) { i += 1 }
        }
        guard i > start, let s = String(bytes: bytes[start..<i], encoding: .utf8), let d = Double(s) else {
            throw JSONParseError.invalid("bad number")
        }
        return d
    }
}

// MARK: - 序列化(JSON.stringify 风格)

/// JSON.stringify(value, null, 2) 的等价输出(无尾换行)。
public func jsStringify(_ value: JSONValue) -> String {
    var out = ""
    write(value, indent: 0, into: &out)
    return out
}

private func write(_ value: JSONValue, indent: Int, into out: inout String) {
    switch value {
    case .null: out += "null"
    case .bool(let b): out += b ? "true" : "false"
    case .number(let d): out += jsNumber(d)
    case .string(let s): out += jsQuote(s)
    case .array(let items):
        if items.isEmpty { out += "[]"; return }
        let pad = String(repeating: " ", count: indent + 2)
        out += "[\n"
        for (idx, item) in items.enumerated() {
            out += pad
            write(item, indent: indent + 2, into: &out)
            out += idx == items.count - 1 ? "\n" : ",\n"
        }
        out += String(repeating: " ", count: indent) + "]"
    case .object(let obj):
        if obj.keys.isEmpty { out += "{}"; return }
        let pad = String(repeating: " ", count: indent + 2)
        out += "{\n"
        for (idx, key) in obj.keys.enumerated() {
            out += pad + jsQuote(key) + ": "
            write(obj.map[key]!, indent: indent + 2, into: &out)
            out += idx == obj.keys.count - 1 ? "\n" : ",\n"
        }
        out += String(repeating: " ", count: indent) + "}"
    }
}

func jsQuote(_ s: String) -> String {
    var out = "\""
    for u in s.unicodeScalars {
        switch u {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\u{08}": out += "\\b"
        case "\u{0c}": out += "\\f"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if u.value < 0x20 {
                out += String(format: "\\u%04x", u.value)
            } else {
                out.unicodeScalars.append(u) // 非 ASCII 原样输出,与 JS 一致
            }
        }
    }
    return out + "\""
}

/// JS Number → 字符串(最短往返;整数值不带小数点)。
func jsNumber(_ d: Double) -> String {
    guard d.isFinite else { return "null" }
    if d == 0 { return "0" } // 含 -0,JS stringify(-0) === "0"
    if d.rounded() == d, abs(d) < 1e15, let i = Int64(exactly: d) { return String(i) }
    var s = d.description
    if s.contains("e") || s.contains("E") { s = expandExponent(s) }
    return s
}

/// Swift 在 <1e-4 时用指数记法而 JS 到 <1e-6 才用;工程数据被 round4 过,这里只是保险。
func expandExponent(_ s: String) -> String {
    var negative = false
    var body = s
    if body.hasPrefix("-") { negative = true; body.removeFirst() }
    guard let eIdx = body.firstIndex(where: { $0 == "e" || $0 == "E" }) else { return s }
    var mantissa = String(body[body.startIndex..<eIdx])
    let exp = Int(body[body.index(after: eIdx)...]) ?? 0
    var point = mantissa.count // 无小数点时加 ".0" 再展开
    if !mantissa.contains(".") { mantissa += ".0" }
    if let p = mantissa.firstIndex(of: ".") {
        point = mantissa.distance(from: mantissa.startIndex, to: p)
        mantissa.remove(at: p)
    }
    let digits = Array(mantissa)
    let newPoint = Int(point) + exp
    var out: String
    if newPoint <= 0 {
        out = "0." + String(repeating: "0", count: -newPoint) + String(digits)
    } else if newPoint >= digits.count {
        out = String(digits) + String(repeating: "0", count: newPoint - digits.count) + ".0"
    } else {
        out = String(digits[0..<newPoint]) + "." + String(digits[newPoint...])
    }
    return negative ? "-" + out : out
}

// MARK: - JS 数值语义

public func jsIsFinite(_ d: Double) -> Bool { d.isFinite }
public func jsIsInteger(_ d: Double) -> Bool { d.isFinite && d.rounded() == d }

/// +(x.toFixed(f)) 的精确实现:JS 对 double 的精确十进制展开舍入,
/// 不能先乘 10^f 再舍入(乘法自身的 double 舍入会在 .5 边界翻转结果)。
/// 用 m×2^e 整数分解:round(m·5^f / 2^-e-f),半值向上(正数场景,与 JS "pick larger n" 一致)。
public func jsToFixedValue(_ x: Double, _ f: Int) -> Double {
    guard x.isFinite, x != 0 else { return x }
    guard x >= -Double(UInt64.max / 2), x <= Double(UInt64.max / 2) else { return x }
    let sign: Double = x < 0 ? -1 : 1
    let ax = abs(x)
    // ax = significand × 2^exponent,significand ∈ [1,2)
    let exp = ax.exponent
    guard ax.isNormal, exp >= -60, exp + f <= 60 else {
        // 覆盖不到的量级(工程数据不会出现):回退近似
        let scale = pow(10, Double(f))
        return sign * ((ax * scale).rounded(.toNearestOrAwayFromZero) / scale)
    }
    // m = ax.significand × 2^52(精确整数)
    let m = UInt64((ax.significand * 4_503_599_627_370_496.0))
    let pow5: UInt64 = f == 0 ? 1 : f == 1 ? 5 : f == 2 ? 25 : f == 3 ? 125 : 625
    let num = m * pow5
    // ax·10^f = num × 2^(exp+f-52);右移位数 = 52-exp-f
    let shift = 52 - exp - f
    let n: UInt64
    if shift <= 0 {
        let up = UInt64(max(0, -shift))
        n = up >= 64 ? num : num << up
    } else if shift >= 64 {
        n = 0
    } else {
        let half = num >> UInt64(shift - 1)        // 最低位是精确的 .5 判定位
        n = (half + 1) >> 1
    }
    let scale = pow(10, Double(f))
    return sign * (Double(n) / scale)
}

/// +(x.toFixed(4)):四舍五入到 4 位小数。
public func round4(_ d: Double) -> Double { jsToFixedValue(d, 4) }
public func clamp(_ n: Double, _ lo: Double, _ hi: Double) -> Double { Swift.max(lo, Swift.min(hi, n)) }

/// JS sort 默认不稳定;这里用下标决胜实现稳定排序,语义对齐现代 JS 引擎。
public func stableSorted<T>(_ items: [T], by areInIncreasingOrder: (T, T) -> Bool) -> [T] {
    items.enumerated().sorted { l, r in
        if areInIncreasingOrder(l.element, r.element) { return true }
        if areInIncreasingOrder(r.element, l.element) { return false }
        return l.offset < r.offset
    }.map(\.element)
}

public func jsUid() -> String { UUID().uuidString.lowercased() }

/// ^[a-zA-Z0-9_-]{1,80}$
public func jsSafeId(_ s: String) -> Bool {
    guard !s.isEmpty, s.count <= 80 else { return false }
    return s.allSatisfy { ($0.isASCII && $0.isLetter) || ($0.isNumber && $0.isASCII) || $0 == "_" || $0 == "-" }
}
