// 助手面板:离线灵感引擎(本机规则)或 DeepSeek(需 API Key)。
// 生成 → 候选卡(试听/应用/放弃);应用走整工程快照撤销。
// DeepSeek 直连(api.deepseek.com),校验规则与 Web 版服务端一致。

#if canImport(AppKit)
import AppKit
import SwiftUI
import Security
import SproutKit

enum Keychain {
    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account,
                                    kSecAttrService as String: "SproutPlayer"]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }
    static func load(_ account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account,
                                    kSecAttrService as String: "SproutPlayer",
                                    kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct AssistantView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var useDeepSeek = false
    @State private var apiKey = Keychain.load("LLM_API_KEY")
    @State private var scope = "all"
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("助手").font(.title3.bold())
                Spacer()
                Picker("", selection: $useDeepSeek) {
                    Text("离线灵感引擎").tag(false)
                    Text("DeepSeek").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)
                Button("关闭") { dismiss() }
            }
            .padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if useDeepSeek {
                    HStack {
                        Text("API Key").font(.caption).foregroundStyle(.secondary)
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Button("保存") { Keychain.save(apiKey, account: "LLM_API_KEY") }
                            .disabled(apiKey.isEmpty)
                    }
                    Text("直连 api.deepseek.com;key 只存在本机钥匙串。输出经与 Web 版一致的服务端校验后才入候选。")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("离线引擎按文字关键词改写(风格/长度/速度/调性/力度),不联网、不花钱。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(minHeight: 72)
                    .overlay(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("想要什么感觉?比如:温柔的雨夜 lo-fi,只要鼓…")
                                .foregroundColor(.secondary).padding(8).allowsHitTesting(false)
                        }
                    }
                HStack {
                    Picker("范围", selection: $scope) {
                        Text("全部轨道").tag("all")
                        Text("只要鼓组").tag("drums")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    Spacer()
                    if working { ProgressView().scaleEffect(0.7) }
                    Button("生成") { generate() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || working || model.project == nil)
                }
                if let error = model.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if let candidate = model.candidate {
                    candidateCard(candidate)
                }
            }
            .padding(12)
            Spacer()
        }
        .frame(minWidth: 520, minHeight: 460)
    }

    private func candidateCard(_ candidate: CandidateProject) -> some View {
        let notes = jarrPublic(nil).count
        _ = notes
        return VStack(alignment: .leading, spacing: 8) {
            Text("候选 · \(candidate.summary)").font(.callout)
            Text("\(Int(jnum(candidate.project, "bpm", 90))) BPM · \(Int(jnum(candidate.project, "bars", 8))) 小节 · \(candidate.trackSummaries.joined(separator: " / "))")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("试听") { model.auditionCandidate() }
                Button("应用(可撤销)") { model.applyCandidate(); dismiss() }
                    .buttonStyle(.borderedProminent)
                Button("放弃") { model.discardCandidate() }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.4)))
    }

    private func generate() {
        working = true
        model.error = nil
        let scope = scope
        let prompt = prompt
        if useDeepSeek {
            guard let project = model.project else { working = false; return }
            var config = LLMConfig()
            config.apiKey = apiKey
            Task {
                do {
                    let result = try await composeWithDeepSeek(project: project, prompt: prompt, scope: scope, config: config)
                    await MainActor.run {
                        model.setCandidate(project: result.project, summary: result.summary)
                        working = false
                    }
                } catch {
                    await MainActor.run {
                        model.error = "\(error)"
                        working = false
                    }
                }
            }
        } else {
            guard let project = model.project else { working = false; return }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try generateFromPrompt(project, prompt, scope: scope, forcedSeed: Double(Int.random(in: 1...2_000_000_000)))
                    DispatchQueue.main.async {
                        model.setCandidate(project: result.project, summary: result.summary)
                        working = false
                    }
                } catch {
                    DispatchQueue.main.async {
                        model.error = "\(error)"
                        working = false
                    }
                }
            }
        }
    }
}
#endif
