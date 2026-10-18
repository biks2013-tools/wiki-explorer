import Foundation

/// One setting llm-wiki reads, as documented by `llm-wiki guide config`.
public struct SettingInfo: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case text
        case secret
        case choice([String])
        /// An absolute path to an executable (the headless browser).
        case executable
        /// An absolute path to a folder.
        case folder
    }

    public let key: String
    public let label: String
    public let help: String
    public let kind: Kind
    public var id: String { key }

    public init(_ key: String, _ label: String, _ kind: Kind = .text, help: String) {
        self.key = key; self.label = label; self.kind = kind; self.help = help
    }

    public var isSecret: Bool { kind == .secret }
}

public struct SettingGroup: Identifiable, Sendable {
    public let title: String
    public let footer: String?
    public let settings: [SettingInfo]
    /// The provider these credentials belong to (`openai`, …), nil for tool settings.
    public let provider: String?
    public var id: String { title }
}

public enum SettingsCatalog {
    public static let providers = ["openai", "anthropic", "gemini", "azure-openai", "azure-anthropic", "ollama", "litellm", "mlx"]

    public static let groups: [SettingGroup] = [
        SettingGroup(title: "Chat model", footer: "Used to ingest sources, answer questions and lint (ingest, query, lint --llm).", settings: [
            SettingInfo("LLM_WIKI_PROVIDER", "Provider", .choice(providers), help: "The provider of the chat model."),
            SettingInfo("LLM_WIKI_MODEL", "Model", help: "The chat model, e.g. gpt-5.5 or claude-sonnet-5-5. Azure OpenAI uses the deployment below."),
        ], provider: nil),
        SettingGroup(title: "Document parser", footer: "Converts PDF, Word, PowerPoint pages and pictures to text before ingest.", settings: [
            SettingInfo("LLM_WIKI_PARSER_PROVIDER", "Provider", .choice(providers), help: "The provider that reads documents and pictures."),
            SettingInfo("LLM_WIKI_PARSER_MODEL", "Model", help: "The parser model, or Azure deployment."),
        ], provider: nil),
        SettingGroup(title: "Embeddings", footer: "Optional: vector and hybrid search (index --embed, search --mode vector|hybrid).", settings: [
            SettingInfo("LLM_WIKI_EMBEDDING_PROVIDER", "Provider", .choice(providers.filter { $0 != "anthropic" && $0 != "azure-anthropic" }), help: "The embedding provider (not Anthropic)."),
            SettingInfo("LLM_WIKI_EMBEDDING_MODEL", "Model", help: "The embedding model, or Azure deployment."),
        ], provider: nil),
        SettingGroup(title: "Wikis and pages", footer: "Usually left unset: the app chooses the wiki, and new wikis ask for their format.", settings: [
            SettingInfo("LLM_WIKI_NAME", "Wiki name", help: "Registered wiki that commands use (overrides the current wiki)."),
            SettingInfo("LLM_WIKI_ROOT", "Wiki folder", .folder, help: "Wiki folder that commands use (alternative to a name)."),
            SettingInfo("LLM_WIKI_FORMAT", "Format of new wikis", .choice(["markdown", "html"]), help: "Page format given to `init` when none is chosen."),
            SettingInfo("LLM_WIKI_BROWSER", "Headless browser", .executable, help: "Chrome, Chromium, Edge or Brave executable, used to save JavaScript-built web pages as PDF."),
        ], provider: nil),
        SettingGroup(title: "OpenAI", footer: nil, settings: [
            SettingInfo("OPENAI_API_KEY", "API key", .secret, help: "OPENAI_API_KEY"),
            SettingInfo("OPENAI_BASE_URL", "Base URL", help: "Optional; also the server of the mlx provider."),
            SettingInfo("OPENAI_ORG_ID", "Organization", help: "Optional."),
        ], provider: "openai"),
        SettingGroup(title: "Anthropic", footer: nil, settings: [
            SettingInfo("ANTHROPIC_API_KEY", "API key", .secret, help: "ANTHROPIC_API_KEY"),
            SettingInfo("ANTHROPIC_BASE_URL", "Base URL", help: "Optional."),
        ], provider: "anthropic"),
        SettingGroup(title: "Google Gemini", footer: nil, settings: [
            SettingInfo("GOOGLE_API_KEY", "API key", .secret, help: "GOOGLE_API_KEY (GEMINI_API_KEY also works)."),
            SettingInfo("GEMINI_API_KEY", "API key (alternative)", .secret, help: "Used when GOOGLE_API_KEY is not set."),
        ], provider: "gemini"),
        SettingGroup(title: "Azure OpenAI", footer: nil, settings: [
            SettingInfo("AZURE_OPENAI_API_KEY", "API key", .secret, help: "AZURE_OPENAI_API_KEY"),
            SettingInfo("AZURE_OPENAI_ENDPOINT", "Endpoint", help: "https://<resource>.openai.azure.com"),
            SettingInfo("AZURE_OPENAI_DEPLOYMENT", "Deployment", help: "The chat deployment."),
            SettingInfo("AZURE_OPENAI_API_VERSION", "API version", help: "e.g. 2025-04-01-preview"),
        ], provider: "azure-openai"),
        SettingGroup(title: "Azure Anthropic (Foundry)", footer: nil, settings: [
            SettingInfo("AZURE_AI_INFERENCE_KEY", "Key", .secret, help: "AZURE_AI_INFERENCE_KEY"),
            SettingInfo("AZURE_AI_INFERENCE_ENDPOINT", "Endpoint", help: "The Foundry endpoint."),
        ], provider: "azure-anthropic"),
        SettingGroup(title: "Ollama", footer: nil, settings: [
            SettingInfo("OLLAMA_HOST", "Host", help: "e.g. http://127.0.0.1:11434"),
        ], provider: "ollama"),
        SettingGroup(title: "LiteLLM", footer: nil, settings: [
            SettingInfo("LITELLM_PROXY_URL", "Proxy URL", help: "The LiteLLM proxy."),
            SettingInfo("LITELLM_MASTER_KEY", "Key", .secret, help: "LITELLM_MASTER_KEY"),
        ], provider: "litellm"),
    ]

    public static var all: [SettingInfo] { groups.flatMap(\.settings) }
    public static func info(_ key: String) -> SettingInfo? { all.first { $0.key == key } }

    /// Keys whose values must never be shown by default: the catalogue's secrets and anything named like one.
    public static func isSecret(_ key: String) -> Bool {
        if info(key)?.isSecret == true { return true }
        let k = key.uppercased()
        return ["KEY", "TOKEN", "SECRET", "PASSWORD"].contains { k.contains($0) }
    }

    /// The providers chosen by the file's (or shell's) values: their credential groups are shown first.
    public static func providersInUse(_ values: [String: String]) -> Set<String> {
        var used = Set(["LLM_WIKI_PROVIDER", "LLM_WIKI_PARSER_PROVIDER", "LLM_WIKI_EMBEDDING_PROVIDER"].compactMap { values[$0] })
        if used.contains("mlx") { used.insert("openai") }
        return used
    }
}
