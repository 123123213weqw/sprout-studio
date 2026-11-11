// sproutkit:.sprout / .sprout-patterns 的命令行校验与对拍工具。
// 用法:
//   sproutkit validate <file>                 解析 + 校验,输出规范 JSON
//   sproutkit check <file> <canonical-file>   校验后与基准文件字节级比较
import Foundation
import SproutKit
import SproutAudio

func run() -> Int32 {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        FileHandle.standardError.write("用法: sproutkit validate <file> | check <file> <canonical>\n".data(using: .utf8)!)
        return 2
    }
    if args[1] == "capture" {
        do {
            let project = try validateProject(try loadSprout(text: String(contentsOf: URL(fileURLWithPath: args[2]), encoding: .utf8))
            )
            let tracks = (project["tracks"]?.asArray ?? []).compactMap { $0.asObject }
            guard let track = tracks.first,
                  let clip = (track["clips"]?.asArray ?? []).first?.asObject,
                  let trackId = track["id"]?.asString, let clipId = clip["id"]?.asString else { return 2 }
            let result = try capturePattern(project, trackId: trackId, clipId: clipId, name: "测试乐句", linkSource: true)
            print(jsCompactStringify(stripIdsForDump(.object(result.project))))
            return 0
        } catch {
            FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
            return 1
        }
    }
    if args[1] == "fill" {
        do {
            let project = try validateProject(try loadSprout(text: String(contentsOf: URL(fileURLWithPath: args[2]), encoding: .utf8)))
            let sections = (project["sections"]?.asArray ?? []).compactMap { $0.asObject }
            guard let section = sections.last, let sectionId = section["id"]?.asString else { return 2 }
            let drumIds = (project["tracks"]?.asArray ?? []).compactMap { $0.asObject }
                .filter { $0["kind"]?.asString == "drum" }.map { $0["id"]?.asString ?? "" }
            var controls = JSONObject()
            controls["style"] = .string(args.count > 3 ? args[3] : "gentle")
            controls["bars"] = .number(1)
            controls["energy"] = .number(70)
            controls["seed"] = .number(42)
            controls["fillGaps"] = .bool(true)
            let result = try planSectionFill(project, sectionId: sectionId, trackIds: drumIds, controls: controls)
            print(jsCompactStringify(stripIdsForDump(.object(result.project))))
            return 0
        } catch {
            FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
            return 1
        }
    }
    if args[1] == "fromprompt" {
        do {
            let project = try validateProject(try loadSprout(text: String(contentsOf: URL(fileURLWithPath: args[2]), encoding: .utf8)))
            var controls = JSONObject()
            controls["seed"] = .number(7777)
            let result = try generateFromPrompt(project, args[3], scope: args.count > 4 ? args[4] : "all", controls: controls)
            print(jsCompactStringify(stripIdsForDump(.object(result.project))))
            return 0
        } catch {
            FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
            return 1
        }
    }
    if args[1] == "generate" {
        // generate <style> <key> <bars> <seed> [--controls](不依赖文件)
        guard args.count >= 6 else { FileHandle.standardError.write("参数不足\n".data(using: .utf8)!); return 2 }
        var composition: JSONObject? = nil
        if args.contains("--controls") {
            var c = JSONObject()
            c["density"] = .number(80); c["complexity"] = .number(80); c["energy"] = .number(75)
            c["humanize"] = .number(25); c["progression"] = .string("lift")
            c["voiceLeading"] = .bool(false); c["seed"] = .number(424242)
            composition = c
        }
        do {
            let project = try generateProject(GenerateOptions(
                style: args[2], key: args[3], bars: Double(args[4]) ?? 4,
                seed: Int(args[5]) ?? 1, composition: composition
            ))
            print(jsCompactStringify(stripIdsForDump(.object(project))))
            return 0
        } catch {
            FileHandle.standardError.write("生成失败:\(error)\n".data(using: .utf8)!)
            return 1
        }
    }
    let url = URL(fileURLWithPath: args[2])
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        FileHandle.standardError.write("无法读取 \(args[2])\n".data(using: .utf8)!)
        return 2
    }
    do {
        let value = try loadSprout(text: text)
        let output: String
        if args[1] == "check" {
            guard args.count >= 4 else { return 2 }
            let canonical = try String(contentsOf: URL(fileURLWithPath: args[3]), encoding: .utf8)
            output = try validateProject(value) |> { serializeProject($0) }
            if output == canonical {
                print("SAME  \(args[2])")
                return 0
            }
            // 找出第一处差异
            let a = Array(output.utf8), b = Array(canonical.utf8)
            var idx = 0
            while idx < a.count && idx < b.count && a[idx] == b[idx] { idx += 1 }
            let ctxA = String(decoding: a[max(0, idx - 60)..<min(a.count, idx + 60)], as: UTF8.self)
            let ctxB = String(decoding: b[max(0, idx - 60)..<min(b.count, idx + 60)], as: UTF8.self)
            print("DIFF  \(args[2]) @byte \(idx)\n  swift: …\(ctxA)…\n  js:    …\(ctxB)…")
            return 1
        } else if args[1] == "render" {
            // render <file.sprout> --samples <dir> --out <file.wav>
            var samples: String? = nil
            var out = "sprout-render.wav"
            if let i = args.firstIndex(of: "--samples"), i + 1 < args.count { samples = args[i + 1] }
            if let i = args.firstIndex(of: "--out"), i + 1 < args.count { out = args[i + 1] }
            let project = try validateProject(value)
            let (wav, stats) = try renderWAV(project, options: RenderOptions(samplesRoot: samples.map { URL(fileURLWithPath: $0) }))
            try Data(wav).write(to: URL(fileURLWithPath: out))
            print(String(format: "OK  %@  %.1fs  peak %.3f  %@", out, stats.seconds, stats.peak, stats.nonSilent ? "非静音" : "静音!"))
            return 0
        } else if args[1] == "transform" {
            // transform <file> transpose <key> | resize <bars> <blank|repeat>
            guard args.count >= 4 else { FileHandle.standardError.write("参数不足\n".data(using: .utf8)!); return 2 }
            let project = try validateProject(value)
            let out: JSONObject
            if args[3] == "transpose" {
                out = try transposeProject(project, toKey: args[4])
            } else {
                let fill = args.count >= 6 ? args[5] : "repeat"
                out = try resizeProject(project, toBars: Double(args[4]) ?? 16, fill: fill)
            }
            print(jsCompactStringify(stripIdsForDump(.object(out))))
            return 0
        } else if args[1] == "mididump" {
            // 编码再解码,输出去掉随机 id 的紧凑工程 JSON(对拍调试用)
            let project = try validateProject(value)
            let bytes = try encodeMIDI(project)
            let decoded = try decodeMIDI(bytes)
            print(jsCompactStringify(stripIdsForDump(.object(decoded.project))))
            return 0
        } else {
            if url.path.hasSuffix(".sprout-patterns") {
                output = serializePatterns(try validatePatternLibrary(value))
            } else {
                output = serializeProject(try validateProject(value))
            }
            print(output)
            return 0
        }
    } catch {
        FileHandle.standardError.write("校验失败:\(error)\n".data(using: .utf8)!)
        return 1
    }
}

infix operator |>: AdditionPrecedence
func |><T, U>(_ value: T, _ f: (T) throws -> U) rethrows -> U { try f(value) }

exit(run())
