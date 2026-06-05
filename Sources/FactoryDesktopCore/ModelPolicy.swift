import Foundation

public struct LocalModel: Identifiable, Hashable {
    public let id: String
    public let role: String
    public let defaultContext: Int
    public let maximumContext: Int

    public init(id: String, role: String, defaultContext: Int = 64_000, maximumContext: Int = 64_000) {
        self.id = id
        self.role = role
        self.defaultContext = defaultContext
        self.maximumContext = maximumContext
    }
}

public enum ModelPolicy {
    public static let plannerDefault = "qwen3.5:4b"

    public static let recommendedModels: [LocalModel] = [
        LocalModel(id: "qwen3.5:4b", role: "Factory planning", defaultContext: 64_000, maximumContext: 64_000),
        LocalModel(id: "codegeex4:9b", role: "Debug/code planning", defaultContext: 64_000, maximumContext: 64_000),
        LocalModel(id: "gemma4:e2b", role: "Task JSON", defaultContext: 64_000, maximumContext: 64_000),
        LocalModel(id: "granite4.1:3b", role: "Structured extraction", defaultContext: 64_000, maximumContext: 64_000),
        LocalModel(id: "qwen2.5-coder:7b", role: "Fallback code reasoning", defaultContext: 64_000, maximumContext: 128_000),
        LocalModel(id: "gemma4:latest", role: "Long-context reading", defaultContext: 64_000, maximumContext: 128_000),
        LocalModel(id: "gemma4:e4b", role: "Long-context reading", defaultContext: 64_000, maximumContext: 128_000),
        LocalModel(id: "qwen3.5:9b", role: "Planning with strict cap", defaultContext: 64_000, maximumContext: 128_000)
    ]

    public static func model(named name: String) -> LocalModel {
        recommendedModels.first { $0.id == name } ?? LocalModel(id: name, role: "Custom model", defaultContext: 64_000, maximumContext: 64_000)
    }

    public static func effectiveContext(for modelName: String, requested: Int? = nil) -> Int {
        let model = model(named: modelName)
        let requestedContext = requested ?? model.defaultContext
        let globalHardCap = 128_000
        return min(requestedContext, model.maximumContext, globalHardCap)
    }
}
