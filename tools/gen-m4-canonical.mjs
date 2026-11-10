// M4 对拍:clip 操作与 Pattern CRUD 应用于全部 fixtures(确定性输入,uid 剥离摘要)。
import { writeFileSync, readFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
const repoRoot = new URL('..', import.meta.url).pathname;
let from = repoRoot;
try { readFileSync(`${repoRoot}dist/clips.js`); } catch { from = '/tmp/sprout-dist'; }
const { validateProject } = await import(`${from}/dist/music.js`);
const { resizeClip, moveClip, splitClip, repeatClip, updateClip, removeClip } = await import(`${from}/dist/clips.js`);
const { capturePattern, updatePattern, removePattern, detachPatternClip, placePattern } = await import(`${from}/dist/patterns.js`);
const { checksum } = await import(`${from}/dist/storage.js`);
const stripIds = value => JSON.parse(JSON.stringify(value, (k, v) => (k === 'id' || k === 'patternId' ? undefined : v)));

const files = [];
(function walk(d){ for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); if (e.isDirectory()) walk(p); else if (e.name.endsWith('.sprout')) files.push(p); } })(join(repoRoot, 'examples'));

const ops = {};
for (const f of files) {
  const rel = relative(join(repoRoot, 'examples'), f);
  const p = validateProject(JSON.parse(readFileSync(f, 'utf8')));
  const track = p.tracks[0];
  const clip = track?.clips?.[0];
  if (!track || !clip) continue;
  const entry = {};
  const cases = [
    ['resize', () => resizeClip(p, track.id, clip.id, Math.max(0.25, clip.length - 1))],
    ['move', () => moveClip(p, track.id, clip.id, clip.start + 0.5)],
    ['split', () => splitClip(p, track.id, clip.id, clip.start + Math.min(2, clip.length / 2))],
    ['repeat', () => repeatClip(p, track.id, clip.id, { count: 2 })],
    ['update', () => updateClip(p, track.id, clip.id, { start: clip.start, length: clip.length, name: '改名', muted: true })],
    ['remove', () => removeClip(p, track.id, clip.id)],
    ['capture', () => capturePattern(p, track.id, clip.id, { name: '测试乐句', linkSource: true })],
  ];
  for (const [name, fn] of cases) {
    try {
      const result = fn();
      const project = result.project ?? result;
      entry[name] = checksum(JSON.stringify(stripIds(project)));
    } catch (e) {
      entry[name] = 'error:' + e.message;
    }
  }
  if (p.patterns?.length) {
    const patternId = p.patterns[0].id;
    const linked = p.tracks.flatMap(t => t.clips).find(c => c.patternId === patternId);
    if (linked) {
      const trackId = p.tracks.find(t => t.clips.includes(linked)).id;
      try {
        entry.detach = checksum(JSON.stringify(stripIds(detachPatternClip(p, trackId, linked.id))));
      } catch (e) { entry.detach = 'error:' + e.message; }
      try {
        entry.updatePattern = checksum(JSON.stringify(stripIds(updatePattern(p, patternId, { name: '改名乐句' }).project)));
      } catch (e) { entry.updatePattern = 'error:' + e.message; }
    }
    try {
      const place = placePattern(p, patternId, p.tracks[0].id, p.bars * 4, { linked: true, extend: true });
      entry.place = checksum(JSON.stringify(stripIds(place.project)));
    } catch (e) { entry.place = 'error:' + e.message; }
    try {
      entry.removePattern = checksum(JSON.stringify(stripIds(removePattern(p, patternId, { detach: true }))));
    } catch (e) { entry.removePattern = 'error:' + e.message; }
  }
  ops[rel] = entry;
}
const outDir = join(repoRoot, 'shared/canonical');
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'm4-logic.json'), JSON.stringify({ version: 1, ops }, null, 1) + '\n');
const total = Object.values(ops).reduce((n, e) => n + Object.keys(e).length, 0);
console.log(`m4-logic.json: ${Object.keys(ops).length} fixtures, ${total} op digests`);
