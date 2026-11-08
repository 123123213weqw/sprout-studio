// ensureClips:音块所有权与音符归属。对应 dist/clips.js 的同名导出(仅校验路径)。

func ensureClips(_ project: inout JSONObject, strict: Bool) throws {
    let end = (jnum(project, "bars", 0)) * 4
    var clipIds = Set<String>()

    if project.has("sections"), let sections = project["sections"] {
        project["sections"] = .array(try normalizeSections(sections, end))
    }

    guard var tracks = project["tracks"]?.asArray else {
        throw SproutError("工程格式不正确")
    }
    for ti in tracks.indices {
        guard var track = tracks[ti].asObject else { continue }
        let trackName = track["name"]?.asString ?? ""

        if !track.has("clips") {
            let span = (jnum(project, "version", 0)) >= 2 ? 8.0 : end
            var built: [JSONValue] = []
            var start: Double = 0
            while start < end {
                var c = JSONObject()
                c["id"] = .string(jsUid())
                c["name"] = .string(trackName)
                c["start"] = .number(start)
                c["length"] = .number(min(span, end - start))
                c["muted"] = .bool(false)
                built.append(.object(c))
                start += span
            }
            track["clips"] = .array(built)
        }

        guard let rawClips = track["clips"]?.asArray, rawClips.count <= 256 else {
            throw SproutError("音块数量不正确")
        }
        var clips: [JSONObject] = []
        for cv in rawClips {
            guard let c = cv.asObject else { throw SproutError("音块位置或长度不合法") }
            let startNum: Double? = c["start"]?.asNumber
            let lengthNum: Double? = c["length"]?.asNumber
            guard let s = startNum, let l = lengthNum else { throw SproutError("音块位置或长度不合法") }
            let geometryOk: Bool = jsIsFinite(s) && jsIsFinite(l) && s >= 0 && l >= 0.25 && s + l <= end + EPS
            guard geometryOk else { throw SproutError("音块位置或长度不合法") }
            let cid: String
            if let raw = c["id"]?.asString, jsSafeId(raw), !clipIds.contains(raw) { cid = raw } else { cid = jsUid() }
            clipIds.insert(cid)
            var out = JSONObject()
            out["id"] = .string(cid)
            out["name"] = .string(jsStringField(c["name"], fallback: trackName, limit: 40))
            out["start"] = .number(round4(s))
            out["length"] = .number(round4(l))
            out["muted"] = .bool(c["muted"]?.asBool == true)
            if let pid = c["patternId"] { out["patternId"] = pid }
            clips.append(out)
        }
        clips = stableSorted(clips) { jnum($0, "start") < jnum($1, "start") }
        for i in stride(from: 1, to: clips.count, by: 1) {
            let prev = clips[i - 1], cur = clips[i]
            if (jnum(cur, "start", 0)) < (jnum(prev, "start", 0)) + (jnum(prev, "length", 0)) - EPS {
                throw SproutError("同一轨道的音块不能重叠")
            }
        }

        var notes = track["notes"]?.asArray ?? []
        for ni in notes.indices {
            guard var note = notes[ni].asObject else { continue }
            let nStart = jnum(note, "start", 0)
            let nDur = jnum(note, "duration", 0)

            var regionIndex: Int? = clips.firstIndex { c in
                let cs = jnum(c, "start", 0), cl = jnum(c, "length", 0)
                return nStart >= cs - EPS && nStart < cs + cl - EPS
            }
            if regionIndex == nil {
                if strict { throw SproutError("音符必须位于一个音块内") }
                var previousEnd: Double? = nil
                for c in clips {
                    let cs = jnum(c, "start", 0), cl = jnum(c, "length", 0)
                    if cs + cl <= nStart + EPS { previousEnd = cs + cl }
                }
                var nextStart: Double? = nil
                for c in clips {
                    if let cs = c["start"]?.asNumber, cs > nStart { nextStart = cs; break }
                }
                let regionStart = max(previousEnd ?? 0, (nStart / 4).rounded(.down) * 4)
                let regionStop = min(nextStart ?? end, max(regionStart + 4, ((nStart + nDur) / 4).rounded(.up) * 4))
                var region = JSONObject()
                region["id"] = .string(jsUid())
                region["name"] = .string(trackName)
                region["start"] = .number(round4(regionStart))
                region["length"] = .number(round4(regionStop - regionStart))
                region["muted"] = .bool(false)
                if let l = region["length"]?.asNumber, l < 0.25 || clips.count >= 256 {
                    throw SproutError("这个空隙放不下音块")
                }
                let regionId = region["id"]?.asString ?? ""
                clips.append(region)
                clips = stableSorted(clips) { jnum($0, "start") < jnum($1, "start") }
                regionIndex = clips.firstIndex { $0["id"]?.asString == regionId }
            }

            let region = clips[regionIndex ?? 0]
            let rStart = jnum(region, "start", 0)
            let rLen = jnum(region, "length", 0)
            let rEnd = rStart + rLen
            if strict, nStart + nDur > rEnd + EPS {
                throw SproutError("音符超出所属音块的边界")
            }
            if let to = note["timingOffset"]?.asNumber, jsIsFinite(to) {
                let upper = rStart + rLen - nStart - min(nDur, rStart + rLen - nStart)
                note["timingOffset"] = .number(round4(max(rStart - nStart, min(to, upper))))
            }
            note["duration"] = .number(round4(min(nDur, rEnd - nStart)))
            if let d = note["duration"]?.asNumber, d < 0.03125 - EPS {
                throw SproutError("音符距离音块边缘太近")
            }
            notes[ni] = .object(note)
        }
        track["clips"] = .array(clips.map { .object($0) })
        track["notes"] = .array(notes)
        tracks[ti] = .object(track)
    }
    project["tracks"] = .array(tracks)
    project["version"] = .number(project.has("patterns") ? 3 : 2)
    try synchronizePatterns(&project, strict: strict)
}
