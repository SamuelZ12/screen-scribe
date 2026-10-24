import Foundation
import Combine

struct RecognitionRecord: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var mode: RecognitionMode
    var backend: RecognitionBackend
    var model: String
    var output: RecognitionOutput
    var png: Data?
}

@MainActor
final class RecognitionHistory: ObservableObject {
    static let shared = RecognitionHistory()
    @Published private(set) var records: [RecognitionRecord] = []
    @Published private(set) var error = ""
    private let url: URL
    private var loadFailed = false
    private let budget = 25_000_000
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenScribe", isDirectory: true).appendingPathComponent("recognitions.json")
        guard FileManager.default.fileExists(atPath: self.url.path) else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: self.url.path)
            guard (attributes[.size] as? Int ?? 0) <= 36_000_000 else { throw RecognitionError.malformed }
            records = try JSONDecoder().decode([RecognitionRecord].self, from: Data(contentsOf: self.url))
        } catch {
            self.error = "历史文件无法读取，已保留原文件。清空历史后可恢复写入。"
            loadFailed = true
        }
    }
    @discardableResult
    func add(mode: RecognitionMode, configuration: RecognitionConfiguration, output: RecognitionOutput, png: Data?) throws -> UUID {
        let record = RecognitionRecord(mode: mode, backend: configuration.backend,
                                       model: configuration.backend == .mathpix ? "v3/text" : configuration.model,
                                       output: output, png: png)
        var next = [record] + records
        next = Array(next.prefix(50))
        while next.count > 1 && next.reduce(0, { $0 + ($1.png?.count ?? 0) + $1.output.code.utf8.count }) > budget { next.removeLast() }
        try persist(next)
        return record.id
    }
    func update(id: UUID, code: String) throws {
        var next = records
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].output.code = code
        try persist(next)
    }
    func remove(id: UUID) throws { try persist(records.filter { $0.id != id }) }
    func removeImages() throws {
        var next = records
        for index in next.indices { next[index].png = nil }
        try persist(next)
    }
    func clear() throws {
        // Explicit user clear also recovers from a damaged history file.
        let failed = loadFailed; loadFailed = false
        do { try persist([]) } catch { loadFailed = failed; throw error }
    }
    private func persist(_ next: [RecognitionRecord]) throws {
        guard !loadFailed else { throw RecognitionError.configuration(error) }
        do {
            let folder = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            records = next; error = ""
        } catch {
            self.error = "无法保存历史，请检查本地目录权限与磁盘空间。当前结果仍可复制。"
            throw RecognitionError.configuration(self.error)
        }
    }
}
