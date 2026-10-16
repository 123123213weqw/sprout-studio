# Current delivery — v0.27, 2026-10-15

A six-call real V4.1 Flash batch completed on V100 under a fixed request/token cap with no retries. All six responses preserved edit scope, globals and sampled voices. Five passed all case-specific measured musical requirements; the ambient case left kick/snare empty. Exact clip/drum timing, full and section harmony, shared-Pattern preservation/detachment, held samples and scope pressure were exercised.

The unedited 80-note numeric-harmony result meets all specified anchors and hats, without the earlier manual bass correction. All six MIDI/WAV exports are saved; all mixes and eight stems are non-silent/unclipped. The batch used 23,441 reported tokens; cumulative recorded requests: nine, 30,751 tokens. 630 automated tests pass without paid calls. No subjective listening or new UI verification is claimed. Further paid tests are stopped at the declared batch cap.

---

# Model clarification — v0.26.1, 2026-10-15

The user explicitly selected DeepSeek V4.1 Flash. Official `/models` metadata and documentation confirm its API ID is `deepseek-flash`, already used in all three recorded composition tests. The V100 bridge was restored and the model is now pinned against accidental Pro overrides. 612 automated tests pass. No new generation calls, credential copying, UI redesign, publishing or Git push occurred.

---

# Current delivery — v0.26, 2026-10-15

- Three real DeepSeek calls completed on V100: 62-note and 83-note eight-instrument arrangements, then an isolated flute edit through the Mac loopback API/SSH bridge (79 total notes, seven other tracks unchanged).
- The key stayed in the existing V100 key file. No key was copied to the Mac, output artifacts or browser. The bridge uses loopback listeners, verified SSH host keys and no agent forwarding; it is not a public deployment.
- A one-command / macOS launcher starts source sync, the remote service and the local app; startup makes no model calls. Existing offline mode and explicit candidate Apply remain intact.
- Actual MIDI/WAV/stems are saved. All eight stems are non-silent and unclipped. The model still missed one explicit bass-root instruction; no perfect-compliance or subjective-quality claim is made.
- Browser screenshot audit/UI refinement remains blocked. The user asked to continue independently; paid calls are stopped at three, and no repeated setup question is required.

The historical entries below record earlier delivery states, not the current live-test status.

---

# Current delivery — 2026-10-15

The user has authorized a real DeepSeek composition test. v0.25 adds the bounded adapter, exact-target note validation, sample/mix preservation, a single-call CLI test fixture and sanitized response receipts. 593 automated tests pass. These use synthetic responses, not a live model result.

Still pending: add the local DeepSeek API key, run the authenticated four-bar test, inspect/audition its output, and refresh the in-app error page for screenshot-led UI refinement. The interface pass must follow the reasons and acceptance criteria in `DESIGN-DECISIONS.md`; no visual redesign was performed or verified in this delivery. The project remains local and ongoing, not a completed FL Studio replacement.

The historical log below predates the current authorization and language preference.

---

# 持续开发记录

开发按用户指令继续推进；单次迭代不代表整个工作站已经完成。2026-10-13 本轮继续本地版，未同步在线 Site。用户已取消旧静音限制，允许声音；页面仍不自动播放。真实模型调用等待明确配置，不使用已有密钥，不调用付费服务。

## 已交付

### 0.1 — 工作台与编曲闭环
- [x] 原创暗色 DAW 工作台、钢琴卷帘、鼓步进器、混音台
- [x] 四种规则编曲风格、候选审核与撤销
- [x] MIDI/WAV/工程导出、本机自动保存、静音模式
- [x] 服务端 LLM 兼容适配器，模拟响应测试；真实模型未接入

### 0.2 — 独立音块与 MIDI 导入
- [x] 音块移动、独立复制、裁剪、延长、分割、改名、删除、块静音
- [x] 鼠标拖拽、键盘移动、数值编辑、碰撞保护
- [x] 音块静音同时进入实时调度、离线 WAV 和 MIDI
- [x] 当前音块候选合并，保护其他区域和全局设置
- [x] v1 → v2 无长音符损失迁移，离开页面时冲刷待保存工程
- [x] SMF format 0/1 导入与明确降级报告
- [x] 39 个自动化测试；真实 UI 片段编辑、MIDI 导入、WAV/工程下载验证

### 0.3 — 本机工程版本与恢复
- [x] IndexedDB 原子事务保存，提交成功后才报告已保存
- [x] 命名保存点、自动版本、恢复预览、版本下载
- [x] 导入/新建/换风格/应用候选/恢复与批量删除前保护性备份
- [x] 校验码、防损坏回退、损坏记录原始下载
- [x] 应急日志、刷新后有限撤销/重做，明确容量/数据丢失边界
- [x] 双页版本 CAS 冲突保护、读取新版本、保留两版接管
- [x] 不可用存储重试，失败时保留内存并提示文件导出
- [x] 56 个自动化测试；实际 IndexedDB 保存/恢复、双页冲突和移动布局静音验证

### 0.4 — 新手音符编辑与和弦输入
- [x] 同轨音符多选：Shift、拖框、触屏选择模式、当前块 / 全轨 / 列表
- [x] 整组鼠标移动 / 调整长度、键盘移动、独立复制、应用内粘贴
- [x] 移调 / 长度 / 力度批量数值操作、选区量化与原子边界拒绝
- [x] 调内三/七和弦、转位、音区、四和弦进行、上下分解与静音预览
- [x] 追加碰撞检查、保护性范围替换、范围外长音片段保留
- [x] 高级参数渐进展开、手机布局、可访问分页列表与定位所选
- [x] 67 个自动化测试；真实 UI / 导出验证与七轨示例工程
- [ ] C/V 快捷键真实浏览器人工验收（自动化工具拦截剪贴板；按钮流程已验收）

### 0.5 — 可控编曲与候选差异
- [x] 三种新手预设、密度 / 复杂度 / 演奏能量 / 人性化参数
- [x] 三种调内进行、转位声部连接搜索、稳定事件随机值与变奏种子
- [x] 名义网格与微时间分离，MIDI / WAV / 实时调度统一实际时间
- [x] 原有乐器 / 名称 / 混音 / 音块布局保护，显式及描述推断的局部全局保护
- [x] 候选逐轨音符差异、全局变化、参数来源及模型软约束说明
- [x] LLM 参数协议与服务端范围保护 / 能量 / 人性化后处理；仅模拟调用
- [x] 81 项自动化测试、真实静音桌面与手机 UI、三格式实际导出核验

### 0.6 — 区段练习与连续编排
- [x] 可保存 / 撤销的练习时间窗、选当前块套用、全曲恢复与范围外定位保护
- [x] 单块独立预览、循环 / 单次、暂停 / 停止 / 编辑后的范围游标保持
- [x] 边界持音起音 / 截断、所有声音源硬终止边界、后台过期周期跳过
- [x] 安静模式纯虚拟时钟，不创建或恢复实时 AudioContext
- [x] 1–32 个独立连续副本、显式空白延长、碰撞 / 上限整组拒绝、一次撤销
- [x] 工程快照导出、可选练习段落 WAV、MIDI / 工程始终完整保存
- [x] 94 项自动化、实际虚拟走拍与手机 UI、独立编辑和完整/区段导出核对

### 0.7 — 共享 Pattern 库
- [x] v3 相对源乐句 / 稳定引用实例 / 绝对音符缓存与严格一致性核验
- [x] 从当前块捕获、可选源关联、共享或独立跨旋律音源放置、同种鼓兼容
- [x] 库内显式共享编辑、受影响实例清单、静音预览与应用前备份
- [x] 分页数值音符编辑、整体移调 / 力度、增删、显式裁尾与长度碰撞原子拒绝
- [x] 局部编辑自动独立化、显式独立化、普通复制 / 连续复制保持独立
- [x] 默认匹配内容关联 / 明确替换、删除源保留所有实例音符、可撤销 / 刷新恢复
- [x] LLM 平铺传输、源库保护、候选独立化差异、MIDI / 调度 / WAV 不重复展开
- [x] 115 项自动化，真实桌面 / 手机静音 UI、坏文件导入拒绝、三格式数值核验

### 0.8 — 可保存的乐器音色与包络
- [x] 八音源适用参数、中文三预设、基本滑杆与高级波形 / Q / 衰减
- [x] 草稿 / 取消 / 一次应用、静态包络、非法参数与旧窗口并发拒绝
- [x] 短音提前释放的连续线性 ADSR，实际鼓衰减 / 频率 / 鼓体，统一实时和离线合成
- [x] 旧工程缺省精确保留原合成、显式复原、换音源复原及鼓引用独立化
- [x] 版本 / 撤销 / 刷新保存，音符 / 混音 / 共享源和其他轨道保护
- [x] 候选音色差异、前后端模型合并保留；MIDI 明确不带自定义音色
- [x] 配置相关 WAV 长释放尾音，安静预览完全不创建实时音频上下文
- [x] 132 项自动化，真实桌面 / 手机静音 UI、并发与坏文件拒绝、四文件数值核验
- [ ] 白天人工评价音色和预设（夜间未试听，不以 PCM 检查代替听感验收）

### 0.9 — 演奏整理与同音高重叠保护
- [x] 所选音符 / 当前块 / 全轨三个明确范围，静音块仍可编辑
- [x] 四个新手预设、比例力度 / 稳定正负变化、保留 / 清除 / 重算微偏移
- [x] 原本同起点的和弦共用松紧、边界限制、0–100% 起点对齐且不量化长度
- [x] 实际时间同音高配对、仅提示或显式缩短目标前音、范围外 / 极短 / 同时起音原子拒绝
- [x] 分页逐音前后与毫秒差、共享独立化预告、草稿 / 取消 / 中性打开 / 并发保护
- [x] 应用前旧版备份、一次撤销 / 刷新、声音 / 混音 / IDs / 源库和其他区域保持
- [x] 150 项自动化、真实桌面 / 手机静音 UI、边界工程 / 精确四文件流水线和 MIDI 核对
- [ ] 音乐人白天人工检查“自然 / 整齐”的听感，未以自动化替代音乐质量评价

### 0.10 — 歌曲段落与跨轨整体编排
- [x] 可选完整小节段落、两种明确只改标签的新手骨架、时间线共用滚动与命名设置
- [x] 全轨独立 / 显式共享复制、完整共享移动 IDs、空白延长和全轨 / 标签碰撞原子拒绝
- [x] 边界音块与持音切片、范围外双侧保留、过短片段整组拒绝、独立片段预告
- [x] 只删标签 / 清空段落音乐分开、静音状态 / 音色 / 混音 / 源库 / 练习范围保护
- [x] 静音草稿 / 影响预览 / 应用前版本备份 / 一次撤销 / 刷新 / 旧窗口并发拒绝
- [x] 段落练习与局部离线候选、前后端 LLM 段落协议 / 请求前校验 / 局部合并，仅模拟响应
- [x] 169 项自动化、实际桌面 / 手机静音 UI、七轨 204 音符四文件流水线 / MIDI 逐音核验
- [ ] 跨界长音重新起音的听感与段落衔接仍待白天人工检查，不宣称无缝音频编辑

### 0.11 — 64 小节工程与可滚动缩放时间线
- [x] 4/8/16/32/64 统一长度契约、默认留白 / 明确独立重复、实际影响预览与容量整组拒绝
- [x] 缩短先说明音符 / 音块 / 段落 / 练习范围变化、应用前备份、一次撤销与旧窗口并发保护
- [x] 自动 / 整曲 / 8 / 16 / 32 视窗、滚动 / 数值 Enter / 滑杆、固定标题、段落 / 音块查看不播放
- [x] 默认关闭的视窗跟随、仅视窗宽的钢琴位图、滚动后的绝对拍编辑与紧凑鼓分页
- [x] MIDI 到 64 小节、晚段库放置 / 和弦 / 段落整体编排、LLM 契约及 3 MB 请求上限
- [x] WAV 与工程同为 12000 音符容量，长渲染耗时 / 内存说明；6000 音符仅伪节点自动化验证
- [x] 187 项自动化、真实手机 / 桌面静音 UI、七轨 32 小节 816 音符四文件及逐音 MIDI / PCM 检查
- [ ] 真实 64 小节满容量 WAV、低内存手机长渲染及人类音乐质量验收，夜间不试听

### 0.12 — 持久候选架与同稿三版比较
- [x] 完整原稿 / 候选 / 范围 / 描述 / 参数保存，离线及显式服务单版接入，不存密钥或端点
- [x] 同稿 A/B/C 本机规则三版、明确预设 / 种子 / 沿用和声，五种范围共用保护，无模型批量调用
- [x] 精确原稿资格、打开与应用分离、应用前备份 / 工程撤销、备份期间切换与旧窗口保护
- [x] A→B ID 中性逐轨差异、不同原稿拒绝、JSON 报告、候选工程下载，不自动评分或试听
- [x] 独立 IndexedDB 原子批量事务、六版 / 8 MiB 全组拒绝、无自动淘汰、校验损坏锁定与重试
- [x] 多页 CAS、改名、只移除候选及页面内一次撤销、刷新持久化、手机可滚动对比与固定操作区
- [x] 211 项自动化、真实双页 / 刷新 / 过期 / 容量 / 静音 UI，三版 + 报告 + MIDI / 双 WAV 核验
- [x] 自建回环模拟 HTTP 前端单版保留与局部两引用独立化；真实模型调用 0，恢复离线并停止服务
- [ ] 批量真实 LLM、跨设备候选同步、历史项目分类与人类音乐质量评价，未当作已实现

### 0.13 — 可诊断、可取消的服务接入
- [x] 显式只读 GET 状态、无工程 / 无厂商请求、配置无值返回、协议 / 同源 / 路径 / 容量严格检查
- [x] 三步设置、检查有效与实际模型验收分开、无状态兼容服务仍可手动生成，静态版限制明确
- [x] 可见等待时间 / 范围、停止等待、迟到结果 / 旧 finally 隔离、页面退出与配置变更取消
- [x] 无自动重试、显式原稿 / 原范围 / 原参数重试、工程或配置变化拒绝，撤销后恢复资格
- [x] 错误类别 / 上游异常脱敏、UTF-8 有界流、状态超时 / 取消 / 地址编辑 / 窗口关闭隔离
- [x] 本机 HTTP 断开传递 AbortSignal、实例独立并发、请求体完成后再检查位置、导入不加载 .env
- [x] 233 项自动化、真实静音桌面 / 手机、完整适配器模拟链、真实取消与状态 GET、四文件导出核验
- [ ] 真正厂商认证 / 额度 / 模型编曲质量、异构服务适配与商业服务的取消计费语义，仍待明确配置验收

### 0.14 — 跨工程乐句文件与显式收藏复用
- [x] 单句 / 多句 .sprout-patterns 导出、参考信息、分页选择与静音音符图；不带音色 / 实例 / 端点
- [x] 独立乐句文件及完整 v3 工程库提取、全文件严格校验与 UTF-8 字节上限
- [x] 内容去重默认跳过、明确新副本、重名后缀、新源 / 音符 IDs 与碰撞拒绝，旧引用绝不重绑
- [x] 原子库容量与完整工程保存上限、只追加源库 / 不放置 / 不重启播放、一次撤销 / 普通本机保存
- [x] 异步文件读取与工作区 / 窗口隔离、旧确认拒绝、手机可滚动预览与固定操作区
- [x] 258 项自动化、实际坏文件 / 分页 / 转义 / 刷新 / 撤销、另一工程 ID 的三源导入与三轨明确放置
- [x] 实际收藏 / 工程 / 不变的 816 音符 MIDI / 新 30 音符 MIDI / 区段 WAV 逐项核验，最终原稿还原
- [ ] 浏览器以外的文件系统收藏索引、每句独立来源元数据、智能调性适配与音乐人听感评价，未当作已完成

### 0.15 — 批量 Pattern 编排与所选引用管理
- [x] 默认一份、明确 1–32 份 / 起点间隔 / 全部位置预览、同乐器后备目标与鼓种限制
- [x] 明确共享或独立副本、空 / 静音块占位、碰撞 / 数量 / 音符 / 完整 3 MB 保存原子拒绝
- [x] 显式空白延长至最多 64 小节、其他轨 / 旧 IDs / 音色 / 混音 / 标签 / 范围不变、整批一次撤销
- [x] 当前源引用八条分页、默认全不选 / 跨页保留、所选静音 / 取消静音 / 独立化 / 删除，不涉及普通副本
- [x] 管理前备份 / 后确认、旧工作区与窗口拒绝、取消不改、无变化禁用、查看位置只定位
- [x] 独立化保持音符 IDs 与运行中的虚拟时钟；静音 / 删除正常刷新调度，不自动开始播放
- [x] 手机工程菜单撤销 / 重做、390×844 固定确认区与 1280×900 桌面静音 UI
- [x] 286 项测试（新增 22 计划保护 + 6 真实下载回归）、十份 / 三轨 / 独立副本 / 跨轨所选实际工程
- [x] 实际 72 音符 MIDI 与区段 WAV / PCM 验收、实际旧窗口拒绝 / 刷新一致、原 816 音符工作区与候选恢复
- [ ] 节奏 / 调性变换、段落衔接与受控变奏、来源追踪、真实模型与人工听感，未借批量复制宣称已完成

### 0.16 — 当前音块的节奏与音高变换
- [x] 新手草稿预设、×½/×1/×2 同步块长与音符、区间倒序而非音频倒放、−24…+24 半音
- [x] 六调全音域最近音显式吸附、等距较低、全局调性不变、重叠仅提示、鼓音高锁定
- [x] 微偏移随倍数 / 方向、保留或清除、四位小数 / 最短音符 / 边界 / 空块碰撞 / 保存预算整块拒绝
- [x] 显式空白延长最多 64 小节、无 ripple、音符 IDs / 数量 / 力度 / 其他块 / 全局与源保护
- [x] 逐音前后与实际时间差分页、仅变化共享块独立化、应用前备份、旧窗口 / 中性 / 取消保护
- [x] 手机完整页脚、桌面表单无溢出、时间线粘性标尺滚动避让与真实命中检查
- [x] 313 项测试（新增 22 纯计划 + 5 真实文件回归）、组合十六音符 / 鼓六音符 / 晚段八音符实际下载与撤销
- [x] 实际 816 音符 MIDI / 43 事件区段 WAV 逐音和 PCM 核验，刷新音乐字节一致，最终原稿恢复
- [ ] 源调性分析、和声改写、共享源批量变换、智能衔接 / 变奏、真实模型与人工听感未完成
- [x] 0.17 修复自动保存提交前即时刷新的有界历史交接，新增明确应急 / 事务提交反馈

### 0.17 — 即时刷新历史交接与真实保存反馈
- [x] format 2 同步应急工程 + 两个有界有序栈，旧 format 1 兼容，历史损坏单独降级而非丢音乐
- [x] 同音乐不同历史也恢复、旧待完成保存只清理匹配意图、恢复页只接管读到的那条应急记录
- [x] 跨页历史-only 记录保护、CAS 仍拒绝旧页覆盖、包装读取预算与双配额失败保留旧记录
- [x] 配额不足只保音乐时明确历史丢失；失败处理不用过时操作前快照回写新工作区
- [x] 应急写入与事务提交分开提示，桌面 / 手机版本窗口显示实际刷新历史数量
- [x] 346 项测试（新增 30 纯应急时间线检查 + 3 真实下载文件回归），90 次编辑 / 撤销 / 重做 / 刷新链
- [x] 实际预提交即时刷新 / 相同音乐新重做 / 重做后刷新 / 手机两次撤销刷新 / 正常提交恢复，原稿字节一致
- [x] 0.18 多个真正独立工程、可逆归档与工作区记录估计用量
- [ ] 用户可见历史清理、外部可选备份、长曲历史压缩与更公平的两栈容量保留仍待实现

### 0.18 — 独立作品库与每页工作区身份
- [x] 侧栏 / 工程菜单入口，空白 / 四规则风格 / 8、16、32 小节明确起点
- [x] 保存当前后切换、创建数据与目录单事务、验证目标 / 两级 CAS 后选择，上次打开不提前改变
- [x] 音乐 / 两栈历史 / 保存点 / 应急 / 更新频道隔离；副本与文件导入新标识、不带旧历史
- [x] 旧 active / 应急格式 / 全局旧工程迁移兼容，其他作品缺失不错误迁移旧歌曲
- [x] 可逆归档 / 恢复、12 项含归档上限、序列化记录用量、无自动淘汰、坏行原记录下载
- [x] 每页本机工作区 URL，另一页选择后刷新不串换；地址不是云分享，未知 / 归档回退说明
- [x] 旧窗口 / 生成 / 编辑并发保护，切换停止走拍且不创建音频硬件；候选架和配置仍共用且边界明确
- [x] 393 项测试（29 库 + 6 切换 / 地址 + 4 起点 + 8 实际文件新增），故障只用测试适配器
- [x] 实际即时刷新 / 手机历史 / 独立保存点 / 双页各作用域 / 归档恢复 / stale 拒绝与原稿字节恢复
- [x] 实际副本块静音 MIDI 800 音符，原 816 音符 / 四引用保持；桌面 / 手机静音工程库截图
- [ ] 历史主动清理 / 全库便携备份 / 文件系统索引 / 云同步 / 长历史压缩，不把本机工程库当永久备份

### 0.19 — 可保存与搬运的音色收藏
- [x] 草稿命名收藏、跨本网站工程共用、默认适用筛选 / 全库禁用 / 四项分页，不自动应用或播放
- [x] 五旋律音源参数复用、native 目标层语义、同种鼓限制、精确原始 null / 原音源限制
- [x] 草稿 / 单份 / 未归档库便携文件、不带歌曲 / 混音 / 服务信息、全文件严格校验与选择
- [x] 内容去重含归档、明确新副本、重名后缀、独立新 ID、整组容量 / 冲突原子拒绝
- [x] 独立 IndexedDB / CAS / 校验码 / 不重置坏数据 / 重试，32 项含归档 / 256 KiB / 无自动淘汰
- [x] 改名 / 可逆归档恢复不改歌曲，旧音色窗口拒绝，完整 3 MB 音乐保存预算保护
- [x] 425 项测试（新增 24 核心 + 8 实际下载），真实跨 Pad / House / 原始缺省 / 双页冲突 / 手机操作
- [x] 实际 816 音符 MIDI 中性与 204 事件离线区段 WAV 核验、原稿字节恢复、桌面 / 手机确认区完整
- [ ] 商业采样 / 插件预设 / 效果链 / 云库 / 音色人类听感不当作已完成；演奏参数复用与智能衔接继续

### 0.20 — 段尾现有鼓轨受控过门
- [x] 三种中文规则鼓型、最后 1 / 2 小节、现有鼓轨选择、能量与稳定力度种子
- [x] 静态十六分网格 / 块静音斜纹 / 新增移除 / 切片 / 新块 / 共享独立预告，无自动播放
- [x] 窗外长音片段保留 / 新 ID / 明确偏移限制 / 过短拒绝，原块布局静音保持、变化共享块局部独立
- [x] 空白默认拒绝、明确新建独立不静音音块、碎隙与边缘 / 全部保存容量原子拒绝
- [x] 备份后一次应用撤销、revision / 段落 / 窗口保护、实际新候选后旧草稿拒绝
- [x] 457 项测试（新增 25 核心 + 7 实际下载），桌面 / 手机 / 显式补块 / 两步恢复与原稿刷新字节一致
- [x] 实际 828 音符 MIDI / 216 事件区段 WAV / 24.7456 秒 / 削波 0，保留旋律与四引用
- [ ] 旋律变奏 / 和声分析 / 自动衔接 / 共享源批量变换 / LLM 音乐质量 / 白天听感仍未完成，不将规则过门当智能编曲

## 下一阶段优先级

1. **Pattern 编排深化**：旋律受控变奏、共享源变换与调性分析；已有段末所选鼓轨规则过门与明确空白补块，不等同于自动和声衔接；当前块节奏 / 音高 / 最近调内音显式变换、批量放置与所选实例管理、外部乐句文件复用已实现，索引和每句来源仍可深化，保持共享 / 局部边界清晰。
2. **音乐可控性深化**：生成后声部连接 / 和声变换、演奏调整可复用设置与恢复原基线；已有音色收藏跨轨 / 跨工程 / 文件搬运，后续深化效果与可控音源；白天再人工评价音质和自然度。
3. **真实 LLM 质量**：明确配置后的真实调用验收、更多服务适配、局部结构约束、多版质量评估、长曲分段生成；配置检查与真实质量验收不能混为一谈。
4. **编辑与播放深化**：跨轨选择的清晰边界、完整键盘操作、区段交叉淡化 / 尾音策略、进一步优化长曲密集编排与低内存渲染；需要保持安静时只做静音调度或离线文件验证。
5. **工程可靠性与库扩展**：管理历史与真实磁盘用量、全库便携备份、长曲历史压缩、可选择的外部备份；已有独立作品库 / 可逆归档 / 估计记录用量 / 每页身份 / 有界即时刷新与明确保存反馈；不把本机版本当云备份。

## 不把这些当成已实现

VST/AU、录音/音频轨、`.flp` 兼容、母带、人声/歌词生成、智能长曲分段生成、速度地图、云同步和专业音质尚未实现。普通音块仍可独立编辑；共享引用由 Pattern 库显式建立。在线站点仍是无密钥静态版。

### 0.21 — 共享源乐句变换（本地实现，包含在 0.22）
- [x] 倍速、倒序、移调、六调内吸附与微偏移处理，全引用同步
- [x] 全实例碰撞、边界、64 小节 / 3 MB 容量预算与旧窗口拒绝
- [x] 源 / 缓存 IDs、实例起点与链接保留，保护性备份、一次撤销
- [x] 桌面 / 手机 / 八引用分页 / 尾部延长与实际文件验证，历史 490 项检查通过

### 0.22 — 克制的本地工作台
- [x] 中性深灰、低饱和显示颜色、移除宣传式助手标题与装饰卡
- [x] 低频编排 / 音块 / 音符工具折叠，原有操作保持可达
- [x] 专注模式与独立本机视图偏好，刷新恢复，不修改歌曲或历史
- [x] 声音按钮明确开 / 静音状态，同步 URL，启动脚本取消强制静音链接
- [x] 手机实际批量和复制 / 粘贴窗口，修复移出容器后的事件委托问题
- [x] 实际 `.sprout` 原稿逐字节保持，MIDI 816 音符保持；候选差异审核后取消
- [ ] 真实配置下的 LLM 音乐质量与端到端联调
- [ ] 真实人工听感、更多屏幕尺寸 / 高倍率缩放 / 屏幕阅读器验收

### 0.23 随包采样乐器
- [x] 立式钢琴八音区双力度、管弦底鼓双力度、军鼓双力度、短击镲单档
- [x] CC0 原始来源固定提交、完整许可与原说明、21 文件原始及处理后校验码
- [x] 新建空采样轨和已有兼容轨来源切换、可调音量 / 余音或门限时长 / 低通
- [x] 加载与校验后保护性备份、单次撤销、取消 / 过期窗口 / 3 MB 容量保护
- [x] 真正 AudioBufferSource、最近根音变速、双录音力度平滑混合、自然尾长与边界截断
- [x] 实时 / OfflineAudioContext 共用采样路径，失败明确报错不偷偷回退合成
- [x] 保存编号和参数、MIDI 钢琴 GM 提示、老工程合成设置保留、模型与局部编曲保护
- [x] 546 项自动化，桌面 / 手机 / 刷新 / 新建撤销 / 合成恢复 / 旧窗口拒绝 / 实际三格式下载
- [x] 独立演示副本 816 音符 / 四引用完整还原，原稿逐字节不变；区段 WAV 削波 0
- [ ] 更多弦乐 / 吉他 / 贝斯 / 真正踩镲、任意用户采样导入与多音区编辑
- [ ] 踏板 / 循环延音 / Round Robin / 完整 SFZ 与真实人工音质评价

### 0.24 八类真实音色覆盖
- [x] 八类音源均有采样选择，12 预设 / 84 WAV；保留全部 0.23 录音与经典预设
- [x] 14 根音双力度钢琴、12 根音低音提琴、10 根音长笛、13 根音大提琴、12 根音竖琴
- [x] CC0 架子鼓底鼓 / 双力度军鼓 / 真正闭合踩镲，不再只用短击镲替代
- [x] 新素材浮点归一后 PCM16、同根音两力度共用系数、原数字 SFZ 音高中心 / 校验码溯源
- [x] 长笛和弦乐处理过的 120 ms 交叉淡化循环、明确松开余音、循环边界与停止清理
- [x] 整首音色预览 / 校验 / 备份 / 单次原子替换，已有推荐参数保留，取消 / 过期 / 3 MB 保护
- [x] 每轨来源 / 新建空轨 / MIDI GM 提示 / 八类重新导入，实时与 WAV 共用路径
- [x] 570 测试；实际八轨 819 音符 MIDI，原 816 音符 / 四引用保持，刷新后演示字节一致
- [x] 实际长音 7–9 秒仍有音频，两份 WAV 削波 0；手机长列表滚动且不越出对话框
- [ ] 人工音乐人听感、踏板共鸣 / 完整轮换、多档表现力、更多吉他 / 电贝斯与开镲
- [ ] 手机低内存和满容量密集音符硬件验收；这一轮不扩展混响 / EQ / 插件效果链

## 0.28 — recorded acoustic alternatives

- Completed: microphone archtop guitar with four dynamics and two recorded takes, solo violin with two dynamics, clarinet with three dynamics, explicit longer previews, compatible MIDI hints, bounded decoded-cache eviction, preservation of sampled voices during bulk fill, and eight actual offline audio examples.
- Verification: 655 tests pass, legacy recording bytes unchanged, no new model calls.
- Remaining: subjective listening feedback, true legato/release articulations and screenshot-led visual QA. Not a complete professional virtual-instrument library.

## 0.29 sound library breadth

- Delivered: 179 fixed playable presets covering 27 categories; 128 soundbank programs, 36 original EDM patches and all fifteen prior recording presets. Search/category filtering, bounded results, source provenance labels and compatible source groups reuse the existing interface.
- Verification: 688 automated tests, every preset offline-rendered, two authored genre sketches, old PCM unchanged and two byte-exact old WAV replays.
- Still outside scope: a complete vocalist/singing model, every commercial instrument/plugin, SF2 controller parity, guitar fingering/true legato and fresh screenshot/subjective listening QA.
