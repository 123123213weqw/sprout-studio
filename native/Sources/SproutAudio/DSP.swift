// 基础 DSP:RBJ 双二阶、等功率声像、振荡器、LCG 噪声、软拐压缩器。
// 全部纯 Swift(Linux 可测),对应 Web Audio 各节点的标准语义。

import Foundation

// MARK: - Biquad(RBJ cookbook;Web Audio 的 lowpass/highpass/bandpass 定义)

public struct Biquad {
    var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    public init() {}

    public init(lowpass cutoff: Double, Q: Double, sampleRate: Double) {
        let w0 = 2 * Double.pi * min(cutoff, sampleRate * 0.49) / sampleRate
        let c = cos(w0), s = sin(w0), alpha = s / (2 * Q)
        b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2
        let a0 = 1 + alpha
        a1 = -2 * c / a0; a2 = (1 - alpha) / a0
        b0 /= a0; b1 /= a0; b2 /= a0
    }

    public init(highpass cutoff: Double, Q: Double, sampleRate: Double) {
        let w0 = 2 * Double.pi * min(cutoff, sampleRate * 0.49) / sampleRate
        let c = cos(w0), s = sin(w0), alpha = s / (2 * Q)
        b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2
        let a0 = 1 + alpha
        a1 = -2 * c / a0; a2 = (1 - alpha) / a0
        b0 /= a0; b1 /= a0; b2 /= a0
    }

    /// Web Audio bandpass(峰值 0dB:H(s)=s/(s²+s/Q+1))
    public init(bandpass cutoff: Double, Q: Double, sampleRate: Double) {
        let w0 = 2 * Double.pi * min(cutoff, sampleRate * 0.49) / sampleRate
        let c = cos(w0), s = sin(w0), alpha = s / (2 * Q)
        b0 = alpha; b1 = 0; b2 = -alpha
        let a0 = 1 + alpha
        a1 = -2 * c / a0; a2 = (1 - alpha) / a0
        b0 /= a0; b2 /= a0
    }

    public mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

// MARK: - 声像(StereoPannerNode 等功率律)

@inline(__always)
func panGains(_ pan: Double) -> (Double, Double) {
    let theta = (max(-1, min(1, pan)) + 1) * Double.pi / 4
    return (cos(theta), sin(theta))
}

// MARK: - 振荡器(相位 0..<1,与 Web Audio 标准波形一致)

public enum OscWave: String {
    case sine, square, sawtooth, triangle
}

@inline(__always)
func oscSample(_ wave: OscWave, _ phase: Double) -> Double {
    switch wave {
    case .sine: return sin(2 * Double.pi * phase)
    case .square: return phase < 0.5 ? 1 : -1
    case .sawtooth: return 2 * phase - 1
    case .triangle:
        // 0 起音上行:0→1(.25)→-1(.75)→0
        if phase < 0.25 { return 4 * phase }
        if phase < 0.75 { return 2 - 4 * phase }
        return 4 * phase - 4
    }
}

// MARK: - LCG 噪声(audio.js noise():种子 1729,×16807 mod 2^31-1)

public struct LcgNoise {
    var state: UInt64 = 1729
    public init() {}
    public mutating func next() -> Double {
        state = (state * 16807) % 2147483647
        return Double(state) / 2147483647 * 2 - 1
    }
    /// 预生成 1 秒缓冲(Web Audio createBuffer 一次生成后循环)
    public static func buffer(sampleRate: Double) -> [Double] {
        var noise = LcgNoise()
        return (0..<Int(sampleRate)).map { _ in noise.next() }
    }
}

// MARK: - 软拐压缩器(Web Audio DynamicsCompressor 语义)

/// Web Audio 规范的软拐曲线(x、y 均为 dB)。
@inline(__always)
func compressorCurve(x: Double, threshold: Double, knee: Double, slope: Double) -> Double {
    if 2 * (x - threshold) < -knee { return x }
    if 2 * abs(x - threshold) <= knee {
        let d = x - threshold + knee / 2
        return x + slope * d * d / (2 * knee)
    }
    return x + slope * (x - threshold)
}

public struct MasterCompressor {
    let threshold: Double   // dB
    let knee: Double        // dB
    let ratio: Double
    var attackCoef: Double
    var releaseCoef: Double
    var detectorDb = -1000.0
    var heldGain = 1.0

    public init(threshold: Double = -14, knee: Double = 12, ratio: Double = 3,
                attack: Double = 0.005, release: Double = 0.17, sampleRate: Double) {
        self.threshold = threshold
        self.knee = knee
        self.ratio = ratio
        self.attackCoef = 1 - exp(-1 / (attack * sampleRate))
        self.releaseCoef = 1 - exp(-1 / (release * sampleRate))
    }

    public mutating func process(_ x: Double) -> Double {
        let db = 20 * log10(max(abs(x), 1e-9))
        // 增大方向用 attack,回落方向用 release(对检波器 dB)
        let coef = db > detectorDb ? attackCoef : releaseCoef
        detectorDb += coef * (db - detectorDb)
        let yDb = compressorCurve(x: detectorDb, threshold: threshold, knee: knee, slope: 1 / ratio - 1)
        let gain = pow(10, (yDb - detectorDb) / 20)
        // 增益本身也平滑,避免抽搐
        heldGain += 0.5 * (gain - heldGain)
        return x * heldGain
    }
}
