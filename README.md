# Sprout Studio — GitHub distribution

Beginner-friendly local music studio with 179 playable sounds, MIDI/WAV export and an optional DeepSeek composition assistant.

## Download and run

Download **seed-studio-v0.29.0.zip** from the [v0.29.0 release](https://github.com/123123213weqw/sprout-studio/releases/tag/v0.29.0), rather than GitHub's automatically generated source ZIP. It includes all 2,259 instrument samples, rendered examples, source code and third-party notices.

Extract it, open a terminal inside `seed-studio`, and run:

```sh
npm start
```

Requires Node.js 22 or newer. No `npm install`, login or API key is needed for local editing, instruments or offline composition. Open the local address printed by the server. Audio only starts after an explicit interaction.

## Developer clone

Git history intentionally excludes WAV files to keep clones lightweight. With GitHub CLI authenticated to this private repository:

```sh
gh repo clone 123123213weqw/sprout-studio
cd sprout-studio
gh release download v0.29.0 --pattern 'seed-studio-v0.29.0.zip' --dir ../sprout-downloads
python3 scripts/restore-release-media.py ../sprout-downloads/seed-studio-v0.29.0.zip
npm test
npm run check
npm start
```

Python 3 is only needed for the one-time media restoration helper. It verifies every expected WAV against the committed size and SHA-256, refuses modified local media and never extracts arbitrary archive paths. Test fixtures that inspect audio require this restoration step. The complete release ZIP can also be run directly without Python.

API keys, local environment files, hosting identifiers and the old local Git history are excluded. The optional V100 bridge requires your own SSH host configuration and credentials; no credentials are bundled. Original project code has no newly assigned open-source license; bundled third-party assets retain their individual notices in `dist/samples/licenses` and the sound-library tools.

The repository is a clean v0.29.0 snapshot. The original local working repository and its history are preserved separately.

---

# 芽音 · Sprout Studio

一个面向新手的浏览器编曲工作站。参考经典 DAW 的暗色轨道、钢琴卷帘和混音台工作流，采用原创界面、内置合成音源和随包采样乐器。不是 FL Studio 的全功能替代品，也不读取 `.flp` 文件。

## 0.29 — 179 playable sounds across acoustic and EDM families

The library now contains **179 distinct playable presets**, not just 179 audio files: 15 detailed recording presets, all 128 bank-zero FluidR3 General MIDI programs and 36 original EDM patches. Coverage includes pianos/electric keys, organs, mallets, guitars, basses, strings, choirs/ooh voices, brass, reeds, winds, synth leads/pads, world instruments, tuned percussion, effects and electronic drums. These are not 179 newly recorded acoustic instrument families; soundbank and synthesized sources are labeled separately.

**Add instrument** now has literal text search, collection/family filters and 24 featured results at a time, with explicit Show more. Source changes retain compatible native category groups. No auto-audition, replacement of existing songs, account or new runtime plugin. The full local recording library is **2,259 WAV files / 767.07 MB**; files load per source rather than downloading the whole library at startup. Native playback preparation uses only note roots needed by the project or preview. Raw PCM and prepared-buffer caches have separate 96 MB and 256 MB ceilings; idle prepared buffers can be evicted without removing active project roots.

**688 tests pass.** Every preset has an actual non-silent, unclipped offline audition. The authored [EDM and acoustic/choir sketches](examples/sound-library-v29/README.md) are separate from model output. Two older WAVs re-rendered byte-exactly, and all 264 old PCM assets/records remain unchanged. No new paid model calls or Sites deployment. This snapshot is backed up on GitHub with media in a separate release asset. These are signal/behavior checks; current browser visual and subjective listening QA remain unperformed.

## 0.28 — more acoustic recordings, fewer identical retriggers

Added **microphone-recorded archtop guitar, solo violin and clarinet**, reusing the existing Add instrument / Source controls. Guitar has 16 roots, four recorded playing intensities and two real alternate takes per intensity; violin has two recorded dynamics and clarinet has three. Explicit previews are long enough to reveal their natural attacks. There are now **15 sampled presets and 264 WAV files**, including all 84 unchanged legacy recordings.

The bulk recording action now fills synth tracks only, preserving any sampled voice already chosen. Nothing automatically changes your song or plays sound. Decoded-cache eviction keeps the 96 MB raw PCM ceiling; prepared audio buffers have a separate 256 MB per-context ceiling. No new runtime dependencies are required.

**655 tests pass.** Eight actual offline exports are non-silent and unclipped, including a 13.207-second [authored acoustic trio](examples/acoustic-v28/README.md), isolated new instruments, alternate takes and held notes. Source-only and explicit natural-performance copies of the earlier 80-note DeepSeek result are labeled separately; the raw model output remains untouched. No new model calls, publishing or Git push. Objective audio checks do not establish subjective realism; browser visual/listening QA remains unverified. See [recorded instrument details](SAMPLED-INSTRUMENTS.md).

## 0.27 — real-model regression batch

Six additional V4.1 Flash calls completed on V100, using 23,441 reported tokens with no automatic retries. **6/6 responses were valid and preserved scope, settings and sampled voices; 5/6 met all measured case instructions.** The ambient case left kick/snare silent despite requesting all eight roles, and that miss is retained rather than silently repaired.

The new unedited 80-note arrangement satisfies all four piano/bass anchors and the 32 requested hi-hat onsets. Tests also cover an exact flute clip, half-time drums, a chorus with shared Patterns, held sampled notes and conflicting scope requests. Actual MIDI/WAV/stems and findings are in [the batch evidence](examples/deepseek-batch-v27/README.md). **630 automated tests pass**; replays make no paid calls. This is structural/instruction/audio-signal verification, not a subjective music-quality or browser-UI verdict.

## 0.26.1 — DeepSeek V4.1 Flash pinned

The V100 service is connected and pinned to **DeepSeek V4.1 Flash**, whose API ID is `deepseek-flash` ([official model table](https://api-docs.deepseek.com/quick_start/pricing/)). The three existing real tests already used that ID. Other model overrides are now rejected before generation; no extra generation calls were needed for this patch. **612 tests pass.** The key stays on V100 and the UI is unchanged.

## 0.26 — real DeepSeek tested on V100

**Three authenticated calls completed** using `deepseek-flash` from V100, with the key kept there. The two full test arrangements produced 62 and 83 notes across all eight sampled instrument roles. A flute-only edit through the local API/SSH bridge preserved the other seven tracks. Reported usage: 7,310 tokens total, no automatic retries.

Use `npm run start:v100` or open **Start with V100.command** to start the connected local app. Then choose the model service in Assistant settings. Startup does not compose or play; generation still produces a candidate that needs explicit Apply. Browser addresses remain local and no key needs to be pasted into the web UI. `npm start` remains the standalone/offline/local-key option.

**609 automated tests pass.** Actual MIDI, WAV, stems, sanitized receipts and instruction checks are in [the live-test folder](examples/deepseek-live/README.md). All eight stems contain nonzero audio and are unclipped. The second prompt fixed the hats but still missed one requested bass root, so this is **not** claimed as perfect instruction-following or a listening-quality verdict. A separately labeled reviewed demo fixes that one bass note with the existing editor operation and verifies exact undo; the raw model results remain unchanged. The visual design pass is still unverified; no new interface look is claimed.

## 0.25 — bounded DeepSeek integration (local only)

The local server now has a DeepSeek-specific compact MIDI-note adapter, strict scope/sample preservation, fixed output limits and sanitized successful-response receipts. The app still stages a candidate before applying anything. **Historical v0.25 state:** this was implemented before the V100 credentials were located; the v0.26 results above supersede that blocker. No UI redesign is claimed; browser visual QA remains blocked.

Set `LLM_API_KEY` in the local `.env` file, restart `npm start`, then explicitly generate through the assistant service or run `npm run test:deepseek -- --live` for one isolated four-bar/eight-instrument test. Browser protocol addresses stay `/api/compose` and `/api/llm/status`; do not put a vendor API key in the web UI.

**593 automated tests pass**, including 23 new DeepSeek/receipt tests using synthetic transports. Synthetic tests are not evidence of a real model call or musical quality. See [DeepSeek setup and limitations](DEEPSEEK.md) and [product decisions and pending design pass](DESIGN-DECISIONS.md).

## 先用起来

需要 Node.js 22 或更高版本。没有第三方运行依赖，不需要 `npm install`。

1. 在本目录执行 `npm start`。
2. 打开终端显示的 `http://127.0.0.1:4173/`。
3. 点击播放或音符可发声；默认不会自动播放，不需要登录。
4. 需要安静时打开 `http://127.0.0.1:4173/?silent=1`，或点击顶部“声音开 / 静音”。静音不影响编辑与离线文件导出。

macOS 也可以双击 `启动芽音.command`。脚本只启动本机服务器，不安装依赖或要求登录。**页面从不自动播放。** 当前启动链接不再强制静音；点击顶部“声音开 / 静音”可切换。

## 0.24 本地版八类真实音色

现有八类音源均有真实录音选择，原合成器与 0.23 经典采样保持可用。现在有 **12 个采样预设、84 个 WAV、约 35.08 MB 素材**：

- 钢琴：新增 14 根音双力度细分采样；原 8 根音经典版本不变。
- 贝斯：12 根音低音提琴拨奏，不是电贝斯；旋律：10 根音长笛。
- 铺底：13 根音大提琴组；拨弦：12 根音竖琴，不是吉他。
- 鼓组：架子鼓底鼓、双力度军鼓、真正闭合踩镲；保留原管弦鼓与短镲。

**＋ 添加乐器 → 整首换真实音色 · 先预览** 可以加载、校验、备份后一次替换现有各轨；不写音符、不改混音、可一次撤销。已经使用推荐采样的轨道保留自己的参数。单轨仍可点 **来源** 切换。新建乐器只加入空轨，不自动播放。

长笛与大提琴使用 120 ms 交叉淡化延音循环，长音不再在 6 秒素材尾部直接停止。其他音源保持自然衰减。新素材先以浮点处理和平衡各根音峰值，再转 PCM16，避免过早量化弱录音；双力度的相对音量保留。音高中心来自原 SFZ 的数字映射，避免不同库的八度命名差异。

**570 项测试通过**（新增 18 项核心与 6 项实际下载回归），桌面、手机弹窗与固定确认区均已验证。八轨演示保留旧 816 音符和四引用，另加 3 个竖琴音符；实际 MIDI 819 音符。区段 WAV 24.2456 秒、峰值 0.32339、削波 0。独立长音验收在第 7–9 秒仍有音频，超过原录音长度；试听 / 播放和离线导出不修改音乐。

素材来自 [VSCO 2 CE](https://github.com/sgossner/VSCO-2-CE) 与 [Sonic Pi 的 CC0 鼓素材集合](https://github.com/samblenny/web-midi-drumkit/blob/main/LICENSES/LICENSE_SAMPLES.md)。许可、来源、原始及处理后校验码随包保存。此版只更新本地，没有发布在线站、调用真实模型，也不代表完整专业音源或人工听感验收。

操作与边界见 [SAMPLED-INSTRUMENTS.md](SAMPLED-INSTRUMENTS.md)，实际证据见 `examples/validation-v24.json`。

## 0.23 本地版采样乐器

- **＋ 添加乐器 → 采样乐器**：立式钢琴、管弦底鼓、军鼓和短镲，加入空轨道，不自动写音符或播放。
- 已有钢琴 / 鼓轨可以点击编辑器的**来源**，加载、校验、备份后只替换此轨的发声方式。原音符、共享关系和合成参数保持；可以切回合成或一次撤销。
- 随包包含 21 个真实录音 WAV，共约 8.22 MB。钢琴 8 个采样音区、两档录音平滑混合；鼓两档录音，短镲一档。素材来自 [VSCO 2 Community Edition](https://github.com/sgossner/VSCO-2-CE)，CC0，完整许可和原说明随包保存。
- 实时播放与 WAV 导出使用同一采样调度。MIDI 只保存音符和钢琴的通用音色提示，不携带这些录音；`.sprout` 保存内置采样编号，需 0.23 或以上的同一素材包正确还原。
- 短镲是击镲录音经闸门缩短，用在踩镲声部，**不是真实踩镲录音**；没有踏板共鸣、延音循环、完整 SFZ、VST 或任意音频导入。
- **546 项测试通过**，新增 33 项采样 / 容量 / 加载 / 调度检查与 6 项实际文件回归。实际演示保留 816 音符 / 4 引用；采样试听创建两层 AudioBufferSource，区段 WAV 24.7456 秒、峰值 0.31354、削波 0。人工听感仍需试听评价。

说明见 [SAMPLED-INSTRUMENTS.md](SAMPLED-INSTRUMENTS.md)，证据见 `examples/validation-v23.json`。此版只更新本地源码与启动服务，没有重新发布在线站。

## 0.22 本地版：让界面像工作台

- 本轮按用户选择更新**本地版**，不同步发布在线站；浏览器打开 `http://127.0.0.1:4173/`，不要直接双击 HTML。
- 收敛为低饱和深灰界面，减少亮色、圆角、装饰图标和助手大标题。轨道名称 / 音源标签仍保留，显示配色不改工程数据。
- 默认折叠编排、音块与音符的低频工具；功能仍可展开使用。「专注模式」隐藏侧栏，视图状态独立保存并能刷新恢复，不进入音乐历史。
- 本轮默认“声音开”，用户已取消原先静音限制；没有自动播放。声音开关同时更新 `silent` 链接参数，双击启动脚本也不再提供强制静音地址。
- 桌面与两种手机断点实际验证；批量与复制 / 粘贴、共享变换、专注切换、候选审核和取消均可操作。实际工程与原稿逐字节相同，实际 MIDI 全部 816 音符保持。
- **507 项测试通过**（新增 15 视图 / UI 回归 + 2 实际下载回归）。
- 包含已实现的 0.21 共享乐句变换。真实模型仍需要用户提供配置；本轮没有调用外部模型，没有人工听感或全面无障碍验收。

说明见 [WORKSPACE-UI.md](WORKSPACE-UI.md)，验证见 `examples/validation-v22.json`。

## 0.21 本地功能：共享乐句变换

- 对库中源乐句做倍速、倒序、移调、调内吸附与微偏移处理；明确备份后同步**全部**关联实例。只想改一个块，请使用普通“乐句变换”。
- 全实例碰撞 / 边界 / 保存预算预检，不局部应用、不挤走其他块；保留 ID、链接、起点、静音和其他音乐。明确勾选才延长到留白，最多 64 小节；一次撤销。
- 实际四引用 / 八引用、手机倒序、尾部延长、旧候选拒绝、MIDI / 离线 WAV 与原稿完整恢复均已有证据，历史检查 490 项通过。

说明见 [PATTERN-TRANSFORMS.md](PATTERN-TRANSFORMS.md)。这是相对音符编辑，不是音频反放或 LLM 生成。

## 0.20 更新：让段落有一个鼓过门

- 选择已有歌曲段落 → **段尾过门**：三种新手鼓型，最后 1 / 2 小节、所选鼓轨、能量与力度种子；先看静态十六分网格和逐轨差异，再备份应用、一次撤销。不改变旋律，不自动播放或调用模型。
- 旧块静音 / M / S / 音色 / 混音 / 全局 / 源库保持，变化的共享鼓块局部独立；跨界长音保留窗外片段。空白默认拒绝，明确勾选才新建不静音的独立块；碎隙 / 边缘 / 所有容量预算整组拒绝。
- 实际第 23–24 小节三个鼓轨移除 25 / 新增 37，816 → 828 音符；手机只改军鼓与真实补块 / 两次撤销 / 旧草稿拒绝均验收。最终刷新后原稿下载逐字节恢复。
- **457 项测试通过**，新增 25 核心 + 7 实际下载回归。216 事件离线练习 WAV，24.7456 秒 / 峰值 0.49841 / RMS 0.08441 / 削波 0。安静模式无实时 AudioContext，未试听；这是规则过门，不是 LLM 智能衔接或专业音质验收。

操作、鼓型与保护边界见 [SECTION-TRANSITIONS.md](SECTION-TRANSITIONS.md)，实际验证见 `examples/validation-v20.json`。

## 0.19 更新：音色收藏与跨工程复用

- **◉ 音色 → 我的音色收藏**：给当前音色草稿取名并收藏，保存不应用、不改歌曲历史。另一条轨道 / 工程可“放入音色草稿”，再明确应用，一次撤销；默认只看适用音源，其他音源可查看但禁用。
- 自定义旋律参数跨五种旋律音源复用，native 沿用目标音源原生层；鼓仅同种鼓。**精确原始合成**用 null 表示删除自定义字段，限制原音源，不伪装成默认 ADSR。
- `.sprout-sounds` 草稿 / 单份 / 全库导出，本机全文件校验与分页选择导入；默认内容去重（含归档）、明确新副本、重名后缀、新 ID。没有音符 / 混音 / 实例 / 服务密钥，不是 VST 或采样文件。
- 独立事务收藏库跨本网站工程共用，最多 **32 项 / 256 KiB（含归档）**，改名、可逆归档 / 恢复、无自动淘汰；坏记录不自动重置，双页 CAS 拒绝覆盖并显式重新读取。草稿可直接下载，不依赖成功保存到库。
- 应用音色检查完整 **3 MB 工程保存预算**，旧窗口 / 非法参数 / 不兼容收藏拒绝。音乐、内部 IDs、音色以外的混音、四引用与源保持；不自动播放、调用模型或换乐器。
- 实际把一份电钢琴收藏用于 Pad 和另一首独立 House；Pad 工程 MIDI 与原音符字节相同。204 事件练习区段 WAV **25.1456 秒 / 峰值 0.47177 / RMS 0.08338 / 削波 0**，44100 Hz 双声道 16-bit，只离线生成。精确原始收藏实际移除自定义字段；最终原稿下载逐字节保持。
- **425 项测试通过**（新增 24 收藏 / 存储 / 兼容 / 保存预算 + 8 实际文件回归），实际坏文件 / 去重 / 重复 / 手机归档 / 分页 / 转义 / 双页冲突 / 过期拒绝，桌面与手机固定确认区可访问。quiet=true、playing=false、hardwareAudioInitialized=false，真实模型调用 0。

入门与格式见 [SOUND-COLLECTIONS.md](SOUND-COLLECTIONS.md)，实际证据见 `examples/validation-v19.json`。不以参数复用或 PCM 检查宣称音乐质量已验收；持续 goal 保持 active。

## 0.18 更新：真正独立的本机作品库

- **工程 → 我的工程 · 独立作品库**，桌面另有侧栏入口。新建空白 / 四种规则起点，8 / 16 / 32 小节；保存当前作品后打开独立新工程，不再用一个工作区轮流覆盖歌曲。
- 每首分开保存音乐、应急记录、有限撤销 / 重做、保存点与版本。**另存副本 / 导入为新工程**分配新工程标识、历史从零开始；内部音符 / 源 / 引用关系、音色、混音、段落与练习范围保持。
- 新作品数据与目录原子保存；验证目标并通过版本检查后才更新上次打开指针。配额 / 坏目录 / 坏目标不自动重置或删歌，保存失败不离开当前作品。旧 0.17 工作区原键和迁移兼容。
- **归档 / 恢复**可逆且保留数据，不释放配额。最多 12 个工程（含归档），没有自动淘汰；显示已提交工作区记录估计用量。候选架和编曲 / 服务 / 视图配置仍共用，候选应用检查原稿指纹。
- 不同作品的双页保存 / 应急 / 更新通知隔离；同作品仍保留冲突保护。每页 URL 的本机工作区标识让另一页选择后刷新不串换；地址不是云同步或作品分享。
- 实际静音 UI：空白改名 / 即时刷新 / 手机撤销重做、独立保存点、归档恢复、副本只静音一块、变换文件导入、House / Lo-fi 创建、旧新建窗口被真实候选应用拒绝、两类双页编辑、另一页选择后本页刷新。原七轨 / 816 音符音乐实际下载逐字节一致，副本实际 MIDI 为 800 音符。
- **393 项测试全部通过**（新增 29 工程库 + 6 工作区 / 地址 + 4 起点 + 8 实际文件回归），桌面 / 手机真实截图，quiet=true / playing=false / hardwareAudioInitialized=false，真实模型调用为 0。

入门与容量边界见 [PROJECT-LIBRARY.md](PROJECT-LIBRARY.md)，实际证据见 `examples/validation-v18.json`。作品仍只在当前浏览器 / 网站，重要音乐请下载文件；持续 goal 保持 active。

## 0.17 更新：立即刷新也保留有限撤销 / 重做

- 自动提交前的同步应急记录现在同时保存当前工程与有界历史，修复上轮实际发现的“音乐恢复了，撤销却丢了”。旧应急格式继续兼容，容量不足可降级到仅保存音乐，并明确说明历史未保存。
- 相同音乐不等于相同编辑时间线：编辑后撤销产生的新重做路径也能恢复；旧待完成保存不能仅凭音乐 checksum 删除更新的历史记录。恢复页只接管实际读到的那条应急记录，不覆盖另一页后来写入的内容。
- 顶部区分“应急已写 · 保存中”与事务确实完成的“已保存 · 版本”；悬停和手机版本窗口显示实际可恢复的撤销 / 重做数量。
- 真实静音 UI 连续验证改名 → 即刻刷新、相同音乐 / 新重做 → 刷新、重做 → 刷新、手机两次撤销 / 刷新；应急路径分别保留 6/0、6/1、7/0、5/2，正常再刷新仍为 5/2。三份实际下载回归验证只改预期名称或原稿字节完全一致。
- 全部 **346 项测试**通过（新增 30 应急 / 时间线回归 + 3 实际文件回归）；七轨 / 816 音符 / 一个源 / 四引用 / 练习 64…96 与五个候选保留，quiet=true、playing=false、hardwareAudioInitialized=false，无声音 / 真实模型调用。

详细操作与边界见 [SAVE-RECOVERY.md](SAVE-RECOVERY.md)，实际记录见 `examples/validation-v17.json`。这是可靠性阶段交付，不是 FL Studio 完整替代品或整个 goal 的完成。

## 0.16 更新：已有乐句的节奏与音高变换

- 选音块 → **乐句变换**，只改当前块。五个旋律新手草稿预设：紧凑一半、展开两倍、乐句倒序、高一个八度、贴合工程调性；鼓只有三个节奏预设且音高控件锁定。预设替换草稿，不自动应用、播放或调用模型。
- **节奏 ×½ / ×1 / ×2** 同时缩放相对起点、音符长度和块长，起点不移动，速度不变。紧凑释放的区域留空；展开碰到旧块（空 / 静音块也占位）整块拒绝。超出工程默认拒绝，明确勾选才空白延长到足够的 4/8/16/32/64 档位，不重复其他内容或标签。
- **倒序音符区间**按 `块长 − 相对起点 − 音符长度` 镜像，再套节奏倍数，不是音频倒放。不同长度的和弦音可能不再同起音。全局摇摆仍在新名义网格上应用，因此实际起音不保证严格镜像或倍乘。
- 半音移动 **−24…+24**；可再明确吸附到六种支持调性的最近调内音，等距离选较低音，音高限定 24…108。不会改工程调性，不分析源调性、不折返八度、不是和声重写。吸附可能合并音高，同音高重叠只提示，不自动删音符或缩短。
- 微偏移可随倍数与倒序方向变换 / 保留原拍数和方向 / 明确清除；超出 ±0.04 拍或块边界整块拒绝，不能悄悄钳制。清除不关闭全局摇摆。过短音符 / 块、音高越界、碰撞与完整 3 MB 保存预算也整组拒绝。
- 预览逐音音高、名义起点、长度、微偏移和实际起音差，十二条分页。保留音符数、IDs、力度、音色、M/S、混音、库与其他块；变化的共享实例仅让当前块独立化。应用前备份、一次撤销 / 重做，中性或旧工作区 / 旧窗口不能确认。手机页脚修复后完整位于窗口内；时间线加滚动避让，避免自动露出的音块被粘性标尺挡住。
- 实际静音工程：原 **32 小节 / 七轨 / 816 音符 / 四引用**，只对首份电钢琴十六音符做 ×½、倒序、+13、D 小调吸附（8 个吸附），块长 2 → 1 小节 / 引用 4 → 3；源库、其他六轨与其余音符精确保留。实际 MIDI 816 音符逐一核对，首小节全轨区段 WAV 43 音符、5.2107 秒 / 峰值 0.43762 / RMS 0.06916 / 削波 0，44100 Hz 双声道 16-bit，未播放。
- 另有真实 **六个底鼓音符倒序**与**末段八个旋律音符展开、32 → 64 小节明确留白延长**，均实际下载 / 一次撤销；旧变换窗口遇到真实规则候选应用后拒绝，revision 不增加；最终原稿实际下载逐字节一致，五个既有候选保留。

操作与算法边界见 [PHRASE-TRANSFORM.md](PHRASE-TRANSFORM.md)，实际记录见 `examples/validation-v16.json`。未以变换或 PCM 数值检查宣称音乐质量 / 真实 LLM 已验收；持续 goal 保持 active。

## 0.15 更新：一次编排多份，只管理选中的关联块

- **Pattern 库 → 放置到轨道**：默认仍为一份，可明确选择 **1–32 份**、首份小节与每份起点间隔（拍）。间隔等于乐句长度则首尾相接，大于长度则留空隙；预览全部起点、新增音符、共享数量和工程长度。优先沿用兼容的当前轨道，否则优先相同乐器；鼓仅同种鼓，旋律跨旋律乐器不自动移调。
- 默认 **共享关联**，以后库内共享编辑同步这些块。取消勾选则每份都是独立副本，单独编辑不改兄弟副本或源。普通复制仍是独立副本；这里没有生成变奏或调用模型。
- 空音块 / 静音块也占位置，任意一份碰撞、越界、容量或完整 3 MB 保存预算超限就 **整组拒绝**。只有明确勾选 **需要时空白延长工程** 才可延长到下一档，最多 64 小节，不重复其他轨道、标签或来源。整批作为一次编辑，可一次撤销。
- **选择管理关联块**：只列当前源的真实引用，默认全不选，八条一页、跨页保留选择。可静音 / 取消块静音 / 独立化 / 删除所选块。未选引用、普通复制、源库、轨道 M/S、音色、混音、段落、练习范围和全局参数保持。删除仅去掉所选块和内部音符，不 ripple、不删源、不缩短工程；独立化连现有音符 IDs 都保持。
- **查看位置**只选中并显示该块，不改音乐、播放位置或工程版本，不试听。管理操作先备份再一次应用，取消与旧工作区 / 旧窗口保护有效；无变化的静音草稿不能应用。独立化不会重启正在运行的虚拟走拍；静音 / 删除会正常刷新调度，但不自动开始播放。
- 手机端 **工程 → 撤销上一步 / 重做上一步** 不再依赖窄屏隐藏的顶部快捷键。390×844 的编排 / 管理表单可滚动、确认区完整可达；桌面检查为 1280×900。
- 实际静音示例：空白三源库批量放 **3 份电钢琴 + 4 份底鼓 + 3 份旋律**，8 → 16 小节、96 音符 / 10 引用；只静音中间电钢琴、独立化第一份、删除最后旋律后为 **88 存储音符 / 8 引用**，实际 MIDI 与区段 WAV 调度 **72 音符**。WAV 23.8256 秒、峰值 0.39731 / RMS 0.05195 / 削波 0，立体声 44100 Hz / 16-bit，只离线生成，未播放。
- 另有真实十份放置 / 手机一次撤销重做、两份独立副本只改第一份 16 音符力度、跨电钢琴 / 铺底四引用只静音一个铺底块，以及旧预览遇到实际离线候选应用后拒绝。测试后原 32 小节 / 7 轨 / 816 音符工程完整还原，五个既有候选保留。真实模型与付费调用仍为 0。

操作说明见 [PATTERN-ARRANGE.md](PATTERN-ARRANGE.md)，实际文件与静音记录见 `examples/validation-v15.json`。这一阶段完成不代表持续开发 goal 已结束。

## 0.14 更新：跨工程复用的乐句收藏

- **Pattern 库 → 导出库中乐句 / 导出此乐句**：选择源乐句、分页查看音符图，再下载 `.sprout-patterns` 文件。单句默认只选当前源，也可选择多句；文件只有相对拍数、固定 MIDI 音高、力度、微偏移、音源类别和导出工程的参考速度 / 调性 / 摇摆，没有轨道、音色、混音、实例、服务地址或密钥。
- **导入乐句文件**支持这种收藏，也能从完整 `.sprout` 工程提取已存入 Pattern 库的源。只在本机读取，不上传、不调用模型、不从普通音块自动推导乐句。整个文件先校验，共享缓存损坏、未知格式 / 字段、非法音符或超限时不部分导入。
- 预览可全选 / 全不选、跨页保留选择、查看音域与相对音符。默认按音源、长度和音符内容跳过已有或文件内相同乐句，忽略名称与 IDs；也可以明确 **仍作为新收藏导入**。重名自动加后缀，新源与其音符重新生成 IDs，绝不覆盖、关联或同步到原有源。
- **只加入库，不播放**作为一次可撤销编辑，走普通工程自动保存；不新增轨道或音块，不改变已有引用、音符、标签、音色、混音、速度和调性，也不启动或重启播放。之后仍须明确放置才进入歌曲。文件读取后 / 确认时检查工作区和窗口，旧预览不能覆盖改变后的工程。
- 参考速度 / 调性 / 摇摆只是导出时工程的信息，不是每句的调性分析或永久来源记录；导入不自动改音高、量化或套用这些全局值。重新导出使用当前工程的参考信息。鼓仍仅能放到同种鼓轨，旋律可放到旋律音源轨。收藏不是采样、插件预设、云库或 `.flp`。
- 文件最多 **3 MB UTF-8 字节 / 64 个源 / 12,000 源音符 / 每源 4,000 音符**。所选新增源与现有库一起计算上限，且完整工程仍须符合 3 MB 保存上限；整组成功或整组拒绝，不自动淘汰。导出也检查字节数，避免下载无法再导入的文件。
- 实际静音下载 `portable-phrases.sprout-patterns`：电钢琴 / 底鼓 / 旋律共 **3 句、30 音符**。原 32 小节工程导入时跳过已有电钢琴、只新增两源，**816 音符 / 4 共享引用逐字段保持，实际 MIDI 与原文件逐字节相同**。选鼓句明确重复导入，得到新 ID 与“导入 2”后缀，可一次撤销。
- 真正另建空白工程（新工程 ID）：先导入三源，仍 **0 音符 / 0 引用**；再主动放到三轨第 9 小节，明确空白延长至 16 小节，得到 **30 音符 / 3 引用**。实际 MIDI 逐音核对；区段 WAV 7.0814 秒、峰值 0.39731 / RMS 0.06171 / 削波 0，44100 Hz / 立体声 / 16-bit。只离线渲染，未播放，未做听感评价。测试后原始 32 小节工作区完整还原。

收藏格式与操作边界见 [PATTERN-FILES.md](PATTERN-FILES.md)，实际记录见 `examples/validation-v14.json`。

## 0.13 更新：服务配置检查与可以停止的生成

- 助手设置新增 **状态服务地址** 和 **检查配置（不调用模型）**。本机默认 `/api/llm/status`，只用 GET 读取芽音协议、地址 / 凭据格式、模型名称是否配置与容量声明；不发送描述或工程，不向模型厂商发请求，不回传密钥、上游地址或模型名。状态可达 / 配置有效不等于凭据、额度或音乐质量已通过真实调用。
- 状态地址须与编曲地址同源，并明确声明匹配的编曲路径和协议版本。不猜测外部地址、不自动连接、不随保存调用模型；没有状态接口仍可保存并手动生成，但不会宣称连接已验证。编辑地址 / 模式、关闭窗口或点停止检查会中止检查并忽略旧结果。静态在线版没有该后端，会说明如何使用自有服务。
- 生成期间显示已等待时间、冻结范围和 **停止等待**。取消后立即允许新请求；迟到结果与旧请求的结束处理不能覆盖新候选或释放新请求状态。浏览器等待最多 90 秒，本机上游最多 80 秒；状态检查最多 8 秒。停止等待只保证本页忽略结果并尽力中止上游，**服务商已经处理的请求不保证停止或取消计费**。
- 网络 / 超时 / 限流 / 临时服务失败提供显式 **按原范围重试**，不自动重试。保留原稿、原范围和参数；工作区或服务设置改变后拒绝旧重试。切换当前范围后，重试仍使用卡片所说明的原范围，而不是悄悄改目标。保存不同服务设置会清除旧等待 / 重试状态。
- 认证、缺少协议、未配置、配置格式、非 JSON、截断、容量和无效工程等分别提示；网页和本机服务器不显示任意上游异常 / 响应错误文本。流式读取按 UTF-8 **字节**限制 3 MB，超量 / 取消时停止读取；状态响应上限 32 KB，不跟随服务重定向，不发送浏览器凭据。
- 本机服务在读完请求体后再次检查并发位置，避免两条同时上传的请求都启动模型；每个服务实例独立计数。客户端断开会传递 AbortSignal，及时释放等待位置；仍由服务商决定是否取消已经开始的推理。`.env` 只在 CLI 启动时读取，导入服务模块做测试不读取环境文件。
- **完整链路仍只用模拟模型验收**：真实网页 → `/api/compose` → 真实适配器 → 合成的兼容响应 → 局部保护 → 保留 / 明确应用 / 撤销。8 条本机模拟编曲调用（4 成功、1 取消、2 网络故障、1 脱敏故障），没有真实模型或付费调用；另外两个慢速状态 GET 均被中止，没有发送工程。结束后恢复离线与原始工程。
- 实际导出 `examples/service-demo-baseline.sprout` / `service-demo.sprout` / `service-demo.mid` / `service-demo-region.wav`：32 小节 / 7 轨 / 816 音符，目标电钢琴 192 音符，其中 190 个实际变化、2 个目标共享引用独立化；其他六轨、源库、音色、混音、标签与练习范围逐项保持。原稿只与长曲示例的练习范围不同（第 7–8 小节），已单独保存以保证回归起点准确。MIDI 816 音符逐一核对；区段 73 音符、8.0014 秒、峰值 0.40720、RMS 0.08293、削波 0，44100 Hz / 立体声 / 16-bit，未播放。听感未验收。

详细自有服务协议与取消边界见 [SERVICE-PROTOCOL.md](SERVICE-PROTOCOL.md)。

## 0.12 更新：候选架与三版对比

- 助手生成后点 **保留这版**，保存完整候选、它的原稿、描述、范围和参数。规则或你配置的模型服务结果都可保留。保留、打开、比较、改名和下载都不自动应用或播放。
- **规则三版**用同一原稿生成 A 留白 / B 适中 / C 活力。明确预览密度、复杂度、能量、人性化及共同种子；沿用和声进行与声部连接，B/C 种子依次加 1。即使助手设为模型服务，三版也只运行本机规则。相同输入可复现音符内容，但 ID 独立；不保证三版不同或更好。
- 范围冻结为整首 / 当前轨道 / 当前块 / 鼓轨 / 当前歌曲段落。三版共用单版合并保护：局部时间外和其他轨道、音色、混音、源库、段落标签及全局设置保留。生成窗口打开后工程改变会拒绝旧窗口。
- **候选架 → 比较两版，不播放**按 A → B 显示逐轨新增、删除、长度 / 力度 / 微偏移修改，ID 不计变化；两版必须基于同一完整原稿。可下载含来源 / 参数的 JSON 对比报告；不是音乐质量评分，没有自动“最佳”。
- **打开 B 为候选**只暂存到审核卡片，仍需另点 **应用这一版**；应用前备份并支持工程撤销。完整原稿与工作区不一致时不能打开 / 应用旧候选；可以查看或下载，撤销回原稿后重新选择。异步备份期间切换候选也不能套用旧结果。
- 独立 IndexedDB 候选库，事务成功才标记保留，最多 **6 版 / 8 MiB**，每个原稿 / 候选工程最大 3 MB。三版要么全存要么全拒绝，**不自动淘汰**已有版本。多页通过事务版本检查拒绝互相覆盖，再显式重新读取。校验失败不会重置或覆盖旧记录；存储不可用时直接生成与工程编辑仍可用。
- 可改名、下载单个 `.sprout`、移除并在本页面撤销最近一次移除；**移除撤销不跨刷新**。候选库仅在同一浏览器 / 网站来源内，不是云备份，也不随单个工程文件迁移。清理 / 回收 / 隐私会话退出仍可能丢失；重要候选请单独下载。
- 实际静音 UI 示例：从 32 小节 / 7 轨 / 816 音符原稿，只改第 17–24 小节副歌，A/B/C 为 **690 / 734 / 814 音符**。A → B 新增 58 / 删除 14 / 修改 64，段外 IDs、4 个共享引用、音色、混音和标签逐项保持。`examples/candidate-a.sprout`、`candidate-b.sprout`、`candidate-c.sprout` 和 `candidate-ab-comparison.json` 均为实际下载。
- 明确应用 B 后实际导出的 `candidate-b.mid`逐一核对 734 音符；`candidate-b.wav` 91.7223 秒、峰值 0.47177、RMS 0.08419；`candidate-b-region.wav` 24.7456 秒、峰值 0.43900、RMS 0.06955（区段 122 音符）。均为 44100 Hz / 双声道 / 16-bit、削波 0，离线渲染后没有播放。数值检查不代替白天人工听感评价。
- `candidate-mock-service.sprout` 来自**自建 localhost 模拟服务**，不是大模型：仅把电钢琴 165 音符力度改为 42，2 个目标共享引用局部独立化，其他六轨与源库保持。前端发送平铺 v2；测试后已恢复离线设置并停止模拟服务。真实服务仍需用户提供配置。

## 0.11 更新：长曲工程与不会挤扁的时间线

- 工程支持 **4 / 8 / 16 / 32 / 64 小节**。改变长度先打开静音影响预览，默认新增部分 **留空白**；明确选择“重复现有内容”才复制各轨的旧内容与空隙。新副本独立编辑，原共享关系、源库、乐器、音色、速度、调性、混音和旧音符 IDs 精确保留；标签不自动重复，不把重复称为智能编曲。
- 缩短前显示移除 / 裁短的音块、音符、段落及练习范围变化；取消不改动，应用前备份旧版，一次可撤销。重复导致每轨 4000 / 合计 12000 音符上限时整组拒绝，不默默丢音符；旧窗口不能覆盖已经改变的工作区。
- 时间线可选 **自动 / 整曲 / 8 / 16 / 32 小节视窗**，原生水平滚动、滑杆和数值小节跳转；数值可按 Enter 确认，非法输入恢复实际视窗。自动桌面最多 16 小节，窄屏最多 8 小节；轨道标题固定在左侧。“查看此段 / 看当前块”滚到正确位置，**不改音乐、不改变播放位置、不启动试听**。自愿勾选“跟随走拍”才自动移动视窗，默认关闭。
- 钢琴卷帘的逻辑宽度仍覆盖整曲，但 **Canvas 位图只占当前视窗宽度**；绘制与点击 / 双击 / 拖框使用滚动后的绝对拍坐标。64 小节不创建 8960 像素宽的纹理；当前浏览器 DPR 上限 2。它还不是海量工程渲染器：轨道 / 音块节点和音符数组仍有容量上限。
- 鼓编辑器用小节下拉、前后按钮及当前组 8 个小节按钮，64 小节不堆 64 个快捷按钮。原有连续复制、库实例放置、和弦、段落整体编排和模型协议统一支持新边界。
- MIDI 导入支持到第 64 小节，超过时明确报告截断；32 / 64 小节文件不再在第 16 小节截断。离线 WAV 调度上限与工程一致为 12000 音符；长曲文件 / 内存消耗更大，低速 64 小节可超过六分钟，不保证低内存手机成功渲染。模型完整返回仍限制 5000 音符；服务请求上限 3 MB。真实模型、长曲智能分段生成与听感验收仍未完成。
- 实际静音 UI 示例 `examples/long-song-demo.sprout` / `.mid` / `.wav`：旧 8 小节七轨 204 音符明确独立重复为 32 小节 **816 音符**；旧源库 1 个 / 4 引用保持，新副本无共享引用，每个八小节跨度中的原空隙保持。四段标签各 8 小节，副歌练习范围为第 17–24 小节。不是一首经过音乐人评价的完整原创歌曲。
- 实际整曲 WAV 91.7223 秒，峰值 0.47177 / RMS 0.08791；`examples/long-song-region.wav` 为 24.7456 秒，峰值 0.47177 / RMS 0.08435。均双声道 44100 Hz / 16-bit，削波样本 0；**只离线生成文件，没有播放或人工试听**。

## 0.10 更新：让乐句变成歌曲段落

- 编曲区点 **歌曲段落**：选“主歌 → 副歌”或“前奏 → 主歌 → 副歌 → 尾奏”新手骨架，先查看分段再应用。骨架只添加 / 替换标签，**不生成或复制音乐**。可自定义名称、类型、完整小节起点和长度；不重叠，最短 1 小节，0.10 当时支持 4 / 8 / 16 小节；0.11 已扩展到 64 小节。旧工程没有段落字段时保持兼容。
- 轨道上方的段落条与所有音块共用横向滚动坐标。点标签选段，不播放；点 **段落设置**只改标签。**仅删除标签**不删音乐，**整体编排 → 清空这段音乐**才会删除该窗内所有轨道的音块片段 / 音符，保留时间和标签，不挤走后面的内容。
- **整体编排**可复制或移动所有轨道在段落内的内容，包括静音块（不取消静音）。原子碰撞保护要求目标在全部轨道和标签上都留空，**空音块也占位置**；不覆盖、不自动重排、不做 ripple。源与目标不得重叠。可明确勾选超长时延长为留白，新增部分不自动重复其他内容；0.10 当时超过 16 小节整组拒绝；0.11 上限为 64。
- 普通复制默认独立；明确勾选可让 **完整共享块**继续引用源乐句，并生成合法实例 IDs。移动完整共享块保持引用和原 IDs。跨段落边界的音块 / 长音会切分，所有切片独立，源库和未受影响引用保持；范围外长音两侧保留，不能保存的过短音块 / 音符会拒绝整组，而不是悄悄丢掉。微偏移受切片边界限制并显示数量。切分长音会重新起音，**不是无缝音频剪辑**。
- 窗口展示所有轨道数量、源块、切分块 / 长音、音符标识增减、共享复制 / 独立片段与显式延长。先改草稿，取消不写入；应用前留旧版本，整次操作一次撤销，保存和刷新保留。工程或段落选择变更后拒绝旧窗口覆盖。音色、混音、源库和全局音乐设置不改；练习范围保留绝对位置，**不会跟随移动的段落**。
- **练习此段**只设置全轨时间窗，不自动播放；**只编曲此段**设置助手范围，先生成候选再决定是否应用。离线规则支持段落约束，真实服务适配器携带并在请求前校验 `selectedSectionId` / `sectionRange`，服务端和前端都只合并段内音符、保留段外长音片段、标签、音块布局、原音源 / 音色、混音与全局速度 / 调性 / 长度。生成期间更换段落拒绝旧候选。模型输出只填现有音块的窗口，不自动创建空隙音块；真实模型音乐质量仍未联调，测试仅模拟响应。
- 工程保留段落字段；MIDI / WAV 展开已有实例与实际时间，不重复叠加共享库。MIDI 当前不写歌曲段落标记；完整 / 练习段落 WAV 均仅离线渲染，没有自动播放。
- 实际示例 `examples/song-sections-start.sprout` → `song-sections-demo.sprout`：4 小节 / 7 轨 / 131 音符 / 1 源 / 2 引用，加两段骨架；把 2 小节主歌复制到第 5 小节（显式关联与留白延长），再整体移到第 7 小节，设置练习范围。结果 8 小节 / 204 音符 / 1 源 / 4 引用 / 3 段，第 5–6 小节保持留白，原有全部内容和三轨音色保持。实际 `.mid` 逐音核对 204 音符的音高 / 力度 / 起音 / 长度；完整 WAV 24.7456 秒、峰值 0.47177、RMS 0.08435；区段 WAV 8.0014 秒、峰值 0.39771、RMS 0.08543。均为立体声 44100 Hz / 16-bit、削波 0、配置尾音 2.42 秒。未试听，不把数值验收当听感保证。

## 0.9 更新：写好音符，再整理演奏

- 钢琴卷帘点 **演奏整理**，鼓轨也能从音块工具栏进入。明确选 **所选音符 / 当前音块 / 整条轨道**；默认有选区用选区，否则用当前块。包含静音块的编辑音符，但不取消静音。四个预设“整齐一点 / 自然一点 / 轻一点 / 有力一点”先改草稿，不重新生成乐句、不播放、不调用模型。
- 演奏力度按原值乘 25–200%，可加 0–20 的正负力度变化；保持 1–127 范围并报告触顶 / 触底数量。100% 且变化 0 不改力度。重复应用比例或力度变化会累积，不是无损实时效果器。
- 微时间可 **保留 / 清除 / 重新生成松紧**。清除只去掉所选音符的微偏移，不改变名义位置、长度或顶部全局摇摆。重新生成覆盖旧偏移，最大 ±0.04 拍，原本同起点的所选和弦共用偏移，音块边界处限制并显示数量；不叠加旧时间偏移。
- 起点对齐支持 1/32、1/16、1/8、1/4 网格与 0–100% 强度，**只动起点，不量化长度、不跨原音块**。放不下原长度或保留的微偏移越界时整组拒绝；拒绝后仍可降低对齐程度，或明确清除 / 重算微偏移。不是偷偷裁短音符。
- 同音高重叠检查使用与 MIDI / WAV / 调度相同的实际起音（全局摇摆 + 微时间 + 音块边界）。统计与目标范围有关的全部配对，详情最多展示 30 对，不把和弦不同音高或音色余音算成冲突。默认 **保留长度、仅提示**；明确选“缩短前音”才可改目标范围内的前音长度。范围外前音、同时起音或不足最短音符的冲突会整组拒绝，**不自动删音符、不改范围外音符**。
- 应用前显示力度 / 微偏移 / 起点 / 缩短数量和分页逐音前后表，实际起音差换算为毫秒；共享实例变化会显示独立化数量，源库和其他引用不改。没有变化或非法 / 受阻草稿不能应用，取消完全不改工程。应用前先保存旧版本，整个整理可一次撤销，刷新恢复音符结果；工程或音块选择变更会拒绝旧窗口覆盖。
- 本次参数与种子属于草稿，不改全局编曲参数记录；结果写入现有音符，音高 / IDs / 音块位置 / 音色 / 混音 / 其他轨道保持。固定基线工程、范围与种子可重现变化；重新打开默认中性，不自动再次减力度。MIDI 导出烘焙实际时间，工程保留名义网格与微偏移。
- 实际示例 `examples/performance-demo.sprout` / `.mid` / `.wav` 和 `performance-region.wav`：保留 7 轨 / 123 音符，1 源 / 1 引用。第 11 小节电钢琴共享实例局部整理（种子 1、力度 80%、变化 5、松紧 100%）后独立化，三音符力度为 72 / 70 / 68，微偏移均 0.0335 拍；第 12 小节只清除所选 A3 的 0.0056 拍偏移，同块 C4 / E4 保持。全部数据精确等于这两次受控操作的结果，原源乐句、Pad 引用、其他六轨、音色、混音和范围不变。MIDI / 调度仍是 120 音符，逐音核对位置、长度、音高和力度。
- 实际整首 WAV 48.0712 秒、峰值 0.33862、RMS 0.05600；区段 6.2107 秒、峰值 0.12976、RMS 0.02323。均为立体声 44100 Hz / 16-bit，削波 0、保留原 3.42 秒配置尾音。没有试听，不能据此评价听感或专业编曲质量。

## 0.8 更新：不懂合成器也能调音色

- 编辑器点 **◉ 音色**，或混音台点某一轨的音色按钮。先选“柔和一点 / 清晰一点 / 短促一点”，再用中文滑杆调起音、余音、亮度与持续音量；衰减、滤波突出感和波形放在高级区。鼓轨按鼓种只提供适用的衰减、鼓体频率 / 噪声滤波和军鼓鼓体比例，不冒充完整插件。
- 窗口始终先改草稿，**应用到此轨**才写入，取消不改变工程；无变化或非法参数不能应用。包络图只画曲线、不发声，安静模式的检查按钮不创建或恢复实时音频上下文。窗口打开后工程改变会拒绝旧草稿覆盖。
- 旋律使用有界线性 ADSR、低通 cutoff / Q 与原生多层或四种基础波形。短音提前松开时从实际包络值进入释放，不跳到峰值；波形选择保留层数、音高比和混合比例。鼓实际改变自然衰减、底鼓扫频 / 噪声滤波 / 军鼓鼓体比例，长噪声会循环。参数进入实时合成和离线 WAV 的同一 `synthNote`，不是仅修改界面。
- 自定义音色是可选的轨道 `sound` 数据，随工程、版本、撤销 / 重做和刷新保存。**未启用保持旧版合成路径**；恢复原始音色删除这个字段，不是用近似参数模拟旧音色。更换乐器会恢复新乐器原始音色；旋律共享引用保留，换鼓种会明确独立化并改成对应 MIDI 鼓音高，源乐句保持。
- 音色只影响这条轨道的全部音符，包括共享实例；**不改音符、混音、源乐句或其他轨道音色，也不解除共享**。编曲候选与模型合并保留原音色，审核显示音色变化轨数。模型只收到当前轨道参数；没有真实服务调用。
- WAV 按最长配置保留尾音，旧工程仍为 1.5 秒，最大释放 3 秒时加 4.02 秒尾音。循环右边界仍硬截断声音源，回声可自然衰减，尚无交叉淡化。**MIDI 不含自定义合成参数**，仅带音符、GM 乐器与混音 CC；接收软件决定实际音色。
- 实际静音 UI 导出 `examples/sound-design-demo.sprout` / `.mid` / `.wav` 与 `sound-practice-region.wav`：只改军鼓、电钢琴和 Pad 三轨音色，原 7 轨 / 123 音符 / 1 源 / 2 引用、所有音块与混音完全不变；MIDI 和 0.7 示例逐字节相同。Pad 释放 2.4 秒使尾音为 3.42 秒；整首 WAV 48.0712 秒、峰值 0.33862、RMS 0.05684，区段 6.2107 秒、峰值 0.19440、RMS 0.03543。均为 44100 Hz / 立体声 / 16-bit、削波 0，波形与旧合成不同；未试听，不代表专业音质已经验收。

## 0.7 更新：真正的共享 Pattern 库

- 编曲区点 **Pattern 库**，或选一个音块点 **存到库**。默认仅保存源乐句；明确勾选后可把当前块同时关联。库随工程保存，不是另一个账号服务。
- 一个源乐句可以放成多个 **↔ 共享引用**。旋律允许跨旋律乐器轨放置，鼓仅允许同种鼓轨。也可不勾选关联，放成独立副本。遇到已有块或上限会拒绝；显式延长只增加空白，不自动重复其他轨道。
- **只有库中的共享编辑会同步所有引用**：分页数值改音高/位置/长度/力度/微偏移，添加/删除音符、整体半音移调或统一力度。显示关联轨道和位置，先静音预览，再保护性备份并整项应用，可一起撤销。加长遇到相邻块或工程边界，全部拒绝；缩短须先明确裁尾，不偷偷丢音符。
- **局部编辑安全优先**：钢琴卷帘、鼓步进、和弦输入、局部候选与剪裁/分割，只把发生音符或长度变化的引用自动独立化；源乐句与其他引用不改。移动、改音块名、块静音保持关联。普通复制 / 连续复制仍是独立副本。也可点“独立化”保留现有音符并解除关联。
- “关联当前音块”默认仅接受内容相同、等长的块；不同内容须明确勾选替换，先备份。删除被使用的源乐句会明确说明全部实例独立化，**保留已有音符**，不是从歌曲里删除这些块。
- 工程 **version 3** 同时保存相对时间的源乐句和绝对时间的实例缓存；导入严格核对源、引用、稳定实例 ID 与音符缓存。不一致即拒绝恢复，不悄悄覆盖。v1/v2 继续可导入；未使用库的工程仍为 v2。库最多 64 个源乐句、每源 4000 音符、库合计 12000 音符；已放置实例另受原有工程音符上限约束。
- MIDI / WAV / 调度只读取已放置的实例，每个只展开一次；未放置的库源不额外发声。音高是固定 MIDI 音高，不自动跟随调性。全局转调会让音高变化的引用独立化，库中原乐句保持。
- LLM 只收到平铺的 v2 工程，不收到共享源库；返回后保留原库并核对引用，改动的块独立化。候选审核显示源数量与将独立化的块数量。真实模型仍未调用或配置。
- 实际静音 UI 导出的 `examples/shared-pattern-demo.sprout` / `.mid` / `.wav`：7 轨 / 123 音符，1 源 / 2 引用；源和引用力度 90，局部独立块力度 50，普通复制块力度 90。MIDI / 调度均 120 音符（排除静音块 3 音符），逐音核对；WAV 46.1512 秒、立体声 44100 Hz，峰值 0.36136、RMS 0.06611、削波 0。未播放，音质未作人工评价。

## 0.6 更新：练习范围、音块预览与连续复制

- 编曲区新增 **练习范围**：设置起始小节和长度，或点“用当前块”套用所选音块。范围只改变播放窗口，不删除/移动音符。顶部循环按钮决定反复播放或只播放一次；“整首范围”恢复全曲。范围写进工程 `loopRange: {start,end}`，拍数为左含右不含，可撤销、导出和刷新恢复。循环开关本身是当前页面的播放状态，刷新默认开启，不会自动开始播放。
- **只预览此块** 仅调度该音块所在轨道在该时间窗的音符，保留轨道 M/S、混音与块静音。静音块或空块会提示原因。暂停后主播放按钮可继续，停止退出音块独立预览。选其他轨道不偷偷切换正在预览的块；删除正在预览的块会停止，不自动改播整首。
- 范围外定位会拒绝并提示先恢复整首。编辑、暂停、撤销/重做与范围变化都保持游标在有效窗口内。左边界的持音重新起音并保留剩余长度，右边界截断持音及振荡器/噪声源；不是采样级续播。回声尾音可以跨循环点自然衰减，尚无交叉淡化。
- **安静模式走拍现在不创建或恢复实时 AudioContext**，不连接声卡，也不创建实时声音节点。使用单调时钟运行同一音符/节拍调度和游标。退出安静模式后，已开始的虚拟播放仍不发声；停止后再次主动播放才启用真实声音。WAV 仍使用 OfflineAudioContext，仅产生文件。页面从不自动播放。
- **连续复制**：选择源音块，设置新增副本数 1–32、第一份起始小节、间隔拍数。先显示数量/位置预览，再整体应用；遇到已有音块或容量上限，全部拒绝，不部分覆盖。
- 显式勾选“需要时延长工程”，现可扩展到 4/8/16/32/64 小节中的合适长度，最大 64（0.6 当时为 16）。这里的扩展只增加空白；0.11 工程长度工具也默认留白，重复须明确选择。源音块、其他轨道和混音保留，每份分配独立音块/音符 ID，保留微偏移、力度和块静音；全部新增作为一次可撤销编辑。仍然不是可共享引用的 Pattern。
- 导出窗口以打开时的工程快照导出，避免后台更改造成不一致。默认 WAV 仍是整首，另可勾选 **WAV 只导出练习范围**；区段从零开始，额外附 1.5 秒效果器尾音。MIDI / 工程始终完整导出，不受练习范围裁剪。
- 实际示例 `examples/repeat-loop-demo.sprout` / `.mid` / `.wav`：7 轨，105 → 114 音符，8 → 16 小节；第 9/10/11 小节新增三份电钢琴块，共 9 音符。只把最后一份的 3 音符力度改为 60，原音块和另外两份保持原样；其他六轨完全不变。练习范围为第 11 小节一小节。MIDI 的 111 个可发声音符逐一核对（排除静音块 3 音符）。
- 实际整首 WAV：46.1512 秒、峰值 0.361、RMS 0.061；`examples/practice-region.wav`：4.2907 秒、峰值 0.148、RMS 0.033。均为双声道 44100 Hz / 16-bit，削波样本 0。没有播放声音；这不证明音质已达到专业标准。

## 0.5 更新：编曲调色盘与候选差异

- 助手上方点 **编曲调色盘**，选“留一点空白 / 刚刚好 / 多一点能量”，再调密度、复杂度、演奏能量、人性化；启用后用于下一次生成，当前工程不变。
- 密度保留每条非空轨道每小节的首个事件，再按稳定随机值筛选其余事件；和弦的同时起音保持成组。复杂度控制细分、切分、填充和三/七和弦。它们控制的是模板，不是任意风格的音乐理解。
- 温柔循环、明亮起伏、回到原点：按当前调性的音级编写。平滑声部用转位与音区搜索减少相邻和弦声部跳跃；不是完整对位规则系统。
- 演奏能量调整音符力度，不重置混音。人性化同时轻微变化力度与时间，微时间存为 `timingOffset`（拍），最大 ±0.04 拍，边界处收敛到音块内；钢琴卷帘仍显示名义网格位置。检查器可显示微偏移毫秒值。
- MIDI 把律动与微偏移共同烘焙到实际拍位置；WAV 和实时调度使用同一拍位置函数。工程文件保留名义网格和偏移。MIDI 再导入保留实际时间，不还原偏移元数据。
- **变奏种子**在高级区。相同工程、描述、范围与参数在离线模式重现音符内容；ID 仍独立分配。新种子只影响下一版。参数设置保存在本浏览器，与工作区撤销历史独立；整首生成后工程记录这一版参数，局部生成不会改工程全局参数记录。
- 所有离线范围生成都保留已有轨道、音源、名称、音块布局、静音与混音。局部生成额外保留速度、调性、长度、风格与律动；描述中的“只修改贝斯”等也按局部范围保护。扩大工程长度会延展原音块，缩短会裁剪，候选预览会列出长度变化。
- 候选卡片点 **查看变化**，逐轨检查增加、删除、修改和全局变化，无需播放。按音高与名义拍位置配对，ID 不计变化；长度、力度、微偏移变化算修改，移位或移调计删除＋新增。未应用仍不覆盖工程。
- LLM 协议接收相同参数、音级进行与范围。后端强制合并保护原轨道/音源/混音/音块，只对目标范围施加有界人性化及能量；密度、复杂度、和声与声部连接仅是模型软约束，不保证逐项满足，模型结果也不保证种子可重复。本轮只做模拟响应测试，没有真实调用。
- 示例 `examples/palette-demo.sprout` / `.mid` / `.wav` 由实际静音 UI 导出：7 轨，243 → 105 音符，85 个非零微偏移。MIDI 102 个可发声音符逐一核对音高、力度、拍位置及长度（3 个音符在静音音块中被排除）。WAV 双声道 44100 Hz、23.8256 秒，峰值 0.361、RMS 0.082、削波 0。未播放，音质仍待白天人工评价。

## 0.4 更新：新手音符编辑与和弦小助手

- 空白处拖框、Shift 点选或开启多选模式；可选当前音块、选全轨。点击“已选”定位所选音符。
- 音符列表按音高、小节、长度和力度显示，每页 50 个，支持勾选与选择本页；触屏和键盘用户不用精确点中 canvas 上的小音符。
- 拖任意选中音符整组移动，拖右边整组调整长度。方向键按网格 / 半音移动；Shift + 方向键按一小节 / 八度移动。越界时整组拒绝，不偷偷裁短或压缩间距。
- 批量窗口可以移动、移调、设置统一长度与力度，或复制成独立副本。音符复制粘贴使用应用内数据，不读取系统剪贴板；可填小节数选择粘贴位置。
- 钢琴卷帘聚焦后，⌘/Ctrl A 全选、D 向后独立复制；C/V 应用内复制 / 打开粘贴窗口。不会抢占文字输入框的快捷键。
- 和弦小助手按照当前调性提供七个级数的三和弦 / 七和弦、两种四和弦进行、原位 / 转位、音区、力度，以及一起按下或上下分解。高级参数默认折叠，不需要学习术语即可开始。
- 只预览音符，不播放声音、不调用模型。追加会检查同音高重叠；替换前保存工程版本，只改声明的范围，保留两侧长音片段和相邻音块。切点太靠近音符边缘时拒绝，避免无声丢弃极短尾部。
- 单音符长度编辑和量化也改为完整边界检查；有选择时只量化所选音符，没有选择时量化整轨。
- `examples/note-chord-demo.sprout/.mid/.wav` 是实际从界面完成列表选择、批量移动/移调、粘贴、整组拖动、框选、键盘移动和四和弦分解写入后导出的示例，不是人工拼接的导出文件。

选择、框选和复制本身不修改工程，也不会清除助手候选；真正的音符编辑仍可撤销并进入自动保存。和弦助手是确定性的音乐规则，不是真实 LLM，也不保证所有风格的编曲质量；暂不支持自定义和弦、自动声部连接或跨轨音符多选。

## 0.3 更新：本机版本与恢复

工程自动保存改为 IndexedDB 事务提交；只有提交成功才显示“已保存”。顶部保存状态或工程 → 本机版本与恢复，可以创建命名保存点、查看速度/调性/轨道/音符差异和轨道缩略图，再恢复或下载工程。预览不会播放声音，也不会改变当前工程。事务使用依据 [W3C IndexedDB 规范](https://w3c.github.io/IndexedDB/)。

- 导入 MIDI/工程、新建、换风格、应用候选、恢复版本，以及清空轨道或删除轨道/音块前，先保存旧版本，再执行修改。
- 备份失败时默认不执行替换；可以明确选择先下载当前工程，再继续内存编辑。保存失败、应急保存和正常保存会分别提示。
- 编辑时每分钟保留一个自动版本，空闲时不反复保存。命名保存点和操作前备份共用最近 24 个 / 8 MiB 保存点数据上限；最早版本会被移除，不能作为永久备份。
- 保留最近有效保存，启动时校验数据；损坏时寻找上一版或可用保存点。损坏记录可下载原始 JSON，但不会未经校验直接恢复。校验码用于检测意外损坏，不是加密或真实性认证。
- 内存撤销 / 重做最多 45 步；正常或应急刷新最多恢复各 8 步，合计不超过 1.5 MiB。大工程会按容量缩减历史。
- 编辑立即写带有界历史的应急记录，离开页面时尝试冲刷。应急记录仅用于兜底，退出时异步事务不保证完成，配额不足也可能失败；重要作品仍应下载 `.sprout`。
- 双页编辑使用事务内版本检查，不静默互相覆盖。冲突时可下载本页后读取新版本，或保存副本并接管；接管前另一页内容也会留下保存点。
- 旧 localStorage 工程会迁移；原记录不删除。浏览器不支持 / 拒绝版本库时会明确提示，支持重试打开或下载文件。

**这些记录只在同一浏览器、同一网站来源内，不是云同步。** 清理网站数据、隐私浏览结束、浏览器存储回收或换设备均可能丢失。在线站点和本机预览各有自己的工程库；请用文件搬运。

## 0.2 更新：音块编辑与 MIDI 导入

0.2 的音块拥有独立的区域、名称和静音状态，移动/复制/裁剪会真实改变内部音符，不再只是编辑入口。普通复制始终是独立副本；0.7 新增可选的共享 Pattern 库，见上方。所有同轨音块仍不重叠；遇到占用会明确拒绝，不覆盖旧音符。

- 拖动移动，Alt 拖动复制，拖右边裁剪/延长；选中后可用工具栏复制、分割、块静音。
- 音块设置支持名称、起始小节和长度数值编辑，以及删除；触屏/键盘用户不用精细拖拽也能操作。
- 左右箭头按一小节移动；Shift + 左右箭头按当前音符网格移动；Delete 删除焦点音块。
- 延长只增加空白，缩短裁掉尾部音符；分割会切开跨分割点的长音符。
- 钢琴卷帘仍编辑整轨，选中区域高亮。音符跨音块终点时裁剪；在没有音块的空隙画音符会创建音块。
- 助手的“当前音块”只合并所选区域，保留相邻音块、轨道和全局设置；候选应用仍可撤销。
- v1 工程自动迁移到 v2；每条旧轨道先成为一个整轨音块，避免破坏跨两小节的长音符。
- `examples/clip-edit-demo.sprout` 是通过真实工作台拖动、复制、裁剪、静音、局部候选生成后导出的工程。

### 导入 MIDI

工程 → 导入 MIDI，支持标准 SMF format 0 / 1、PPQ、running status、note-on/off、速度、轨名、初始音量/声像、支持范围内的调号。导入前会显示音符保留数量和所有降级说明，确认后才替换，且可以撤销。文件和音符都在本机解析，不上传。文件解析依据 [MIDI Association 的 SMF 规范](https://midi.org/standard-midi-files-specification)。

目前最大 64 小节、16 轨、12000 音符和 5 MB。更长文件仅导入前 64 小节；格式 2 和 SMPTE 明确拒绝。固定 4/4 与起始 BPM，不还原速度/拍号变化、踏板、弯音、自动化或插件音色。常见底鼓/军鼓/踩镲映射到三个内置鼓，其他打击乐和音高 24–108 以外的音符不导入；**以上都在预览报告中列出，不悄悄丢弃**。不自动量化或转调。

## 第一次创作

- 起点：Lo-fi、Hip-hop、House、Ambient。切换会弹确认框，旧版本可以撤销。
- 先听：空格播放/暂停，停止按钮回到开头。节拍器与循环可开关。
- 轨道：M 静音；S 独奏，支持多轨独奏。
- 钢琴卷帘：双击添加音符；点击选中；拖动移动；拖右边延长；双击现有音符、右键或删除键移除。可在下方调整音高、长度、力度。
- 鼓步进器：每格一个十六分音符，即 1/4 拍；每 4 格是一拍。选择小节后点亮格子，也可复制到全部小节。
- 混音：每轨音量、左右声像，主音量；播放电平实时显示。
- 音色：选轨后点 ◉，中文预设和少量滑杆；只在应用后生效，随工程保存。
- 整理：写好音符后调整演奏力度、清除 / 重算微时间、部分对齐起点；明确选择范围，先看变化再应用。
- 编辑：4/8/16/32/64 小节，40–200 BPM，六种调性，摇摆律动，网格与量化；添加、改名、换音源、删除轨道。
- 音块：拖动、复制、分割、静音或数值调整；可只让助手改当前音块。
- 导入：工程菜单载入 `.mid/.midi`，先查看报告再确认。
- 助手：输入“鼓更有律动”“只修改贝斯，让它更有变化”等描述。先生成候选，再试听、应用或放弃。未应用不会覆盖工程。
- 导出：WAV 是可播放音频；MIDI 是多轨音符；`.sprout` 是完整工程。
- 快捷键：⌘/Ctrl Z 撤销，⌘/Ctrl Shift Z 重做；描述输入框中 ⌘/Ctrl Enter 生成。

自动保存只在当前浏览器、当前网站来源内。清理浏览器会丢失本机自动保存；本地预览与在线版本不会共享工程。重要作品请保存 `.sprout` 文件。

## 真实 LLM 接入

**默认是离线音乐规则生成，不是大模型。** 离线规则理解有限，不能保证任意自然语言要求、歌词或完整歌曲结构。UI 会明确显示生成来源。

服务端已经实现 Chat Completions 兼容适配器；尚未配置、未调用任何付费模型，也没有使用现有用户密钥。单元测试使用模拟响应，不等于验证了真实模型的音乐质量。

1. 将 `.env.example` 复制为 `.env`。
2. 填入你选择的兼容服务的完整地址、模型和自己的 API key。例如：
   - `LLM_API_URL`：服务的完整 `.../v1/chat/completions` 地址，不是基础 URL。
   - `LLM_MODEL`：该服务实际支持的模型名称。
   - `LLM_API_KEY`：只保存在本机服务端环境中。自托管无鉴权服务可留空。
3. 重启 `npm start`。
4. 网页右侧设置 → 我的 LLM 服务；编曲服务地址保留 `/api/compose`，状态地址保留 `/api/llm/status`。先检查配置，再保存；模型名可留空，以服务端为准。检查不会验证真实模型或自动生成。
5. 生成时才将描述和当前音符发送给配置的模型。播放、手动编辑和离线生成不发送工程数据。

适配器默认使用 JSON mode。若你的服务不支持 `response_format`，设 `LLM_JSON_MODE=0`。模型返回仍必须符合编曲 JSON 格式。JSON mode 仅保证 JSON 可解析，不保证音乐 schema；本应用对音符、数量、拍数和参数再次校验。相关接口设计参考 [OpenAI 官方结构化输出文档](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=chat)。

在线演示是静态版：默认离线引擎完整可用，**没有内置 LLM API 或 API key**。如要在线接真实模型，需另行部署编曲服务，并显式配置 HTTPS 服务地址和 CORS；不要把服务端密钥写进前端。

## 文件和架构

- `dist/index.html` / `styles.css`：工作台界面，无远程字体或图片依赖。
- `dist/app.js`：项目状态、UI、撤销/重做、候选审核、本机保存、导入导出。
- `dist/music.js`：工程 schema、校验、音乐规则、调性变换、长度调整、MIDI 编码。
- `dist/instruments.js`：统一内置音源元数据；`dist/patterns-core.js`：源库、稳定引用 ID 与缓存一致性；`dist/patterns.js`：原子共享/局部操作；`dist/patterns-ui.js`：库、放置和显式共享编辑窗口。
- `dist/clips.js`：非重叠音块、独立复制、区域编辑、v1 迁移、局部候选合并。
- `dist/midi.js`：边界受限的标准 MIDI 解析与导入映射报告。
- `dist/storage.js`：按工作区隔离的事务保存、容量受限版本库、应急日志、损坏回退和跨页面冲突保护。
- `dist/project-library.js` / `project-library-ui.js` / `project-starts.js` / `workspace.js`：原子作品目录、独立创建 / 切换 / 副本 / 导入 / 可逆归档、新手起点、切换预处理与每页本机地址标识。
- `dist/editor.js`：原子音符组编辑、复制/粘贴、范围替换与调内和弦/分解进行。
- `dist/composition.js`：严格编曲参数、稳定事件随机值、人性化、声部连接、候选音符差异。
- `dist/candidates.js` / `candidate-store.js` / `candidate-ui.js`：完整原稿身份、共享范围合并、纯离线三版、独立事务候选架与 A/B 对比。
- `dist/ranges.js` / `transport.js`：统一范围校验、窗口时钟、持音边界裁剪、定位起音与节拍计划。
- `dist/audio.js`：Web Audio 实时调度、内置合成器、混音图、离线渲染、PCM WAV 编码。
- `dist/section-transition.js` / `section-transition-ui.js`：段末现有鼓轨受控过门、静态节奏预览、空隙明确补块、长音 / 共享 / 预算保护。
- `dist/sound-bank.js` / `sound-bank-ui.js`：参数收藏 / 精确原始语义、跨音源兼容、便携文件与去重、独立事务存储、适用筛选 / 分页 / 可逆归档。
- `dist/sound.js`：音色 schema / 预设、线性包络与尾音规划；`sound-edit.js`：轨道设置 / 换音源 / 模型保护；`sound-ui.js`：中文草稿表单与无声包络图。
- `dist/performance.js`：严格整理参数、目标范围、稳定演奏变化、实际时间重叠报告与显式缩短规划；`performance-ui.js`：无声草稿、分页逐音预览和保护性应用。
- `dist/sections-core.js` / `sections.js` / `sections-ui.js`：可选段落元数据与保护、歌曲骨架、原子跨轨切片 / 复制 / 移动、段落候选合并与静音草稿界面。
- `llm.mjs`：服务端模型协议适配与输出校验。
- `dist/service.js` / `service-ui.js`：有界协议读取、只读配置检查、错误分类、请求取消隔离与新手设置。
- `llm-config.mjs`：不泄露值的配置元数据和上游格式校验。
- `server.mjs`：零依赖静态服务器、`/api/compose` 与 `/api/llm/status`，仅绑定本机地址。
- `tests/`：数据、MIDI/WAV 编码、模型适配与本机服务器测试。
- `examples/`：实际从浏览器导出的多轨 MIDI 和立体声 WAV。

声音可使用振荡器 / 噪声合成的八种音源，或 0.23 随包的立式钢琴、底鼓、军鼓与短镲录音。不是商业完整采样库；音色与混音仍是原型级。真实音频回调不调用大模型，模型只生成可编辑的音符。

```text
描述 → 离线规则或服务端 LLM → 候选工程 → 校验 → 试听 → 应用
                                             ↓
工程音符 → look-ahead 实时调度 → 合成器或采样器 → 每轨 gain/pan → 回声 → 主音量/压缩 → 声卡
工程音符 → OfflineAudioContext → WAV
工程音符 → 标准 MIDI format 1 → .mid
```

## 验证

```sh
npm run check
npm test
```

570 个自动化测试覆盖四种风格 × 六种调性 × 五种长度、重复生成、工程校验、局部修改保护、转调、MIDI/WAV 编码、LLM 模拟响应与异常、本机静态资源和未配置模型错误。包括音块编辑/边界/迁移/局部保护、MIDI 往返/格式 0/running status/速度变化/截断/坏文件、静音模式不创建实时音频上下文，以及版本/历史保留、损坏回退、保存失败、应急记录和跨页面冲突。音符组保持间距 / IDs / 无关轨道、边界原子拒绝、复制粘贴、框选相交、六调 × 七级 × 三/七和弦 × 转位、分解节奏、显式范围替换与长音尾部保留也有覆盖。

0.20 新增 32 项：25 项严格参数 / 三鼓型 / 窗外与旋律保护 / 力度种子 / 同种多轨 / M/S / 块静音 / 参数保护 / 空隙明确补块 / 边缘拒绝 / 长音片段与微偏移 / 共享局部独立 / IDs / 每轨与全曲音符 / 音块与完整保存预算 / 所有风格长度检查，7 项实际原稿 / 两小节过门 / MIDI / 区段 WAV / 手机只改军鼓 / 新建空隙块 / 最终刷新还原文件检查。旧窗口在真实候选应用后拒绝，所有音频只做离线导出。

0.19 新增 32 项：24 项八音源 / 原始缺省 / 25 种旋律源目标组合 / 鼓种限制 / 全文件校验 / UTF-8 限额 / 选项顺序 / 内容去重 / 明确新副本 / 长名称 / ID 碰撞 / 32 项含归档上限 / 校验码 / 独立事务 / 配额失败 / 双页 CAS / 归档恢复 / 重试 / 音乐与共享保护 / MIDI 中性 / 临近 3 MB 添加参数原子拒绝，8 项真实收藏 / 四项文件 / Pad / MIDI / 区段 WAV / 跨独立 House / 原始字段移除 / 原稿还原下载回归。收藏故障仅测试适配器注入，未修改真实浏览器存储；实际音色草稿收藏 / 导入 / 改名 / 归档操作不改变歌曲 revision。

0.18 新增 47 项：29 工程目录原子保存 / CAS / 配额失败 / 损坏保留 / 12 个上限 / 旧迁移 / 独立历史与应急 / 重试 / 新建失败选择保护，6 目标预处理 / 范围与选择 / URL 每页标识与静音参数保护，4 五起点 / 支持长度 / 严格输入契约，8 实际空白 / 副本 / 导入 / House / Lo-fi / 撤销还原 / 800 音符 MIDI 下载回归。故障注入仅用测试适配器，未修改真实浏览器存储。原稿从 5 撤销 / 2 重做到测试后 5 / 1 是正常新编辑分支清旧重做再撤销，不是切换丢历史；最终音乐字节一致。完整操作记录见 `examples/validation-v18.json`。

0.16 新增 27 项：22 项参数 / 中性 / 节奏倍数 / 区间倒序 / 半音再吸附 / 六调全音域最近音 / 同音高合并提示 / 音高与微偏移边界 / 空或静音块 / 碰撞 / 明确延长 / 64 小节与最短音符 / 鼓锁定 / 局部共享保护 / 名义和实际时间 / MIDI 与工程包 / 120 种风格调性长度 / 坏缓存 / 完整保存字节预算保护；5 项实际下载文件回归，逐项复算组合十六音符、六音符底鼓倒序、末段八音符展开、816 音符 MIDI 与 43 事件区段 WAV。

0.16 实际静音 UI：中性禁用、非法半音禁用、展开碰撞与超长默认拒绝、组合变换草稿两页前后、手机明确应用 / 一次撤销重做、刷新后下载字节一致、正常备份、取消 revision 不变、候选应用后旧确认拒绝、鼓控件锁定与真正只改六个底鼓音、末段展开明确留白 / 撤销。手机 390×844 对话框 y=12…832 / 页脚下边界 831，无页面横向溢出；桌面 1280×900 对话框 x=190…1090 / y=24…876，页脚下边界 875，表单无横向溢出。原 816 音符 / 四引用工程与练习 64…96 完整还原，quiet=true / hardwareAudioInitialized=false / playing=false，日志警告和错误 0。

0.16 历史记录：本轮当时发现自动提交前即时刷新仅从应急记录恢复音乐、不恢复撤销栈。0.17 已补齐有界应急历史与旧事务清理保护，并实际验证；容量不足仍可能仅保音乐或连应急写也失败。正常版本与应急路径最多各八项、共享 1.5 MiB，重要原稿仍应命名保存点或单独下载。

0.15 新增 28 项：22 项批量计划 / 严格参数 / 默认一份 / 共享与独立边界 / 碰撞 / 明确留白扩展 / 32 份 / 每轨 256 块、4000 音符及合计 12000 音符 / 完整 3 MB 保存预算 / ID 碰撞 / 4096 跨轨引用选管 / 四种操作 / 中性静音 / 字段保护 / MIDI 中性；6 项真实下载文件回归，逐字段重放十份、三轨拼装、选择性静音 / 独立化 / 删除、独立副本单份力度修改、跨乐器单块静音、实际 72 音符 MIDI 与区段 WAV。

0.15 实际静音 UI：默认无选择与无变化禁用、十引用两页选取保持 / 取消、碰撞与短间隔拒绝、三轨共享批量与独立两份明确留白延长、备份并选择性四操作、删除 / 独立副本修改的一次撤销重做、手机工程菜单撤销重做、刷新后实际下载字节一致、两个旧窗口遇到实际规则候选应用后拒绝且 revision 不增加、查看关联块不改 revision / 播放位置、同乐器默认目标。独立化期间虚拟时钟从 45.31509 → 45.83769 拍持续向前，quiet=true / hardwareAudioInitialized=false；随后停止。390×844 手机管理窗口下边界 832、页脚下边界 831，无页面横向溢出，1280×900 桌面。未做实际存储故障注入或最大容量硬件渲染，4096 引用与各容量限额仅合成自动化；未试听或使用真实 LLM。

0.14 新增 25 项：精确源导出与选择顺序、完整 v3 工程库提取 / 坏缓存拒绝、版本 / 字段 / 名称 / 音符 / 微时间严格校验、参考信息只读、ID 中性去重 / 文件内确定顺序 / 明确新副本、长名称后缀、空乐句、生成 IDs 重试与碰撞拒绝、64 源 / 单源与合计音符上限 / UTF-8 文件上限 / 完整工程保存上限原子保护，以及实际收藏 / 单句 / 默认与重复导入 / 另一空白工程 / 三轨明确放置 / MIDI / 区段 WAV 下载回归。

0.14 静音 UI：单句与多句下载、空选禁用、默认去重与全重复禁用、只复制所选鼓句 / 后缀 / 撤销、实际存储刷新、旧预览遇到实际候选应用后拒绝并禁用确认、坏工程缓存与超限文件拒绝、两页选择保持和 HTML 名称文本转义、取消不改变工程、跨工程导入不放置 / 主动三轨放置 / 空白延长与鼓种限制；桌面 1280×900、手机 390×844 可滚动预览和固定确认区。范围和音频仍遵守安静模式，不以数据检查替代听感验收。

0.13 新增 22 项：地址与凭据格式、无值配置元数据、只读 GET / 无凭据 / 无工程、协议与路径 / 容量声明校验、UTF-8 流式容量与取消、错误脱敏 / 分类、已经取消不发请求、迟到 Promise / 超时 / 新旧 gate 隔离、真实 HTTP 状态与未配置保护、客户端断开传递、实例独立计数、两条半上传请求同时完成时只启动一条、上游预取消 / 大响应 / 错误类别，以及实际完整服务链 + 原稿 / MIDI / 区段 WAV 导出的精确保护回归。

0.13 静音 UI：配置未就绪 / 已配置未真实调用、密钥参数地址拒绝、不同服务状态地址拒绝、静态 404 说明、等待 / 取消 / 立即新请求、显式重试与转调后拒绝 / 撤销后冻结原轨道重试、模拟原始异常文本未展示、候选保留 / 应用 / 导出 / 撤销、检查停止和地址编辑中止两个真实慢速状态 GET；手机 390×844 对话框 x=12…372 / y=19…825、固定页脚可访问，桌面 1280×800。最终原始工程 816 音符 / 4 引用 / 练习 64…96 拍已还原，刷新后实际导出内容与 `long-song-demo.sprout` 完全一致；离线模式、quiet=true / hardwareAudioInitialized=false / playing=false。没有以这些检查宣称真实模型、音质或所有浏览器均已验收。

0.12 新增 24 项自动化：范围上下文 / 种子 / 可复现音符、五种范围与引用保护、全原稿精确一致 / 撤销资格、ID 中性 A→B 与不同原稿拒绝、安全元数据及校验包、批量一次事务 / 六版与字节上限 / 无自动淘汰、失败保留旧数据、双页 CAS / 排队 / 重新读取、一次移除撤销、损坏锁定 / 不可用存储 / 连接重开重试，以及真实三版 / 对比报告 / 模拟服务 / MIDI / 双 WAV 文件回归。容量、配额和损坏注入使用内存适配器，不代表真实磁盘故障已复现。

0.12 实际静音 UI：非法种子拒绝、三版一次持久化且工作区 816 不变、390×844 堆叠 A/B 和固定底部按钮（x=12…372 / y=19…825）、打开 B 只暂存 / 显式应用 734 / 旧候选全部过期 / 撤销恢复资格、改名与移除独立撤销、刷新后四版及名称恢复但不自动暂存或应用、不同原稿 / 相同候选拒绝比较、4+3 超容量整批拒绝、旧窗口在工程改变后拒绝、真实双页改名冲突与重新读取、独立候选库连接重开。只有一次自建 localhost 模拟 HTTP 请求，真实模型调用 0；设置已恢复离线。quiet=true / hardwareAudioInitialized=false / playing=false，浏览器错误 / 警告日志为空，未试听。

0.11 新增 18 项自动化：统一 64 小节契约、48 个长曲风格 / 调性组合、默认留白严格中性、独立重复及原空隙 / 引用保护、缩短的实际影响统计 / 范围处理、容量原子拒绝、晚段 Pattern / 和弦 / 整体复制、64 小节持音源与缓存、32 / 64 小节 MIDI 完整往返、晚段局部规则 / 模拟模型全局保护、视窗缩放 / 滚动 / 非法参数、有限钢琴缓冲区与绝对拍坐标、晚段练习及版本包、超过旧 600 KB 限制的本地 HTTP 模拟服务、6000 音符伪离线节点容量，以及真实四文件逐音 MIDI / PCM 回归。模型测试只用进程内替身或回环 HTTP，环境变量临时替换后恢复，没有真实密钥或付费调用。

0.11 实际静音 UI：8 → 32 默认留白仍 204 音符 / 4 引用，撤销后明确重复为 816；四段骨架与晚段练习；末段横向滚动后固定标题仍在同一 X 位置；第 27 小节双击新增实际拍 106.25 / 音高 66，所有原音符与无关数据逐项保持，撤销恢复；64 小节留白仍 816 音符、鼓末组 57–64、手机自动 8 小节视窗与边界裁剪报告；4 小节实际缩短至 131 音符后一次撤销恢复；旧长度预览在候选应用后拒绝覆盖；MIDI 真实导入 816/816 音符 / 32 小节及撤销，最终工程与导出基线完全相等，刷新后全部恢复。虚拟跟随走拍确认 quiet=true / hardwareAudioInitialized=false 且不增加工程 revision。Enter 工程名提交 / 一次撤销、数值视窗提交 / 非法恢复与整曲缩放实际通过。390×844 手机长度窗口边界 x=12…372 / y=33…811；1440×1000 桌面钢琴逻辑宽 8960（64 小节）但 Canvas 仅 883 像素。浏览器错误 / 警告日志为空；未试听声音，真实 64 小节满容量 WAV / 低内存手机渲染与音乐质量仍待进一步验收。

0.10 新增 19 项自动化：段落严格校验、两种骨架、标签与 MIDI 字节中性、伸缩与元数据保护、版本包往返、跨轨独立 / 共享复制与空白扩展、完整共享移动 IDs、空块 / 全轨碰撞与容量原子拒绝、跨边界持音保留、清空音乐 / 删除标签区别、共享切片独立化、过短片段拒绝、段落候选边界 / 全局 / 音色 / 源库保护、不变候选中性、离线范围与请求前模型校验、16 组风格 / 长度 / 骨架复制组合、真实静音浏览器四文件导出与逐音 MIDI / WAV 核验。

0.10 实际静音 UI：导入受控 4 小节七轨起点；骨架预览 / 应用不改音乐；复制目标标签碰撞拒绝；勾选共享与空白延长复制 73 音符；整体移动到第 7 小节保留 4 引用；设置练习范围不播放；段落局部规则候选 / 审核 / 应用（170 音符、仅局部 2 引用独立化）与一次撤销恢复；模型候选应用期间旧标签窗口写入拒绝；手机清空草稿 / 实际清空恢复为 131 音符，桌面一次撤销与刷新恢复 204 音符 / 4 引用 / 3 标签。390×844 手机窗口和固定页脚、1280×800 桌面无表单横向溢出；1440×1080 桌面密集行布局可同时看到示例七轨。所有下载经过回归核对，全程 quiet=true / hardwareAudioInitialized=false，无真实 LLM 调用，未做听感验收。

0.9 新增 18 项自动化：严格参数 / 零种子 / 四预设、三个范围 / 未知 IDs / 静音块、完全中性、力度边界与全部无关数据保护、稳定和弦松紧 / 不叠加、边界限制与持音保护、微偏移清除、部分起点量化、区域 / 长度 / 保留偏移越界整组拒绝、非相邻长持音重叠配对、仅目标前音缩短、同时起音 / 极短 / 范围外前音拒绝、缩短引起的音块尾部摇摆钳制释放、局部共享边界、密集 44850 对计数但只保存 30 对详情、保存包 / MIDI / 调度一致性、72 个风格 / 调性 / 长度组合下 288 个受控整理方案、真实四文件精确流水线回归。

0.9 实际静音 UI：非法力度拒绝、草稿 / 取消 / 中性重新打开、共享块局部力度 / 微时间整理与引用保护、撤销 / 重做 / 刷新保留、列表单音选择与仅单音清除、整轨 39 音符四页预览 / 翻页、键盘滑杆 80 → 81、旧窗口并发拒绝。测试工程真实验证重叠 1 → 0 对的前音缩短 / 撤销、范围外前音拒绝、完整对齐越界拒绝后降低到 50% 成功且长度不变，鼓入口与无声预览。390×844 手机单列滑杆 / 双列预设 / 固定页脚可访问，表格仅局部横向滚动，页面不横向溢出；1280×800 桌面和四文件实际导出核对。全程 `quiet=true`、`hardwareAudioInitialized=false`，错误日志为空，无人工音质试听或真实模型请求。

0.8 新增 17 项自动化：八音源参数 / 三预设 / 非字符串波形及非法字段拒绝、旧工程字段缺省保留、短音起音 / 衰减中松开与零持续包络、音符 / 混音 / 引用保护、版本包 / 转调 / 延长 / 离线生成保留、换乐器复原与鼓引用独立化、音色差异统计、模型音色保护、实际 DSP 参数与清理、全部音源硬边界 / 低采样率滤波界限、鼓长衰减噪声循环和鼓体端点、旧合成寿命、伪节点实时调度、安静预览无 AudioContext、伪离线参数 / 长释放尾音、模拟模型协议、真实四文件导出数据回归。DSP 路径用伪节点或 OfflineAudioContext，无硬件播放。

0.8 实际静音 UI：非法起音拒绝、草稿 / 取消保护、三角波应用、单步撤销 / 重做 / 刷新保留、Pad 长释放和军鼓预设、候选审核 / 应用保留音色并撤销恢复引用、恢复原始音色与撤销、换音源复原与撤销、旧窗口并发拒绝、越界音色文件导入拒绝 / 有效文件导入恢复。390×844 手机单列表单和固定页脚可访问，混音台按钮 / 编辑器顶栏无页面横向溢出；1280×800 桌面与四格式实际下载核验。`quiet=true`、`hardwareAudioInitialized=false`，浏览器错误日志为空，未进行人工音质试听或真实 LLM 调用。

0.7 新增 21 项自动化：源捕获/唯一实例 ID/跨音源关联、全引用传播、局部编辑/移动/裁剪/分割/普通复制/重复/显式独立化、源/缓存篡改拒绝、库容量/边界/鼓兼容、空白扩展、共享长度碰撞原子拒绝、删除保留实例、相同内容关联/显式替换、局部候选/转调保护、v3 保存包与 MIDI/调度单次展开、LLM 平铺传输与局部保护、候选关联差异、精确鼓音高和未知音源拒绝，实际三格式导出示例数据回归。

0.7 实际静音 UI：捕获并关联、两轨三引用、放置碰撞拒绝、共享加长/缩短拒绝、力度改动同步三块、局部三音符力度修改仅独立化一块、撤销/重做恢复引用、刷新保留源库/实例、删除源保留音符与撤销恢复、普通复制独立、显式独立化/撤销、不同内容关联默认拒绝/显式替换及撤销、鼓仅同种轨放置和共享新增精确 pitch 36 音符、局部编曲候选差异/应用/撤销、坏缓存实际文件导入拒绝、有效 v3 文件导入恢复以及实例虚拟走拍（quiet=true、hardwareAudioInitialized=false）。390×844 手机库与共享编辑窗口页脚可访问，长表格仅在局部水平滚动；1280×800 桌面无横向页面溢出。实际三格式下载经数值核对；全程安静、无真实模型调用。

0.6 新增 13 项自动化：范围/持音/微时间/定位计划、起始延迟不跳尾、循环时钟、空循环与超长后台延迟跳过、暂停/单次自然停止、待初始化播放取消、全部八音源硬截断、模拟声音节点下的真实调度路径、WAV 范围/默认整首与 MIDI 不受范围影响、工程范围缩短/扩展、独立复制/空白扩展/碰撞原子拒绝/元数据继承。声音路径只用伪 AudioContext 节点，不接硬件。

0.6 真实静音 UI：越界范围拒绝、设置不自动播放、虚拟走拍/暂停/停止、仅当前块循环、超过一遍时长仍位于窗口内、切换单次后自然结束；WebMCP 读取确认 `quiet=true` 且 `hardwareAudioInitialized=false`。连续复制碰撞/溢出提示、明确延长、新增三副本、整组撤销/重做、最后副本独立力度修改；刷新后范围与两步撤销/重做游标恢复、范围外定位拒绝。390×844 手机范围和复制窗口固定页脚可访问，无页面横向溢出；1280×800 桌面及完整工程/MIDI/整首/区段 WAV 实际下载核对，错误日志为空。未做真实声音试听或真实模型调用。

0.5 新增自动化：严格参数与零种子、144 个受控生成组合、固定种子的密度单调保留、复杂度/力度、最小声部运动、定时偏移与 MIDI、范围外保护、自定义音源/名称/混音/音块保留、音符差异配对，以及 LLM 参数传递/后处理/缺轨拒绝。真实静音 UI：预设、越界种子拒绝、参数保存刷新、生成候选与逐轨差异、应用/放弃/撤销、同种子重复零差异、当前块候选保护、390×844 单列调色盘及固定页脚、滑杆键盘调整/取消、1280×800 桌面、实际三格式下载与工程/MIDI/PCM 数据核对。手机无页面横向溢出，浏览器错误日志为空。真实 LLM 与硬件试听仍未测试。

浏览器实际验证：工作台显示、首次播放/时间线、鼓编辑、钢琴卷帘双击删音符、混音台切换、候选生成/应用/撤销、WebMCP 有效/无效输入、模型未配置时的明确错误、实际 WAV/MIDI 下载及窄屏布局。用户要求保持安静后，全部继续检查在 `?silent=1` 下进行，未再试听声音。

0.2 新增实际静音 UI 验证：分割、数值裁剪、鼠标拖动（音符跟随）、独立复制、块静音、鼠标右边缘裁剪、撤销/重做、创建空音块、当前音块候选通过 WebMCP 生成/应用、工程导出与刷新恢复、390×844 移动布局（无页面横向溢出）、1280×800 桌面布局、标准 MIDI 文件导入报告/确认/撤销。

0.3 新增实际静音 UI 验证：旧工程迁移、命名保存点、版本预览、86 → 96 BPM 编辑保存后刷新恢复、刷新后撤销/重做、恢复前留旧版、候选应用前备份、MIDI/工程导入前备份、双页 100/110 BPM 冲突保护、另存副本与读取新版本、恢复原版、390×844 版本窗口和菜单访问、1280×800 桌面预览，无页面横向溢出、浏览器错误日志为空。未进行硬件声音播放。损坏/配额失败/重试/保存顺序/保留上限使用模拟存储适配器注入故障的单元测试，不代表实际浏览器磁盘故障已复现。

0.4 新增实际静音 UI 验证：列表勾选、三音符批量移位/移调/力度设置、独立粘贴、批量删除/撤销与版本记录、越过音块边界拒绝、鼠标整组拖动、真实框选两音符、键盘方向移动、⌘A/⌘D 独立复制、触屏尺寸下的列表全页选择、和弦预览/写入/碰撞/备份替换/撤销、刷新保留、390×844 手机与 1280×800 桌面布局、WAV/MIDI/工程实际下载。自动化环境拦截 C/V 作为浏览器虚拟剪贴板操作，因此这两个快捷键未通过端到端验证；对应应用内复制粘贴按钮流程已经验证。

0.4 示例文件：7 轨 / 243 音符；原有六轨的旧音符、音块和混音设置全部保留，新增 3 个独立复制音符与 16 个 Pad 分解音符。MIDI 解码为 235 个可发声音符（排除原有静音块的 8 个音符），与工程计算一致。实际离线 WAV：双声道、44100 Hz、23.8256 秒，峰值 0.497、RMS 0.101、削波样本 0；没有播放声音，音质仍待白天人工评价。

和弦窗口的并发保护也通过实际 WebMCP 验证：窗口打开期间，另一个操作应用鼓轨候选后，旧窗口拒绝写入并要求重新打开，没有覆盖新工程。输入长度时音符预览实时更新；最新界面的定位所选功能已验证。浏览器错误日志为空。

0.2 实际离线 WAV：双声道、44100 Hz、23.8256 秒，峰值 0.497、RMS 0.100、削波样本 0；未进行声音播放。

0.1 实际导出的 8 小节 WAV：双声道、44100 Hz、16-bit，约 23.83 秒；峰值 0.497、RMS 0.103、削波样本 0。音质评价仍需白天人工试听。

## 已知边界

- 最多 16 条轨道；标准 MIDI 最多 15 个非鼓通道，超出时明确报错。
- 最长 64 小节；每轨最多 4000 / 工程合计 12000 音符。离线 WAV 上限 12000 调度音符，工程导入最多 12000 音符/3 MB；模型完整返回仍限 5000 音符。长曲渲染仍受本机内存与浏览器限制。
- WAV 包含混音、主音量、静音和独奏；MIDI 保留所有轨道及未被块静音的音符；轨道 M/S 不影响 MIDI，接收 DAW 使用自己的音源。
- 钢琴卷帘以鼠标编辑为主；触屏可选择音符后用数值修改，复杂触屏编辑仍需增强。
- 暂无 VST/AU、录音、音频剪辑、时间拉伸、歌词/人声生成、母带、`.flp` 兼容或云同步。
- 已支持独立音块区域、显式共享 Pattern 引用与同轨音符多选；暂不支持跨轨拖动、同轨音块叠放、音块循环拉伸、音块多选或跨轨音符多选。
- Undo/Redo 内存最多 45 步；刷新最多各 8 步且总量受限。工程、版本和应急记录仍可能受浏览器配额/回收影响，不是永久备份。
- 引导和界面适合新手，但这仍是首版原型，不是经过音乐人长期验证的专业 DAW。
