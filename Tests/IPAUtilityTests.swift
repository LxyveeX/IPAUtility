import XCTest
import UIKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
@testable import IPAUtility

final class IPAUtilityTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    }
    private func read(_ name: String) throws -> IPAInfo {
        try IPAReader.read(fixture(name), languages: ["zh-Hans-CN", "en"])
    }

    func testChineseNameAndRootAppSelection() throws {
        let info = try read("localized.ipa")
        XCTAssertEqual(info.name, "示例应用")
        XCTAssertEqual(info.version, "2.3.4")
        XCTAssertEqual(info.build, "57")
        XCTAssertEqual(info.bundleID, "example.fixture")
        XCTAssertEqual(info.suggestedName, "示例应用 2.3.4.ipa")
        XCTAssertNotNil(info.icon)
    }

    func testCrushedPNGPixelsMatchStandardPNG() throws {
        let ordinary = try XCTUnwrap(IconDecoder.image(Data(contentsOf: fixture("ordinary.png"))))
        let crushed = try XCTUnwrap(IconDecoder.image(Data(contentsOf: fixture("crushed.png"))))
        XCTAssertEqual(ordinary.size, crushed.size)
        let a = try pixels(ordinary), b = try pixels(crushed)
        XCTAssertEqual(a.count, b.count)
        XCTAssertTrue(zip(a,b).allSatisfy { pair in abs(Int(pair.0)-Int(pair.1)) <= 2 })
        XCTAssertNotNil(try read("crushed.ipa").icon)
    }

    func testZIP64AndLegacyArtwork() throws {
        XCTAssertNotNil(try read("zip64.ipa").icon)
        let artwork = try read("artwork.ipa")
        XCTAssertNotNil(artwork.icon)
        XCTAssertEqual(artwork.iconSource, "iTunesArtwork")
    }

    func testInvalidArchiveAndMissingIcon() throws {
        XCTAssertThrowsError(try read("invalid.ipa"))
        let info = try read("no-icon.ipa")
        XCTAssertEqual(info.name, "Test App")
        XCTAssertNil(info.icon)
        XCTAssertNil(IconDecoder.image(Data([0,1,2,3])))
        let bad = Data(repeating: 0, count: 200)
        XCTAssertNil(IconDecoder.image(bad))
    }

    func testExtractionLimitIsEnforced() throws {
        let archive = try Archive(url: fixture("localized.ipa"), accessMode: .read)
        let entry = try XCTUnwrap(archive["Payload/Fixture.app/Info.plist"])
        XCTAssertThrowsError(try IPAReader.data(archive, entry, limit: 8))
    }

    func testSanitizesNamesAndKeepsUnicodeWithinFilesystemLimits() {
        let name = FileNaming.name(app: " 测试/应用:游戏\n", version: "1/2")
        XCTAssertEqual(name, "测试 应用 游戏 1 2.ipa")
        let long = FileNaming.name(app: String(repeating: "𠮷🎮", count: 100), version: String(repeating:"版本",count:100))
        XCTAssertLessThan(long.utf8.count, 255)
        XCTAssertEqual(FileNaming.name(app: "../", version: "..."), "未命名 未命名.ipa")
    }

    func testRenamePreservesContentsAvoidsCollisionsAndIsIdempotent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("download.ipa")
        let destination = "示例应用 2.3.4.ipa"
        let original = try Data(contentsOf: fixture("localized.ipa"))
        try original.write(to: source)
        let existing = folder.appendingPathComponent(destination)
        try Data("keep".utf8).write(to: existing)
        let renamed = try FileOperations.rename(source, toName: destination)
        XCTAssertEqual(renamed.lastPathComponent, "示例应用 2.3.4 (2).ipa")
        XCTAssertEqual(try Data(contentsOf: renamed), original)
        XCTAssertEqual(try Data(contentsOf: existing), Data("keep".utf8))
        XCTAssertEqual(try FileOperations.rename(renamed, toName: destination), renamed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testEmbeddedExtensionRegistrationConfiguration() throws {
        let extensions = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let url = extensions.appendingPathComponent("IPAThumbnail.appex/Info.plist")
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String:Any])
        let config = try XCTUnwrap(plist["NSExtension"] as? [String:Any])
        XCTAssertEqual(config["NSExtensionPointIdentifier"] as? String, "com.apple.quicklook.thumbnail")
        let attributes = try XCTUnwrap(config["NSExtensionAttributes"] as? [String:Any])
        XCTAssertTrue((attributes["QLSupportedContentTypes"] as? [String] ?? []).contains("com.apple.itunes.ipa"))
        XCTAssertTrue((attributes["QLSupportedContentTypes"] as? [String] ?? []).contains("sign.wnqapp.com.ipa"))
    }

    func testSystemGeneratesRealIPAThumbnail() throws {
        try verifySystemThumbnail(contentType: nil)
    }

    func testSystemGeneratesWanNengQianIPAThumbnail() throws {
        try verifySystemThumbnail(contentType: XCTUnwrap(UTType("sign.wnqapp.com.ipa")))
    }

    func testSystemGeneratesAppleIPAThumbnail() throws {
        try verifySystemThumbnail(contentType: XCTUnwrap(UTType("com.apple.itunes.ipa")))
    }

    private func verifySystemThumbnail(contentType: UTType?) throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documents.appendingPathComponent("thumbnail-integration-\(UUID().uuidString).ipa")
        try FileManager.default.copyItem(at: fixture("localized.ipa"), to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let done = expectation(description: "Quick Look invokes the IPA thumbnail provider")
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 64, height: 64), scale: 1, representationTypes: .thumbnail)
        if let contentType { request.contentType = contentType }
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
            defer { done.fulfill() }
            XCTAssertNil(error)
            XCTAssertEqual(representation?.type, .thumbnail)
            guard let image = representation?.uiImage, let cg = image.cgImage,
                  let rgba = try? self.pixels(image) else { XCTFail("No thumbnail image returned"); return }
            let center = ((cg.height/2)*cg.width + cg.width/2)*4
            XCTAssertGreaterThan(Int(rgba[center+2]), Int(rgba[center])+40, "Expected the fixture's blue icon")
            XCTAssertGreaterThan(rgba[center+3], 240)
            let attachment = XCTAttachment(image: image)
            attachment.name = "System-generated IPA thumbnail: \(contentType?.identifier ?? "automatic")"
            attachment.lifetime = .keepAlways
            self.add(attachment)
        }
        wait(for: [done], timeout: 40)
        QLThumbnailGenerator.shared.cancel(request)
    }

    @MainActor
    func testDirectFileSelectionDoesNotGrantParentAccess() async throws {
        UserDefaults.standard.removeObject(forKey: "folderBookmark")
        let model = LibraryModel()
        let source = try fixture("localized.ipa")
        model.chooseFiles([source])
        for _ in 0..<200 where model.loading { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(model.loading)
        let item = try XCTUnwrap(model.items.first)
        XCTAssertNotNil(item.info?.icon)
        XCTAssertNil(model.folder)
        XCTAssertFalse(model.canRename(source))
        XCTAssertEqual(model.suggestedFolder, source.deletingLastPathComponent())
        await model.open(item)
        XCTAssertEqual(model.selected?.url, source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(model.undoRecords.isEmpty)
    }

    @MainActor
    func testOpeningAnExternalIPAImmediatelyShowsDetails() async throws {
        UserDefaults.standard.removeObject(forKey: "folderBookmark")
        let model = LibraryModel()
        let source = try fixture("localized.ipa")
        model.receive(source)
        for _ in 0..<200 where model.loading { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(model.selected?.url, source)
        XCTAssertNotNil(model.selected?.info?.icon)
        XCTAssertNil(model.pendingOpen)
        XCTAssertNil(model.message)
    }

    @MainActor
    func testPickerSelectionAndCancellationCompleteExactlyOnce() {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        let url = FileManager.default.temporaryDirectory
        var selections: [[URL]] = []
        let selected = DocumentPicker.Coordinator { selections.append($0) }
        selected.documentPicker(controller, didPickDocumentsAt: [url])
        selected.documentPickerWasCancelled(controller)
        XCTAssertEqual(selections, [[url]])
        let cancelled = DocumentPicker.Coordinator { selections.append($0) }
        cancelled.documentPickerWasCancelled(controller)
        cancelled.documentPickerWasCancelled(controller)
        XCTAssertEqual(selections, [[url], []])
    }

    func testSystemIconsExistAtSmallAndIPadSizes() throws {
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            let icons = try XCTUnwrap(Bundle.main.infoDictionary?[key] as? [String: Any])
            let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
            XCTAssertNil(primary["CFBundleIconName"])
            let files = try XCTUnwrap(primary["CFBundleIconFiles"] as? [String])
            XCTAssertTrue(Set(["Icon20", "Icon29", "Icon40"]).isSubset(of: Set(files)))
            for name in files {
                let url = try XCTUnwrap(Bundle.main.url(forResource: name + "@2x", withExtension: "png"))
                XCTAssertNotNil(IconDecoder.image(try Data(contentsOf: url)))
            }
        }
    }

    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width*cg.height*4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                                                  bitsPerComponent: 8, bytesPerRow: cg.width*4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return bytes
    }
}
