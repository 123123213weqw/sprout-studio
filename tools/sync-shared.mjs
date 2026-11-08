// shared/*.json → 各栈消费点。唯一被允许持有这份数据的地方:
//   native/Sources/SproutKit/Resources/(SwiftPM 资源,字节级拷贝)
//   dist/tables.js(Web 端消费点,待 Web 侧统一数据层时启用,当前不写)
// 改数据 = 改 shared/*.json → 跑本脚本 → 提交。CI 校验跑完本脚本 git diff 必须为空。
import { writeFileSync, readFileSync, mkdirSync, existsSync } from 'node:fs';

const repoRoot = new URL('..', import.meta.url).pathname;
const files = ['tables.json', 'samples.json'];
const targets = files.map(f => `${repoRoot}native/Sources/SproutKit/Resources/${f}`);
for (const target of targets) {
  const source = readFileSync(target.replace(/[^/]+$/, '') === '' ? '' : `${repoRoot}shared/${target.slice(target.lastIndexOf('/') + 1)}`);
  mkdirSync(target.slice(0, target.lastIndexOf('/')), { recursive: true });
  const unchanged = existsSync(target) && readFileSync(target).equals(source);
  writeFileSync(target, source);
  console.log(`${unchanged ? 'unchanged' : 'updated'}  ${target.slice(repoRoot.length)}`);
}
