# Sprout Studio 原生化迁移计划(Web/Electron → macOS 原生 Swift)

状态:v4(2026-11-11,M0–M3 全部落地;Web 栈已退役,原生为唯一实现,见 §0a)

## 0a. Web 栈退役(2026-11-11)

逻辑层 100% 对拍完成后,Web/Electron 版整栈移除:`dist/`、Node 服务(server/bridge/llm)、JS 测试、desktop/ 与 node CI。原"双栈互维护"收敛为**原生唯一 + 基准锁定**:`shared/canonical/`(11 个基准,~7400 项)与 `shared/*.json` 数据源继续是契约;格式演进时以基准为可执行规范(如需重新生成基准,可从退役前的 git 历史检出 dist 运行 tools/gen-m*-canonical.mjs)。采样许可在 `shared/sample-licenses/`。

## 0. 决策与目标

**决定**:新增 macOS 原生实现(SwiftUI + AVAudioEngine),与 Web 版**双栈互维护**——不冻结、不废弃 Web;两边共享同一份数据源与格式契约,任何一侧的演进都以契约测试保障另一侧。本地 Xcode 与 GitHub CI 并用;V100 保留用于可在 Linux 上跑的纯逻辑测试。

- 目标:功能对齐 v0.31 的原生 Mac 应用;`.sprout` / `.sprout-patterns` 双向完全兼容;WAV/MIDI 导出可用;可公证分发。
- 非目标:不做 iOS、不做跨平台;不重渲染采样(FluidR3 bake 好的 PCM 原样复用)。

**动机**:只发 mac-arm64,Electron 是纯负重(684MB 包、Chromium 内存、ad-hoc 签名);原生拿到 CoreMIDI/MusicSequence、离线渲染、系统菜单/快捷键/撤销/无障碍/公证。

## 1. 已核实的关键事实(迁移契约)

| 契约 | 内容 | 出处 |
| --- | --- | --- |
| `.sprout` 格式 | `JSON.stringify(project, null, 2)` 美化 JSON,无封装无签名 | `dist/app.js` `saveProject()` |
| 工程模型 | `{id,name,bpm,key,bars,style,swing,master,seed,tracks[],sections,patterns,ranges,controls…}`;track=`{id,instrument,kind,color,volume,pan,muted,solo,notes[],clips[]}`;note=`{id,pitch,start,duration,velocity}` | `dist/music.js` `validateProject` |
| 采样资产 | `SAMPLE_ASSETS`:`{id,file,root,maxVelocity,frames,sampleRate,channels,sha256,sourcePath,…}`;preset=`{name,instrument,gain,release,attack,program,assets[]}`;179 presets / 2259 WAV / 767MB | `dist/sample-assets.js`、`dist/sampler-core.js`、`release-media.json` |
| 采样语义 | root 区间映射、相邻力度层混合、确定性 take 轮换(传输启动/离线渲染重置)、160ms 交叉淡化延音循环、懒加载批 4、PCM 缓存 96MB / prepared 256MB LRU、活动根音钉住 | `SAMPLED-INSTRUMENTS.md`、`dist/sample-library.js` |
| 原始合成 | Web Audio 振荡器 + 确定性 LCG 噪声(种子 1729,×16807 mod 2³¹−1)、固定包络(attack/hold×0.82/release) | `dist/audio.js` |
| LLM 协议 | DeepSeek `chat/completions`,JSON mode;入参 prompt+工程上下文+显式目标轨道/节拍窗口;出参 `[pitch,start,duration,velocity]` 元组;服务端全量校验(目标 ID 精确、≤512 音符、跨窗口/重复/截断一律拒绝)后才合并;候选先暂存不自动应用 | `DEEPSEEK.md`、`server.mjs`、`dist/service.js` |
| 服务端职责 | 静态文件 + 本机 LLM 代理 + V100 SSH 隧道密钥托管。**原生 App 后此层消失**:key 进 Keychain,URLStream 直连 | `server.mjs`、`bridge.mjs` |
| 测试资产 | 393+ 项自动化;`examples/` 含渲染 WAV fixture、validation JSON、deepseek-live 真模型产物 | `tests/`、`examples/` |
| 代码体量 | 核心 dist JS 仅 **~2,679 行**(65 个小文件);577KB 大头是资产数据 | `git ls-tree` 统计 |

## 2. 目标架构(SwiftPM 多模块)

```
native/
├── SproutKit      纯 Swift,无 Apple 依赖 → Linux/V100 可 swift test
├── SproutMIDI     纯 Swift(自研解析,对齐 dist/midi.js 语义)→ Linux 可测
├── SproutLLM      纯 Swift(协议/校验规则)+ URLSession 客户端 → 规则部分 Linux 可测
├── SproutAudio    AVAudioEngine 采样/合成/调度/离线渲染(仅 Apple)
├── SproutStudio   SwiftUI 应用壳 + 编辑器视图(仅 Apple)
└── MediaSync      采样装载/SHA-256 校验(对齐 restore-release-media.py 语义)
```

**模块归属映射**(JS → Swift,按 dist 文件):

| Swift 模块 | 吸收的 JS |
| --- | --- |
| SproutKit | `music.js` `clips.js` `limits.js` `ranges.js` `sections-core.js` `patterns-core.js` `composition.js` `phrase-transform.js` `pattern-transform.js` `pattern-transfer.js` `pattern-arrange.js` `sections.js` `section-transition.js` `performance.js` `transport.js`(计划/纯计算部分)`storage.js`(限额/校验语义,存储换 SwiftData/文件)`project-starts.js` `sound.js`(参数规范化) |
| SproutMIDI | `midi.js`(GM 提示、鼓件映射、往返校验) |
| SproutLLM | `service.js` `model-receipt.js` + 根目录 `llm.mjs` `deepseek.mjs` `llm-config.mjs` |
| SproutAudio | `audio.js` `sampler-core.js` `sample-library.js` `sampler-edit.js` + `transport.js`(调度部分) |
| SproutStudio | `app.js` `editor.js` `workspace.js` 及全部 `*-ui.js`(界面重建,不逐行移植) |
| MediaSync | `sample-assets.js` `sample-presets-extra.js` `sound-catalog.js` `sound-bank.js`(转静态数据)+ `scripts/restore-release-media.py` 语义 |

资产数据(`SAMPLE_ASSETS`、presets、sound catalog)建议构建期由脚本从 JS 生成 JSON/`.swift` 常量,**单一事实来源仍是现有 JS**,避免双份漂移。

## 3. 兼容与验证策略

1. **`.sprout` 双向对拍**:SproutKit 解析 `examples/`(含 `deepseek-live/`)全部 `.sprout`,normalize 后重新序列化,与 JS 版输出比对。注意:pretty JSON 的 key 顺序必须一致 → Swift 侧手写 `encode(to:)` 保持字段序,或比对语义等价(解析→字段集/值全等)而非字节。
2. **音频对拍目标**:不强求逐样本一致(渲染路径不同);出口判据 = 事件表一致(音符→采样选择/take 序列完全相同,这部分逻辑在 SproutKit 里做成纯函数)+ 输出非静音、不削波 + 人工 A/B 听感。`examples/` 现有 WAV fixture 作为回归基线。
3. **确定性优先**:LCG 噪声、`rng(seed)`(music.js)、take 轮换序列全部是纯算法,Swift 逐位复刻,单元测试直接对拍 JS 输出(跑一次 JS 生成期望值存 fixture)。
4. **分层 CI**:SproutKit/SproutMIDI/SproutLLM 规则在 Linux runner(顺带 V100)跑 `swift test`;音频/UI 在 macOS runner 跑 `xcodebuild test`。
5. 每阶段出口判据见 §5。

## 4. 音频引擎设计要点

- 主图:`AVAudioEngine` → 每轨 channel(volume/pan/mute/solo)→ master。对齐 `updateMix` 语义。
- **SampleVoice**:root 区间选择 → 力度层线性混合 → 确定性 take 轮换 → 160ms 交叉淡化循环。变调对齐 Web `playbackRate` 线性语义(预重采样或 `AVAudioUnitTimePitch`,以听感对拍定案)。样本懒加载批 4、LRU 预算 96MB/256MB、活动根音钉住——预算数字照搬,行为可测。
- **SynthVoice**:LCG 噪声逐位复刻;振荡器/包络参数(attack/hold×0.82/release、kick 145→43Hz 指数下滑等)照搬 `audio.js`。
- 调度:`transport.js` 的 lookahead 计划器移植,beat↔time 换算、swing、range/loop、stop(true) 立即切断语义保持。
- **WAV 导出**:`AVAudioEngine.manualRendering` 离线渲染,**复用同一 voice 路径**(与现版"WAV 导出用同一采样器"承诺一致)。
- 采样数据不进 git、不进 App bundle:MediaSync 首启引导选择已解压的 release 目录(或 zip 导入),按 `release-media.json` 逐文件 SHA-256 校验。

## 5. 阶段划分与出口判据

| 阶段 | 内容 | 出口判据 | 预估 |
| --- | --- | --- | --- |
| **M0 基建** | `native/` + SwiftPM + CI 骨架;SproutKit 数据模型、validate/normalize、`.sprout` 读写;资产生成脚本 | examples 全部 `.sprout` 解析+规范化对拍通过;Linux CI 绿 | ~1 周 |
| **M1 播放器** | SproutAudio(采样+合成+调度+离线渲染)、SproutMIDI 导入导出;UI:打开工程、走拍、混音、工程库(12 工程/24 版本/归档)、WAV/MIDI 导出 | 打开 v0.31 现有工程日常听歌;WAV 非静音不削波;MIDI 往返校验;A/B 听感可接受 | 2–3 周 |
| **M2 编辑器** | piano roll(Canvas)、鼓格、clip/段落/时间线、撤销重做、乐句与节奏/音高变换、共享 Pattern 库、`.sprout-patterns` | 编辑器全流程可用;变换结果与 JS 版同输入同输出(纯函数对拍) | 4–6 周 |
| **M3 助手与分发** | SproutLLM + DeepSeek 面板、候选架三版对比、模型回执;Developer ID 签名 + 公证 + DMG;采样按需装载引导 | 真模型一次受控生成(`--live` 语义);公证通过;可对外发 | 2–3 周 |

总量级:**~2–3 个月**达到对齐 v0.31 的可分发原生版。核心逻辑仅 2.7K 行 JS 是有利条件;主要不确定性在 M2 编辑器 UI 与 M1 听感对齐。

## 6. 构建与 CI

- **本地**:Xcode 16+,`xcodebuild`/`swift build`;不违反"远程验证"精神的底线是:音频/UI 必须本地 Mac 编译(macOS 独占),纯逻辑模块照旧可远程/V100 验证。媒体继续走 restore 脚本,git 不进 WAV。
- **GitHub Actions**(公开仓库 macOS runner 免费):
  - `linux`:SproutKit/SproutMIDI/SproutLLM `swift test`
  - `macos`:`xcodebuild test` + `xcodebuild build`(M3 起加签名/公证,secrets:Developer ID 证书 + App Store Connect API key,`notarytool`)
  - tag → 构建 DMG + SHA256SUMS,复用现有 release 习惯
- **V100**:保留两用——Linux `swift test` 的额外跑批 + (可选)远端密钥的 DeepSeek 代理。默认方案改为 Keychain 直连,V100 桥降级为可选项。

## 7. 风险与对策

| 风险 | 对策 |
| --- | --- |
| 采样音色不一致(力度混合/循环/take) | 采样选择与参数计算全部做成 SproutKit 纯函数,JS/Swift 双跑对拍;听感问题早暴露(M1 即 A/B) |
| pretty JSON 兼容 | 手写有序编码;`validateProject` 语义 1:1 移植 |
| piano roll/时间线工作量 | M2 独立阶段;先窄后宽(单轨编辑→多轨→段落) |
| 双栈期功能漂移 | Web 冻结声明写进 README |
| 767MB 资源体验 | bundle 不带采样;首启导入+校验,进度明确;磁盘不足显式失败 |
| 语义遗漏(几百条防御性校验) | 迁移按模块做 checklist:每个 JS 文件的导出函数在 Swift 侧逐个打勾或明确弃用 |

## 8. UI 组件复用映射(尽量少自设计)

**白捡(零设计)**:`NavigationSplitView`+`Inspector`(三栏工作台)、`.toolbar`+SF Symbols(走拍控制)、`Table`/`List(selection:)`+`.searchable`+`.contextMenu`(工程库/版本/音色浏览器)、`Settings`+`Form`(LLM 配置)、`Slider`/`Toggle`(混音)、`.sheet`/`.alert`/`.confirmationDialog`(弹窗)、`FileImporter`/`FileExporter`(sprout/MIDI/WAV,注册 UTType 可双击打开)、`UndoManager`(整块替换手写撤销栈 UI)、`Commands`(菜单+快捷键)、`.draggable`/`.dropDestination`(Pattern 拖拽)、暗色模式/无障碍/材质免费。CSS design tokens 层(v0.30)整体作废,系统控件自带 HIG。

**必须 Canvas 自绘(仅三块)**:piano roll、时间线/编排区(clip 拖拽 `DragGesture`,画法参照现有 `clipSVG()`)、鼓格;候选对比为三个小 Canvas。三者的坐标换算/吸附/命中逻辑 JS 里已是纯函数,Swift 侧为翻译。

**不可复用**:`AVAudioUnitSampler` 无法表达力度层混合/take 轮换/交叉淡化循环,采样引擎仍自研。**可复用**:AudioToolbox `MusicSequence` 做 SMF 解析/写盘,GM 提示/鼓件映射语义(`midi.js`)套用。

**存储**:工程库不用 SwiftData 硬套——`.sprout` 本就是 JSON,建议 `Application Support/sprout-vault/` 文件库 + 版本快照文件,限额/校验语义照搬 `storage.js`,比 IndexedDB 语义更直白。

## 9. 互维护契约(已落地,M0)

**单一数据源**:`shared/tables.json`(乐器/调性/风格/音色默认值/字段规格/控制参数/限额/179 preset manifest)。
- 改数据 = 改 `shared/tables.json` → `node tools/sync-shared.mjs`(同步到 `native/Sources/SproutKit/Resources/tables.json`)→ 提交;CI 校验同步后 `git diff` 为空。
- `tools/extract-tables.mjs` 是一次性提取器(留档),Web 侧 dist 内联字面量暂保持原样,由 `tests/tables-drift.test.mjs` 锁死与 JSON 的一致性;后续 Web 数据层统一时改为直接消费。

**可执行格式规范**:`shared/canonical/`(98 个 JS `validateProject`/`normalizePatterns` 规范输出,提交为测试资产)。
- Swift 侧:`swift test`(native/)对拍全部 fixture,字节级一致 + 校验幂等。
- JS 侧:`npm test` 原有 702 项;两侧任何语义改动都必须让对拍保持绿色,或显式更新 canonical(视为格式演进,须同步升版本)。

**错误文案是 API**:所有中文报错字符串锁定在两侧测试中,不许顺手润色。

**M0 实绩**(2026-11-08):98/98 字节级一致;`sproutkit-cli` 可命令行校验/对拍;Swift 侧零硬编码数据表。

**M1 纯逻辑实绩**(2026-11-08):`shared/samples.json`(2259 资产 + 179 完整 preset,唯一采样映射源);SproutKit 新增 Transport(swungBeat/performanceBeat/playbackPlan/timelineEvents)、SamplerLogic(pickSample/sampleLayers/sampleVoicePlan)、SoundPlan(envelopePlan + 合成层/峰值/滤波常量)。对拍摘要(`shared/canonical/m1-logic.json`,由 `tools/gen-m1-canonical.mjs` 生成):96 工程播放计划 + 179 preset 采样选择 + 179 发声计划全部一致;JS 防漂移测试同步覆盖 samples.json。

**M1 音频与 MIDI 实绩**(2026-11-08):MIDI 编解码(`encodeMIDI`/`decodeMIDI`)字节级与摘要级对拍 96/96、89/89;期间发现并修复 `toFixed` 语义差异(JS 对精确十进制展开舍入,乘法近似在 .5 边界翻转)——`jsToFixedValue` 用整数位分解实现精确版,全局生效。新增 `SproutAudio` target:纯 Swift 离线渲染器(Biquad/等功率声像/LCG 噪声/软拐压缩器/延迟回声、WAV 读写、SHA-256、采样库装载校验),`renderWAV` 对应 dist/audio.js 完整图结构;修一处 loop 单位 bug(loopStart/loopEnd 为秒,回绕按帧)。实测:合成工程、采样工程(小提琴/吉他/单簧管/EDM,媒体取自 Electron asar 解包 + SHA-256 校验)全部非静音不削波,release 模式渲染 32 秒立体声 <1 秒。CLI:`sproutkit-cli render/mididump/check/validate`。CI:新增 `native.yml`(Linux swift test + sync 防漂移)。剩余:M2 编辑器 UI、Player 壳、实时播放引擎(AVAudioEngine)。

## 11. 实绩总账(2026-11-11 全部缺口闭环)

| # | 缺口 | 状态 |
|---|---|---|
| 1 | 轨道管理 + 工程属性(移调/长度,96+96 对拍) | ✓ #8 |
| 2 | 音源浏览器(179 preset)+ 音色编辑(soundPreset 24/24 对拍) | ✓ #9 |
| 3 | 离线灵感引擎(generateProject 288/28、提示词引擎 30/30 对拍) | ✓ #10 #12 |
| 4 | 时间线音块 + Pattern 库(904/904 对拍,.sprout-patterns 互通) | ✓ #11 |
| 5 | DeepSeek 助手 + 候选架(协议校验移植,Keychain,直连) | ✓ #12 |
| 6 | App 打包(UTType/ad-hoc 签名/DMG,可切 Developer ID+公证)+ macOS CI | ✓ #13 |
| 7 | 卷帘多选(⌘点选/⌘A/组拖拽/批量力度/批量删除) | ✓ #13 |

对拍体系:M0 98/98 字节级;M1 transport/采样/发声/MIDI;M2 移调/长度;M3 生成;M4 音块/Pattern;M5 提示词——全部 CI 锁定。测试 28/28(Linux)+ 本地 macOS。公证需仓库主人的 Developer ID 证书(见 tools/package-app.sh 头注)。

## 12. 待定项(默认值可改)

- 最低系统:**macOS 14+**(SwiftUI Observation/新 API 自由度)
- 应用名沿用 Sprout Studio,bundle id 另定(如 `com.sproutstudio.mac`)
- Web 版长期去留:默认冻结,迁移完成后归档
- 采样变调实现(预重采样 vs TimePitch):M1 听感对拍后定
