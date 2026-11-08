// WAV 读写 + SHA-256。对应 dist/sample-library.js 的 decodeSamplePCM
// 与 dist/audio.js 的 encodeWAV(PCM16、[-1,1] 钳位、负满幅不对称缩放)。

import Foundation

public struct SampleBuffer {
    public let frames: Int
    public let sampleRate: Double
    public let channels: [[Double]]
    public var duration: Double { Double(frames) / sampleRate }
}

public enum WavError: Error, CustomStringConvertible {
    case size, riff, chunk, fmt, dataDuplicate, trailing, unsupported, length
    public var description: String {
        switch self {
        case .size: return "采样文件大小不正确"
        case .riff: return "采样不是完整 WAV"
        case .chunk: return "采样 WAV 区块损坏"
        case .fmt: return "采样格式区块不正确"
        case .dataDuplicate: return "采样数据区块重复"
        case .trailing: return "采样 WAV 末尾区块不完整"
        case .unsupported: return "仅支持完整的 16-bit PCM 采样"
        case .length: return "采样长度不正确"
        }
    }
}

/// decodeSamplePCM 的逐条移植(错误文案一致)。
public func decodeSamplePCM(_ bytes: [UInt8]) throws -> SampleBuffer {
    guard bytes.count >= 44, bytes.count <= 1_200_000 else { throw WavError.size }
    func ascii(_ off: Int, _ n: Int) -> String {
        String(decoding: bytes[off..<off + n], as: UTF8.self)
    }
    func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
    func u32(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24 }

    guard ascii(0, 4) == "RIFF", ascii(8, 4) == "WAVE", u32(4) + 8 == bytes.count else { throw WavError.riff }
    var fmt: (format: Int, channels: Int, rate: Int, byteRate: Int, align: Int, bits: Int)? = nil
    var data: (start: Int, size: Int)? = nil
    var off = 12
    while off + 8 <= bytes.count {
        let id = ascii(off, 4)
        let size = u32(off + 4)
        let start = off + 8
        if start + size > bytes.count { throw WavError.chunk }
        if id == "fmt " {
            if fmt != nil || size < 16 { throw WavError.fmt }
            fmt = (u16(start), u16(start + 2), u32(start + 4), u32(start + 8), u16(start + 12), u16(start + 14))
        }
        if id == "data" {
            if data != nil { throw WavError.dataDuplicate }
            data = (start, size)
        }
        off = start + size + (size % 2)
    }
    guard off == bytes.count else { throw WavError.trailing }
    guard let f = fmt, let d = data, f.format == 1, f.bits == 16, f.channels == 1 || f.channels == 2,
          f.rate >= 16000, f.rate <= 96000, f.align == f.channels * 2, f.byteRate == f.rate * f.align,
          d.size % f.align == 0 else { throw WavError.unsupported }
    let frames = d.size / f.align
    guard frames >= 16, Double(frames) / Double(f.rate) <= 6.1 else { throw WavError.length }
    var channels: [[Double]] = Array(repeating: [], count: f.channels)
    for ch in 0..<f.channels {
        channels[ch] = [Double](repeating: 0, count: frames)
    }
    for i in 0..<frames {
        for ch in 0..<f.channels {
            let o = d.start + (i * f.align + ch * 2)
            let raw = Int16(bitPattern: UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8)
            channels[ch][i] = Double(raw) / 32768
        }
    }
    return SampleBuffer(frames: frames, sampleRate: Double(f.rate), channels: channels)
}

/// encodeWAV 移植:PCM16 立体声,clamp 后负 32768 / 正 32767。
public func encodeWAV(left: [Double], right: [Double], sampleRate: Double) -> [UInt8] {
    let length = min(left.count, right.count)
    let channels = 2
    let bytes = 44 + length * channels * 2
    var out = [UInt8](repeating: 0, count: bytes)
    func put(_ off: Int, _ s: String) { for (i, c) in s.utf8.enumerated() { out[off + i] = c } }
    func u16(_ o: Int, _ v: Int) { out[o] = UInt8(v & 255); out[o + 1] = UInt8((v >> 8) & 255) }
    func u32(_ o: Int, _ v: Int) {
        out[o] = UInt8(v & 255); out[o + 1] = UInt8((v >> 8) & 255)
        out[o + 2] = UInt8((v >> 16) & 255); out[o + 3] = UInt8((v >> 24) & 255)
    }
    put(0, "RIFF"); u32(4, bytes - 8); put(8, "WAVE"); put(12, "fmt ")
    u32(16, 16); u16(20, 1); u16(22, channels); u32(24, Int(sampleRate))
    u32(28, Int(sampleRate) * channels * 2); u16(32, channels * 2); u16(34, 16)
    put(36, "data"); u32(40, bytes - 44)
    var off = 44
    for i in 0..<length {
        for ch in 0..<2 {
            let x = max(-1, min(1, ch == 0 ? left[i] : right[i]))
            let s = x < 0 ? Int16(x * 32768) : Int16(x * 32767)
            out[off] = UInt8(UInt16(bitPattern: s) & 255)
            out[off + 1] = UInt8(UInt16(bitPattern: s) >> 8)
            off += 2
        }
    }
    return out
}

// MARK: - SHA-256(纯 Swift 实现,Linux 亦可用;与 release-media.json/samples.json 校验一致)

public func sha256Hex(_ data: [UInt8]) -> String {
    var k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]
    var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    var message = data
    let bitLength = UInt64(data.count) * 8
    message.append(0x80)
    while message.count % 64 != 56 { message.append(0) }
    for shift in stride(from: 56, through: 0, by: -8) { message.append(UInt8((bitLength >> UInt64(shift)) & 255)) }

    var w = [UInt32](repeating: 0, count: 64)
    for chunkStart in stride(from: 0, to: message.count, by: 64) {
        for i in 0..<16 {
            let o = chunkStart + i * 4
            w[i] = UInt32(message[o]) << 24 | UInt32(message[o + 1]) << 16 | UInt32(message[o + 2]) << 8 | UInt32(message[o + 3])
        }
        for i in 16..<64 {
            let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
        for i in 0..<64 {
            let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            let ch = (e & f) ^ (~e & g)
            let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
            let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let t2 = s0 &+ maj
            hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
        }
        h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
        h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
    }
    return h.map { String(format: "%08x", $0) }.joined()
}

private func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
    (x >> n) | (x << (32 - n))
}
