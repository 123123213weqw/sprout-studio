// 设计令牌对比度 lint：解析 dist CSS 的 :root 令牌，校验关键配对的 WCAG 对比度。
// 用法：node scripts/design-lint.mjs（由 npm run check 调用，不达标即失败）
import { readFileSync } from 'node:fs';

const files = ['dist/styles.css', 'dist/workspace.css'];

function rootTokens(text) {
  const tokens = {};
  const rootBlocks = text.matchAll(/:root\s*\{([^}]*)\}/g);
  for (const [, body] of rootBlocks)
    for (const m of body.matchAll(/--([a-z0-9-]+)\s*:\s*([^;]+)/g)) tokens[m[1]] = m[2].trim();
  return tokens;
}

function channel(hex) {
  return [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255);
}
function luminance(hex) {
  const [r, g, b] = channel(hex).map(c => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function contrast(a, b) {
  const [l1, l2] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
}

// workspace.css 后加载，同名令牌覆盖 styles.css
const effective = {};
for (const f of files) Object.assign(effective, rootTokens(readFileSync(f, 'utf8')));
const hex = name => {
  const v = effective[name.replace(/^--/, '')] ?? '';
  return /^#[0-9a-fA-F]{6}$/.test(v) ? v.toLowerCase() : null;
};

const checks = [];
const on = (fg, bg, min, why) => checks.push({ fg, bg, min, why });
// 文本 ≥4.5:1（小字号令牌按 6:1 要求）
for (const t of ['--text', '--muted', '--warn-text']) for (const s of ['--bg', '--bg-bar', '--bg-panel-2', '--bg-tile', '--chip-bg']) on(t, s, 4.5, '正文/标签');
// 小字两级标准：主要表面（状态栏/面板标题区）6:1 补偿抗锯齿；组件内嵌标签 4.5:1（WCAG AA）
for (const t of ['--subtle', '--hint-text']) {
  for (const s of ['--bg', '--bg-bar', '--bg-panel-2']) on(t, s, 6.0, '9-12px 小字·主表面');
  for (const s of ['--bg-tile', '--chip-bg']) on(t, s, 4.5, '组件内小标签');
}
for (const s of ['--bg', '--bg-bar', '--bg-panel-2']) on('--accent', s, 3.0, '强调色文字/图标');
for (const s of ['--bg', '--panel', '--raised']) on('--border', s, 1.6, '面板边界');
on('--on-accent', '--accent', 4.5, '强调按钮上的文字');
on('--on-accent', '--accent-hover', 4.5, '强调按钮悬浮文字');

let fail = 0;
for (const c of checks) {
  const f = hex(c.fg), b = hex(c.bg);
  if (!f || !b) continue; // 非颜色令牌（尺寸等）跳过
  const r = contrast(f, b);
  const ok = r >= c.min;
  if (!ok) fail++;
  console.log(`${ok ? '✓' : '✗'} ${c.fg}(${f}) on ${c.bg}(${b}) = ${r.toFixed(2)}:1  最低 ${c.min}  [${c.why}]`);
}
console.log(fail ? `\n${fail} 项不达标` : '\n全部达标');
process.exit(fail ? 1 : 0);
