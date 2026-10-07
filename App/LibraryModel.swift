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
    @Published private(set) var sourceFiles: [URL] = []
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
    @Published var selfCheckReport = ""
    @Published var selfCheckImages: [UIImage] = []
    @Published var selfChecking = false
    @Published var autoRename: Bool { didSet { UserDefaults.standard.set(autoRename, forKey: "autoRename") } }
    @Published var recursive: Bool { didSet { UserDefaults.standard.set(recursive, forKey: "recursive") } }
    private var accessGranted = false
    private var fileScopes: [URL] = []
    private var scanTask: Task<Void, Never>?
    private var diagnosticRequest: QLThumbnailGenerator.Request?
    private var diagnosticToken = UUID()
    private var generation = UUID()
    var hasSource: Bool { folder != nil || !sourceFiles.isEmpty }
    var suggestedFolder: URL? { sourceFiles.first?.deletingLastPathComponent() ?? folder }
    var localLibraryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IPA", isDirectory: true)
    }

    func canRename(_ url: URL) -> Bool {
        guard let folder else { return false }
        return url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
    }

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestSeed") {
            UserDefaults.standard.removeObject(forKey: "folderBookmark")
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let directory = docs.appendingPathComponent("IPA", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let sample = Bundle.main.url(forResource: "ThumbnailSample", withExtension: "ipa") {
                let destination = directory.appendingPathComponent("Picker Sample.ipa")
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.copyItem(at: sample, to: destination)
                }
            }
        }
        #endif
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
        let scoped = url.startAccessingSecurityScopedResource()
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            message = "未取得这个文件夹的访问权限。请改用“选择 IPA 文件”，或在“浏览”中进入文件夹后点“打开”。"
            return
        }
        scanTask?.cancel()
        generation = UUID()
        if let old = folder, accessGranted { old.stopAccessingSecurityScopedResource() }
        releaseFileScopes()
        sourceFiles = []
        accessGranted = scoped
        folder = url
        selected = nil; items = []; undoRecords = []
        saveBookmark(url)
        refresh()
    }

    func chooseFiles(_ urls: [URL], openFirst: Bool = false) {
        let valid = Array(Set(urls.filter { $0.pathExtension.lowercased() == "ipa" })).sorted { $0.path < $1.path }
        guard !valid.isEmpty else { message = "没有选中 IPA，请选择以 .ipa 结尾的文件。"; return }
        scanTask?.cancel(); generation = UUID()
        // Acquire the new grants before releasing any previous grants for the same URLs.
        let scopes = valid.filter { $0.startAccessingSecurityScopedResource() }
        if let old = folder, accessGranted { old.stopAccessingSecurityScopedResource() }
        releaseFileScopes(); fileScopes = scopes
        accessGranted = false; folder = nil; sourceFiles = valid
        UserDefaults.standard.removeObject(forKey: "folderBookmark")
        selected = nil; items = []; undoRecords = []
        pendingOpen = openFirst ? valid.first : nil
        if valid.count != urls.count { message = "已选中 \(valid.count) 个 IPA，其他类型的文件已忽略。" }
        refresh()
    }

    private func releaseFileScopes() {
        for url in fileScopes { url.stopAccessingSecurityScopedResource() }
        fileScopes = []
    }

    private func saveBookmark(_ url: URL) {
        do { UserDefaults.standard.set(try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "folderBookmark") }
        catch { message = "本次可以使用文件夹，下次启动可能需要重新选择。" }
    }

    func refresh() {
        guard hasSource, !busy else { return }
        let root = folder
        let files = sourceFiles
        scanTask?.cancel()
        let token = UUID(); generation = token
        let recursive = self.recursive
        loading = true; progress = root == nil ? "正在读取选中的 IPA…" : "正在读取文件夹…"
        items = []
        scanTask = Task {
            // Each scan holds its own access until background reads have finished.
            let scopes = ([root].compactMap { $0 } + files).filter { $0.startAccessingSecurityScopedResource() }
            defer { for url in scopes { url.stopAccessingSecurityScopedResource() } }
            do {
                let urls: [URL]
                if let root {
                    urls = try await Task.detached(priority: .userInitiated) { try FileOperations.list(root, recursively: recursive) }.value
                } else { urls = files }
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
        if autoRename, item.info != nil, canRename(item.url) { await rename([item]) }
    }

    func rename(_ batch: [IPAItem]) async {
        guard !busy, !loading else { return }
        busy = true
        defer { busy = false; progress = "" }
        var changed: [RenameRecord] = []
        var failures: [String] = []
        for (i, item) in batch.enumerated() {
            guard let info = item.info else { continue }
            guard canRename(item.url) else {
                failures.append("\(item.filename)：请先返回主页，点“定位并授权所在文件夹”。")
                continue
            }
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
        // Open the granted file immediately. Parent access remains a separate user grant.
        chooseFiles([url], openFirst: true)
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

    func openLocalLibrary() {
        do {
            try FileManager.default.createDirectory(at: localLibraryURL, withIntermediateDirectories: true)
            chooseFolder(localLibraryURL)
        } catch { message = error.localizedDescription }
    }

    func importCopies(_ urls: [URL]) async {
        guard !busy, !urls.isEmpty else { return }
        let files = urls.filter { $0.pathExtension.lowercased() == "ipa" }
        guard !files.isEmpty else { message = "请选择 .ipa 文件。"; return }
        busy = true
        let destination = localLibraryURL
        var errors: [String] = []
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for (index, source) in files.enumerated() {
                progress = "正在导入 \(index + 1) / \(files.count)…"
                do {
                    try await Task.detached(priority: .userInitiated) {
                        let scoped = source.startAccessingSecurityScopedResource()
                        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                        var readError: NSError?
                        var copyResult: Result<Void, Error>?
                        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &readError) { url in
                            copyResult = Result {
                                let target = FileNaming.availableDestination(
                                    source: destination.appendingPathComponent(UUID().uuidString),
                                    desiredName: source.lastPathComponent)
                                try FileManager.default.copyItem(at: url, to: target)
                            }
                        }
                        if let readError { throw readError }
                        guard let copyResult else { throw IPAError.invalid("文件未能读取。") }
                        try copyResult.get()
                    }.value
                } catch { errors.append("\(source.lastPathComponent)：\(error.localizedDescription)") }
            }
        } catch { errors.append(error.localizedDescription) }
        busy = false; progress = ""
        openLocalLibrary()
        if !errors.isEmpty { message = errors.prefix(5).joined(separator: "\n") }
    }

    func runSelfCheck() async {
        guard !selfChecking else { return }
        selfChecking = true; selfCheckImages = []
        defer { selfChecking = false }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        selfCheckReport = "IPA 图标 \(version) · iPadOS \(UIDevice.current.systemVersion)\n"
        do {
            guard let sample = Bundle.main.url(forResource: "ThumbnailSample", withExtension: "ipa") else {
                throw IPAError.invalid("缺少内置样本。")
            }
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("缩略图测试", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let name = "图标测试-\(version)-\(UUID().uuidString.prefix(8))"
            let ipa = root.appendingPathComponent(name + ".ipa")
            let control = root.appendingPathComponent(name + ".ipacheck")
            try FileManager.default.copyItem(at: sample, to: ipa)
            try FileManager.default.copyItem(at: sample, to: control)
            let actual = (try? ipa.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier) ?? "未知"
            let types = UTType.types(tag: "ipa", tagClass: .filenameExtension, conformingTo: nil).map(\.identifier)
            selfCheckReport += "IPA 实际类型：\(actual)\nIPA 已登记类型：\(types.joined(separator: "、"))\n"
            let checks: [(String, URL, String?)] = [
                ("IPA 自动识别", ipa, nil), ("IPACHECK 对照", control, nil),
                ("指定本 App 类型", ipa, "com.lxyvee.ipautility.ipa"),
                ("指定万能签类型", ipa, "sign.wnqapp.com.ipa"),
                ("指定 Apple IPA 类型", ipa, "com.apple.itunes.ipa")
            ]
            for (label, url, type) in checks {
                selfCheckReport += "\n\(label)：检测中…"
                // Each forced-type request gets a distinct URL so the system's
                // result for an earlier request cannot be reused from its cache.
                var probeURL = url
                if type != nil {
                    probeURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("thumbnail-probe-\(UUID().uuidString).ipa")
                    try FileManager.default.copyItem(at: sample, to: probeURL)
                }
                let result = await ThumbnailProbe().run(url: probeURL, contentType: type)
                if type != nil { try? FileManager.default.removeItem(at: probeURL) }
                selfCheckReport += "\n\(result.message)\n"
                if let image = result.image { selfCheckImages.append(image) }
            }
            selfCheckReport += "\n检测完成。以上指定类型请求用于定位；系统“文件”的最终显示以自动识别和实际浏览结果为准。"
        } catch { selfCheckReport += "\n\(error.localizedDescription)" }
    }

    func checkThumbnail(_ url: URL) {
        if let previous = diagnosticRequest { QLThumbnailGenerator.shared.cancel(previous) }
        let token = UUID(); diagnosticToken = token
        let type = (try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier) ?? "未知"
        let embedded = Bundle.main.builtInPlugInsURL.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("IPAThumbnail.appex").path) } ?? false
        let plugin = Bundle.main.builtInPlugInsURL.flatMap { Bundle(url: $0.appendingPathComponent("IPAThumbnail.appex")) }
        let config = plugin?.infoDictionary?["NSExtension"] as? [String: Any]
        let attributes = config?["NSExtensionAttributes"] as? [String: Any]
        let supported = attributes?["QLSupportedContentTypes"] as? [String] ?? []
        let knownTypes = UTType.types(tag: "ipa", tagClass: .filenameExtension, conformingTo: nil).map(\.identifier)
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let header = "IPA 图标 \(version)\n扩展文件：\(embedded ? "已包含（是否能加载以请求结果为准）" : "缺失，请在签名时保留扩展")\n文件类型：\(type)\n类型匹配：\(supported.contains(type) ? "支持" : "尚未支持，请把检测结果发给开发者")\n已登记 IPA 类型：\(knownTypes.joined(separator: "、"))"
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
