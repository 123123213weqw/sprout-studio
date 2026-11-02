# Sprout编曲服务协议 v1

适用于 0.13.0。网页连接的是 **Sprout编曲服务**，不是模型厂商的 Chat Completions 接口。本仓库的 `server.mjs` 负责工程校验、调用模型和受限合并；`llm.mjs` 是服务端的兼容接口适配器。在线 Site 只发布静态网页，不包含这个 Node 后端或任何模型凭据。

## 给初次接入的用户

1. 本机运行源码版时，复制 `.env.example` 为 `.env`，填写自己的 `LLM_API_URL`、`LLM_MODEL`；服务需要鉴权时才填写 `LLM_API_KEY`。重启 `npm start`。
2. 网页“创作助手设置”选“我的 LLM 服务”，保留 `/api/compose` 和 `/api/llm/status`。模型名称可以留空，使用服务端默认值。
3. 点“检查配置（不调用模型）”。它只检查协议和配置格式，**不验证真实认证、额度、可用性或音乐质量**。保存设置也不会生成。主动生成后，先审核候选，再决定是否应用。

密钥只留在服务端；不要放进网页、查询参数、工程文件或 Git。本次开发没有读取现有密钥，也没有调用真实模型。

## POST 编曲

默认地址：`/api/compose`，请求类型 `application/json`。

| 字段 | 约束与意义 |
| --- | --- |
| `prompt` | 非空字符串，最多 1,600 个 JS 字符；描述希望怎样编曲。 |
| `project` | 完整Sprout工程。当前网页先把 v3 共享 Pattern 展开为 v2 绝对音符工程，再发送；输入仍包含音块、音色和段落信息。服务端按 `validateProject` 严格校验。 |
| `scope` | `all` / `selected` / `drums` / `section`，省略为 `all`。 |
| `selectedTrackId` | `selected` 范围的已有轨道 ID。 |
| `clipRange` | 可选 `{start,length}`，只用于 `selected`，须匹配该轨道的已有音块。单位是四分音符拍。 |
| `selectedSectionId`, `sectionRange` | `section` 必填；`sectionRange` 为 `{start,length}`，须与已有段落一致。不能同时使用 `clipRange`。 |
| `controls` | 可选受限参数；密度、复杂度、力度、人性化、和声走向、声部衔接与 seed，按 `normalizeControls` 校验。音乐参数是指导，不保证真实模型效果。 |
| `model` | 可选服务端模型名覆盖；最多 120 个字符，不接受控制字符。不是密钥。 |

输入 JSON 最多 **3,000,000 UTF-8 字节**，工程最多 64 小节、16 轨、12,000 音符；每轨、音块和 Pattern 等细分上限由工程校验器进一步约束。模型返回的完整工程最多 5,000 音符，这不同于输入上限；缩小修改范围仍会传送完整工程，而不是只传所选音符。

成功响应是 JSON，至少包含：

```json
{
  "project": "完整且已校验的工程对象，实际不是字符串",
  "summary": "简短编曲说明",
  "source": "llm"
}
```

本仓库还返回 `controls`、`seed` 和可选的 `constraints`。网页会再次校验工程，并以生成开始时的基线保护音色、音块、共享来源和范围外内容。窄范围不能更改无关轨道或全局设置。结果先进入候选审核，**不会自动应用或播放**。

浏览器响应最多 3,000,000 UTF-8 字节，并要求 JSON MIME；上游兼容响应也逐块限制为 3,000,000 字节。截断、拒绝、格式错误、非法工程和超限结果不采用。网页摘要按文本呈现，错误消息使用固定白名单，不显示服务商原始错误内容。

## GET 可选的配置检查

默认地址：`/api/llm/status`。只发送 `GET` 和 `Accept: application/json`，没有请求体、提示词或工程。状态地址需要用户明确填写，不会猜测、遍历或自动发起编曲；应与编曲地址同源。

本仓库的配置示例响应如下（仅示例，不代表真实调用成功）：

```json
{
  "protocol": "sprout-compose",
  "protocolVersion": 1,
  "composePath": "/api/compose",
  "ready": true,
  "checks": {"endpoint": "valid", "model": "valid"},
  "apiKeyPresent": false,
  "jsonMode": true,
  "limits": {
    "maxInputNotes": 12000,
    "maxGeneratedNotes": 5000,
    "maxProjectBytes": 3000000,
    "maxBars": 64,
    "timeoutMs": 80000,
    "maxConcurrent": 1
  }
}
```

- `checks.endpoint` 是**地址 / 凭据格式**检查，不是联网验证；凭据的控制字符格式错误也会使其无效。
- `checks.model` 只检查名称是否填写和格式。两项均为 `valid` 时 `ready` 才能为 `true`。值只能是 `missing` / `invalid` / `valid`。
- `apiKeyPresent` 只回传布尔值。本机免鉴权的兼容模型可以不提供密钥。不会回传上游 URL、模型名、密钥或任意环境值。
- `composePath` 解析后须与网页填写的编曲地址同源，且路径和查询串完全一致。限制字段必须是正整数，不能超过网页自身支持上限。
- 状态响应最多 32,000 UTF-8 字节。检测结果只用于当前设置窗，不保存为永久“连接成功”证明。没有状态接口仍可保存并主动生成，但检查会明确提示未验证。

状态和编曲响应都禁止重定向，浏览器使用 `credentials: 'omit'`，不携带 Cookie。HTTPS 或 `localhost` / `127.0.0.1` / `[::1]` 的 HTTP 地址可用；嵌入账号、片段以及名称含 key/token/secret/password/auth/credential 的查询参数被拒绝。

## 等待、取消、重试

- 网页配置检查最多等待 8 秒；生成最多 90 秒；本仓库上游调用最多 80 秒。
- “停止等待”中止浏览器请求、清除当前请求票据并忽略迟到结果。切换编曲服务或关闭页面也取消当前等待；旧请求完成不能解除新请求的忙碌状态。
- 本机服务器检测客户端断开后传递 `AbortSignal`，释放自己的请求槽位。上游已处理的请求不保证停止或取消计费；取消也不等于服务商取消。
- **没有自动重试。** 网络、超时、限流或通用服务失败提供“按原范围重试”。重试冻结原工程、范围、参数和服务设置，不使用后来切换的范围；工程或服务已变则拒绝重试，需重新明确生成。
- 默认服务每次最多 1 个活动请求，最短请求间隔 1,500 ms。读取请求体后再次检查槽位，避免并发慢速上传越过限制；429 附带 `Retry-After: 2`。这不是按用户计费或互联网部署的完整配额系统。

## 错误响应

服务端形如 `{"error":"固定的中文说明","code":"network"}`。网页信任固定代码，不采用任意 `error` 原文。主要分类：

| 代码 | 含义 |
| --- | --- |
| `unconfigured`, `configuration` | 服务端配置缺失 / 格式无效。 |
| `input` | 请求、模型覆盖名或范围不符合协议。 |
| `unauthorized`, `not_found`, `rate_limit` | 权限拒绝、地址不存在、并发或速率限制。 |
| `network`, `timeout`, `server` | 连接失败、等待超时、通用服务错误。 |
| `response_json`, `response_large`, `response_project` | 浏览器收到非 JSON、超限响应或无效工程。 |
| `provider_http`, `provider_json`, `provider_truncated`, `provider_refusal`, `provider_shape`, `provider_project` | 上游 HTTP、JSON、截断、拒绝、兼容格式或音乐工程问题。 |
| `status_address`, `status_protocol` | 只用于网页配置检查：不同源或不兼容状态协议。 |

本仓库输入错误用 400 / 415，未就绪用 503，上游失败通常用 502；网页也按 401 / 403 / 404 / 429 等标准状态映射固定说明。不把原始异常、模型错误体或凭据回传网页。

## 本机与在线版边界

`server.mjs` 默认绑定 `127.0.0.1:4173`，校验本机 Host；API 只接受同端口的 localhost / 127.0.0.1 Origin（没有 Origin 的本机程序也可请求）。导入 `createAppServer` 不读取 `.env`；只有直接启动服务的 CLI 才加载项目 `.env`。

**这个本机服务不能直接给已发布的在线 Site 跨域调用。** 在线版要接入用户自己部署的 HTTPS Sprout协议服务，配置自己的身份/访问控制并按需允许准确的网站 Origin；Cookie 登录目前不适用，因为客户端省略凭据。不要为了在线接入而放宽本机服务器的 Host / Origin 限制。部署服务、凭据、额度和真实模型验收仍需用户配置，不在静态 Site 中伪装完成。

## 本轮验证范围

0.13.0 的 233 项测试包含纯协议、配置脱敏、取消和迟到响应、限流竞态、流式字节上限、上游错误分类及实际浏览器 MIDI / WAV 导出对照。本机完整链路使用注入的模拟模型响应：网页 → HTTP 服务 → 真正的适配器 → 候选保护与审核。`examples/service-demo-*` 是这些静音导出，不是真实模型的音乐质量证明；具体记录见 `examples/validation-v13.json`。
