// M10 对拍:Pattern 批量编排 + 实例操作 + 音色收藏文件往返。
import { writeFileSync, readFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
const repoRoot = new URL('..', import.meta.url).pathname;
let from = repoRoot;
try { readFileSync(`${repoRoot}dist/pattern-arrange.js`); } catch { from = '/tmp/sprout-dist'; }
const { validateProject } = await import(`${from}/dist/music.js`);
const { planPatternSeries, planPatternInstances } = await import(`${from}/dist/pattern-arrange.js`);
const { exportSoundFile, parseSoundFile } = await import(`${from}/dist/sound-bank.js`);
const { checksum } = await import(`${from}/dist/storage.js`);
const stripIds = value => JSON.parse(JSON.stringify(value, (k, v) => (k === 'id' || k === 'patternId' ? undefined : v)));

const files = [];
(function walk(d){ for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); if (e.isDirectory()) walk(p); else if (e.name.endsWith('.sprout')) files.push(p); } })(join(repoRoot, 'examples'));

const results = {};
for (const f of files) {
  const rel = relative(join(repoRoot, 'examples'), f);
  const p = validateProject(JSON.parse(readFileSync(f, 'utf8')));
  const entry = {};
  // 有 patterns 的:系列放置(关联/独立 × 2/4 份)与实例批量(静音/独立化/删除)
  if (p.patterns?.length) {
    const patternId = p.patterns[0].id;
    for (const track of p.tracks) {
      const kind = track.kind;
      const pk = p.patterns[0].kind;
      if (kind !== pk || (pk === 'drum' && p.patterns[0].instrument !== track.instrument)) continue;
      for (const [name, fn] of [
        ['series2', () => planPatternSeries(p, patternId, track.id, { start: 0, count: 2, extend: true })],
        ['series4-unlinked', () => planPatternSeries(p, patternId, track.id, { start: p.bars * 4, count: 4, linked: false, extend: true })],
      ]) {
        try { entry[`${track.instrument}:${name}`] = checksum(JSON.stringify(stripIds(fn().project))); }
        catch (e) { entry[`${track.instrument}:${name}`] = 'error:' + e.message; }
      }
      // 实例批量(需要现有关联块)
      const refs = p.tracks.flatMap(t => t.clips.filter(c => c.patternId === patternId).map(c => ({ trackId: t.id, clipId: c.id })));
      if (refs.length) {
        for (const action of ['mute', 'unmute', 'detach', 'delete']) {
          try { entry[`${track.instrument}:inst-${action}`] = checksum(JSON.stringify(stripIds(planPatternInstances(p, patternId, { clipIds: refs.map(r => r.clipId), action }).project))); }
          catch (e) { entry[`${track.instrument}:inst-${action}`] = 'error:' + e.message; }
        }
      }
      break;
    }
  }
  // 音色收藏:导出往返(前两条有 sound 的轨道)
  const soundTracks = p.tracks.filter(t => t.sound).slice(0, 2);
  if (soundTracks.length) {
    try {
      const presets = soundTracks.map((t, i) => ({ id: `sb-${i}`, name: t.name, instrument: t.instrument, sound: t.sound, createdAt: 1000, archived: false }));
      const file = exportSoundFile(presets);
      const back = parseSoundFile(file);
      entry['sounds-roundtrip'] = checksum(JSON.stringify(back.map(x => ({ instrument: x.instrument, sound: x.sound }))));
    } catch (e) { entry['sounds-roundtrip'] = 'error:' + e.message; }
  }
  results[rel] = entry;
}
const outDir = join(repoRoot, 'shared/canonical');
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'm10-logic.json'), JSON.stringify({ version: 1, arrange: results }, null, 1) + '\n');
const total = Object.values(results).reduce((n, e) => n + Object.keys(e).length, 0);
console.log(`m10-logic.json: ${Object.keys(results).length} fixtures, ${total} digests`);
