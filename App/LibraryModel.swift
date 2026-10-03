import Foundation
import Combine
import UIKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct IPAItem: Identifiable {
    let id: UUID
    var url: URL
    let info: IPAInfo?
    let size: Int64
    let error: String?
    var filename: String { url.lastPathComponent }
    var title: String { info?.name ?? url.deletingPathExtension().lastPathComponent }
}

struct RenameRecord {
    let before: URL
    let after: URL
}

enum FileOperations {
    static func rename(_ source: URL, toName: String) throws -> URL {
        var result: Result<URL, Error>?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: source, options: .forMoving, error: &coordinationError) { localSource in
            result = Result {
                let target = FileNaming.availableDestination(source: localSource, desiredName: toName)
                if localSource.standardizedFileURL == target.standardizedFileURL { return localSource }
                // FileManager refuses an existing destination: no replacement or overwrite.
                try FileManager.default.moveItem(at: localSource, to: target)
                coordinator.item(at: localSource, didMoveTo: target)
                return target
            }
        }
        if let error = coordinationError { throw error }
        guard let result else { throw IPAError.invalid("重命名未完成，请重新选择文件夹。") }
        return try result.get()
    }

    static func list(_ root: URL, recursively: Bool) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursively { options.insert(.skipsSubdirectoryDescendants) }
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: options,
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw IPAError.invalid("文件夹暂时无法访问，请重新选择。")
        }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true && url.pathExtension.lowercased() == "ipa" { urls.append(url) }
        }
        if let error = enumerationError { throw error }
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func item(_ url: URL) -> IPAItem {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        do { return IPAItem(id: UUID(), url: url, info: try IPAReader.read(url), size: size, error: nil) }
        catch { return IPAItem(id: UUID(), url: url, info: nil, size: size, error: error.localizedDescription) }
    }
}

@MainActor
final class LibraryModel: ObservableObject {
    @Published var items: [IPAItem] = []
    @Published var folder: URL?
    @Published var loading = false
    @Published var busy = false
    @Published var progress = ""
    @Published var message: String?
    @Published var selected: IPAItem?
    @Published var pendingOpen: URL?
    @Published var undoRecords: [RenameRecord] = []
    @Published var diagnosticImage: UIImage?
    @Published var diagnostic = ""
    @Published var checking = false
    @Published var autoRename: Bool { didSet { UserDefaults.standard.set(autoRename, forKey: "autoRename") } }
    @Published var recursive: Bool { didSet { UserDefaults.standard.set(recursive, forKey: "recursive") } }
    private var accessGranted = false
    private var scanTask: Task<Void, Never>?
    private var diagnosticRequest: QLThumbnailGenerator.Request?
    private var diagnosticToken = UUID()
    private var generation = UUID()

    init() {
        UserDefaults.standard.register(defaults: ["autoRename": true, "recursive": true])
        autoRename = UserDefaults.standard.bool(forKey: "autoRename")
        recursive = UserDefaults.standard.bool(forKey: "recursive")
        if let bookmark = UserDefaults.standard.data(forKey: "folderBookmark") {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale)
                accessGranted = url.startAccessingSecurityScopedResource()
                folder = url
                if stale { saveBookmark(url) }
            } catch { message = "请重新选择存放 IPA 的文件夹。" }
        }
    }

    func chooseFolder(_ url: URL) {
        scanTask?.cancel()
        generation = UUID()
        if let old = folder, accessGranted { old.stopAccessingSecurityScopedResource() }
        accessGranted = url.startAccessingSecurityScopedResource()
        folder = url
        selected = nil; items = []; undoRecords = []
        saveBookmark(url)
        refresh()
    }

    private func saveBookmark(_ url: URL) {
        do { UserDefaults.standard.set(try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "folderBookmark") }
        catch { message = "本次可以使用文件夹，下次启动可能需要重新选择。" }
    }

    func refresh() {
        guard let root = folder, !busy else { return }
        scanTask?.cancel()
        let token = UUID(); generation = token
        let recursive = self.recursive
        loading = true; progress = "正在读取文件夹…"
        items = []
        scanTask = Task {
            // Each scan holds its own access until background reads have finished.
            let scoped = root.startAccessingSecurityScopedResource()
            defer { if scoped { root.stopAccessingSecurityScopedResource() } }
            do {
                let urls = try await Task.detached(priority: .userInitiated) { try FileOperations.list(root, recursively: recursive) }.value
                for (index, url) in urls.enumerated() {
                    guard !Task.isCancelled, generation == token else { return }
                    progress = "正在读取 \(index + 1) / \(urls.count)"
                    let item = await Task.detached(priority: .utility) { autoreleasepool { FileOperations.item(url) } }.value
                    guard !Task.isCancelled, generation == token else { return }
                    items.append(item)
                }
                guard generation == token else { return }
                loading = false; progress = ""
                if let pending = pendingOpen,
                   let item = items.first(where: { $0.url.standardizedFileURL == pending.standardizedFileURL }) {
                    pendingOpen = nil
                    await open(item)
                }
            } catch {
                guard generation == token else { return }
                loading = false; progress = ""; message = error.localizedDescription
            }
        }
    }

    func open(_ item: IPAItem) async {
        guard !busy, !loading else { return }
        selected = item
        if autoRename, item.info != nil { await rename([item]) }
    }

    func rename(_ batch: [IPAItem]) async {
        guard !busy, !loading else { return }
        busy = true
        defer { busy = false; progress = "" }
        var changed: [RenameRecord] = []
        var failures: [String] = []
        for (i, item) in batch.enumerated() {
            guard let info = item.info else { continue }
            progress = "正在重命名 \(i+1) / \(batch.count)"
            do {
                let newURL = try await Task.detached(priority: .userInitiated) {
                    try FileOperations.rename(item.url, toName: info.suggestedName)
                }.value
                if newURL != item.url {
                    changed.append(RenameRecord(before: item.url, after: newURL))
                    if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].url = newURL }
                    if selected?.id == item.id { selected?.url = newURL }
                }
            } catch { failures.append("\(item.filename)：\(error.localizedDescription)") }
        }
        if !changed.isEmpty { undoRecords = changed }
        if !failures.isEmpty { message = "\(changed.count) 个文件已重命名。\n" + failures.prefix(5).joined(separator: "\n") }
        else if batch.count > 1 { message = changed.isEmpty ? "这些文件已使用规范名称。" : "已重命名 \(changed.count) 个文件；可以撤销。" }
    }

    func undo() async {
        guard !busy, !loading else { return }
        busy = true
        var remaining: [RenameRecord] = []
        for record in undoRecords.reversed() {
            do {
                // Do not restore over a newly created file with the old name.
                guard !FileManager.default.fileExists(atPath: record.before.path) else {
                    throw IPAError.invalid("原名称已被占用：\(record.before.lastPathComponent)")
                }
                let restored = try await Task.detached(priority: .userInitiated) {
                    try FileOperations.rename(record.after, toName: record.before.lastPathComponent)
                }.value
                if let index = items.firstIndex(where: { $0.url == record.after }) { items[index].url = restored }
                if selected?.url == record.after { selected?.url = restored }
            } catch { remaining.append(record); message = error.localizedDescription }
        }
        undoRecords = Array(remaining.reversed()); busy = false
    }

    func receive(_ url: URL) {
        guard url.pathExtension.lowercased() == "ipa" else { message = "请选择 .ipa 文件。"; return }
        if let item = items.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            Task { await open(item) }; return
        }
        pendingOpen = url
        if let root = folder, url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") {
            refresh(); return
        }
        // A file URL grant does not grant rename access to its parent directory.
        message = "请选择这个 IPA 所在的文件夹，授权后即可在原位置重命名。"
    }

    func createSamples() {
        do {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let directory = docs.appendingPathComponent("缩略图测试")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let source = Bundle.main.url(forResource: "ThumbnailSample", withExtension: "ipa") else { throw IPAError.invalid("缺少测试样本。") }
            // New names bypass stale Files thumbnails without modifying existing user files.
            let stamp = String(Int(Date().timeIntervalSince1970))
            for ext in ["ipa", "ipacheck"] {
                try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent("图标测试-\(stamp).\(ext)"))
            }
            message = "已生成两个测试文件。请到“文件 → 我的 iPad → IPA 图标 → 缩略图测试”，切换为图标视图查看。两种扩展名都应显示蓝色 App 图标；对比它们可定位类型关联问题。"
        } catch { message = error.localizedDescription }
    }

    func checkThumbnail(_ url: URL) {
        if let previous = diagnosticRequest { QLThumbnailGenerator.shared.cancel(previous) }
        let token = UUID(); diagnosticToken = token
        let type = (try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier) ?? "未知"
        let embedded = Bundle.main.builtInPlugInsURL.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("IPAThumbnail.appex").path) } ?? false
        let header = "扩展文件：\(embedded ? "已包含" : "缺失，请在签名时保留扩展")\n文件类型：\(type)"
        diagnostic = header + "\n正在请求系统缩略图…"
        diagnosticImage = nil; checking = true
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 160, height: 160), scale: 2, representationTypes: .thumbnail)
        diagnosticRequest = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, error in
            Task { @MainActor in
                guard let self, self.diagnosticToken == token else { return }
                self.checking = false
                self.diagnosticImage = representation?.uiImage
                let success = representation?.type == .thumbnail
                self.diagnostic = header + (success ? "\n系统已返回缩略图，请核对下方是否为该 App 图标。" : "\n系统未返回内容缩略图。\n\(error?.localizedDescription ?? "暂时只有默认文件图标。")")
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard diagnosticToken == token, checking else { return }
            QLThumbnailGenerator.shared.cancel(request)
            diagnosticToken = UUID(); checking = false
            diagnostic = header + "\n系统请求超时。请检查扩展签名、文件下载状态，再重试。"
        }
    }

    func clearDiagnostic() {
        if let request = diagnosticRequest { QLThumbnailGenerator.shared.cancel(request) }
        diagnosticToken = UUID(); diagnosticRequest = nil
        diagnosticImage = nil; diagnostic = ""; checking = false
    }
}
