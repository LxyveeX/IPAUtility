import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

enum IPAError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct IPAInfo {
    let name: String
    let version: String
    let build: String
    let bundleID: String
    let minimumOS: String
    let icon: Data?
    let iconSource: String
    var suggestedName: String { FileNaming.name(app: name, version: version) }
}

enum FileNaming {
    static func component(_ text: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t").union(.controlCharacters)
        let cleaned = text.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: " ")
        var result = cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        // Keep a complete Unicode character while leaving room for version / collision suffixes.
        while result.utf8.count > 170 { result.removeLast() }
        return result.isEmpty ? "未命名" : result
    }

    static func name(app: String, version: String) -> String {
        let title = component(app)
        var v = component(version)
        while v.utf8.count > 40 { v.removeLast() }
        return "\(title) \(v).ipa"
    }

    static func availableDestination(source: URL, desiredName: String) -> URL {
        let folder = source.deletingLastPathComponent()
        let desired = folder.appendingPathComponent(desiredName)
        if source.standardizedFileURL == desired.standardizedFileURL { return source }
        if !FileManager.default.fileExists(atPath: desired.path) { return desired }
        let stem = desired.deletingPathExtension().lastPathComponent
        var count = 2
        while true {
            let next = folder.appendingPathComponent("\(stem) (\(count)).ipa")
            if next.standardizedFileURL == source.standardizedFileURL { return source }
            if !FileManager.default.fileExists(atPath: next.path) { return next }
            count += 1
        }
    }
}

enum IPAReader {
    static func read(_ url: URL, assetLimit: Int = 48 * 1024 * 1024,
                     languages: [String] = Locale.preferredLanguages) throws -> IPAInfo {
        var result: Result<IPAInfo, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { localURL in
            result = Result { try parse(localURL, assetLimit: assetLimit, languages: languages) }
        }
        if let error = coordinationError { throw error }
        guard let result else { throw IPAError.invalid("无法读取文件，请重新选择所在文件夹。") }
        return try result.get()
    }

    static func parse(_ url: URL, assetLimit: Int, languages: [String]) throws -> IPAInfo {
        let archive = try Archive(url: url, accessMode: .read)
        var entries: [Entry] = []
        var scanned = 0
        for entry in archive {
            scanned += 1
            guard scanned <= 200_000 else { throw IPAError.invalid("IPA 内文件数量过多。") }
            let parts = entry.path.split(separator: "/")
            // Retain only root resources and localized names, not every game asset / framework entry.
            if (parts.count == 1 && entry.path.hasPrefix("iTunesArtwork"))
                || (parts.count >= 3 && parts.count <= 4 && parts[0] == "Payload" && parts[1].hasSuffix(".app")
                    && (parts.count == 3 || entry.path.hasSuffix(".lproj/InfoPlist.strings"))) {
                entries.append(entry)
            }
        }
        let roots = entries.filter { entry in
            let parts = entry.path.split(separator: "/")
            return entry.type == .file && parts.count == 3 && parts[0] == "Payload"
                && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
        }
        guard roots.count == 1, let plistEntry = roots.first else {
            throw IPAError.invalid("未找到唯一的 Payload/App.app/Info.plist，文件可能不完整。")
        }
        let prefix = String(plistEntry.path.dropLast("Info.plist".count))
        let plist = try dictionary(data(archive, plistEntry, limit: 2 * 1024 * 1024))
        let bundleID = text(plist["CFBundleIdentifier"]) ?? "未知标识"
        var name = text(plist["CFBundleDisplayName"]) ?? text(plist["CFBundleName"])
            ?? URL(fileURLWithPath: prefix).deletingPathExtension().lastPathComponent

        let localized = entries.filter {
            $0.path.hasPrefix(prefix) && $0.path.dropFirst(prefix.count).split(separator: "/").count == 2
                && $0.path.hasSuffix(".lproj/InfoPlist.strings")
        }
        let available = localized.map {
            String($0.path.dropFirst(prefix.count).split(separator: "/")[0].dropLast(".lproj".count))
        }
        let preferred = Bundle.preferredLocalizations(from: available, forPreferences: languages)
        for locale in preferred {
            if let entry = localized.first(where: { $0.path == prefix + locale + ".lproj/InfoPlist.strings" }),
               let bytes = try? data(archive, entry, limit: 256 * 1024),
               let values = try? dictionary(bytes),
               let title = text(values["CFBundleDisplayName"]) ?? text(values["CFBundleName"]) {
                name = title
                break
            }
        }

        let declared = iconNames(plist)
        let rootFiles = entries.filter {
            $0.type == .file && $0.path.hasPrefix(prefix)
                && !$0.path.dropFirst(prefix.count).contains("/")
        }
        let candidates = rootFiles.filter { entry in
            let leaf = String(entry.path.dropFirst(prefix.count)).lowercased()
            guard leaf.hasSuffix(".png") || leaf.hasSuffix(".jpg") || leaf.hasSuffix(".jpeg") else { return false }
            return declared.contains(where: { matches(leaf, name: $0) })
                || leaf.hasPrefix("appicon") || leaf == "icon.png" || leaf.hasPrefix("icon@")
                || leaf.hasPrefix("icon-") || leaf.hasPrefix("icon~")
        }.sorted { score($0.path, declared: declared) > score($1.path, declared: declared) }

        var best: UIImage?
        var bestScore = -1
        var origin = "未找到可读取的图标"
        for entry in candidates.prefix(24) {
            guard let bytes = try? data(archive, entry, limit: 8 * 1024 * 1024),
                  let image = IconDecoder.image(bytes) else { continue }
            let rank = score(entry.path, declared: declared) + Int(image.size.width)
            if rank > bestScore { best = image; bestScore = rank; origin = URL(fileURLWithPath: entry.path).lastPathComponent }
        }

        if best == nil {
            for path in ["iTunesArtwork@2x", "iTunesArtwork", prefix + "iTunesArtwork@2x", prefix + "iTunesArtwork"] {
                if let entry = entries.first(where: { $0.path == path }),
                   let bytes = try? data(archive, entry, limit: 8 * 1024 * 1024),
                   let image = IconDecoder.image(bytes) { best = image; origin = "iTunesArtwork"; break }
            }
        }
        if best == nil, let car = rootFiles.first(where: { $0.path == prefix + "Assets.car" }) {
            if let image = try? assetCatalogIcon(archive, entry: car, plist: plist, limit: assetLimit) {
                best = image; origin = "Assets.car"
            } else {
                origin = "图标仅在 Assets.car 中，系统未能读取"
            }
        }
        return IPAInfo(name: name, version: text(plist["CFBundleShortVersionString"])
                       ?? text(plist["CFBundleVersion"]) ?? "未知版本",
                       build: text(plist["CFBundleVersion"]) ?? "—", bundleID: bundleID,
                       minimumOS: text(plist["MinimumOSVersion"]) ?? "—",
                       icon: best.flatMap { IconDecoder.scaled($0, maximum: 256).pngData() }, iconSource: origin)
    }

    static func data(_ archive: Archive, _ entry: Entry, limit: Int) throws -> Data {
        guard entry.type == .file, entry.uncompressedSize <= UInt64(limit) else {
            throw IPAError.invalid("图标或描述文件超过读取上限。")
        }
        var bytes = Data()
        let crc = try archive.extract(entry, bufferSize: 64 * 1024) { chunk in
            guard bytes.count <= limit - chunk.count else { throw IPAError.invalid("文件解压大小异常。") }
            bytes.append(chunk)
        }
        guard crc == entry.checksum else { throw IPAError.invalid("文件校验失败，请重新下载 IPA。") }
        return bytes
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let result = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw IPAError.invalid("无法读取应用信息。")
        }
        return result
    }
    private static func text(_ value: Any?) -> String? {
        let s: String?
        if let v = value as? String { s = v } else if let v = value as? NSNumber { s = v.stringValue } else { s = nil }
        return s.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
    private static func iconNames(_ plist: [String: Any]) -> [String] {
        var names = (plist["CFBundleIconFiles"] as? [String]) ?? []
        names += (plist["CFBundleIconFiles~ipad"] as? [String]) ?? []
        if let name = plist["CFBundleIconFile"] as? String { names.append(name) }
        for key in ["CFBundleIcons~ipad", "CFBundleIcons"] {
            if let icons = plist[key] as? [String: Any], let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] {
                names += (primary["CFBundleIconFiles"] as? [String]) ?? []
                if let name = primary["CFBundleIconName"] as? String { names.append(name) }
            }
        }
        return Array(Set(names))
    }
    private static func matches(_ filename: String, name: String) -> Bool {
        let name = name.lowercased().replacingOccurrences(of: ".png", with: "")
        return filename == name + ".png" || filename.hasPrefix(name + "@") || filename.hasPrefix(name + "~")
    }
    private static func score(_ path: String, declared: [String]) -> Int {
        let leaf = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        return (declared.contains(where: { matches(leaf, name: $0) }) ? 10_000 : 0)
            + (leaf.contains("~ipad") ? 500 : 0) + (leaf.contains("@3x") ? 100 : 0)
    }

    // Public UIKit lookup for a resource-only bundle. No executable is extracted or loaded.
    private static func assetCatalogIcon(_ archive: Archive, entry: Entry, plist: [String: Any], limit: Int) throws -> UIImage? {
        guard entry.uncompressedSize <= UInt64(limit) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let carURL = folder.appendingPathComponent("Assets.car")
        FileManager.default.createFile(atPath: carURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: carURL)
        defer { try? output.close() }
        var count = 0
        let crc = try archive.extract(entry, bufferSize: 64 * 1024) { bytes in
            guard count <= limit - bytes.count else { throw IPAError.invalid("资源图标过大。") }
            try output.write(contentsOf: bytes); count += bytes.count
        }
        guard crc == entry.checksum else { return nil }
        let resourceInfo: [String: Any] = ["CFBundleIdentifier": "com.lxyvee.icons." + UUID().uuidString,
                                         "CFBundlePackageType": "BNDL", "CFBundleVersion": "1"]
        try PropertyListSerialization.data(fromPropertyList: resourceInfo, format: .binary, options: 0)
            .write(to: folder.appendingPathComponent("Info.plist"))
        guard let bundle = Bundle(url: folder) else { return nil }
        for name in iconNames(plist) + ["AppIcon", "Icon"] {
            if let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
                return IconDecoder.scaled(image, maximum: 256)
            }
        }
        return nil
    }
}
