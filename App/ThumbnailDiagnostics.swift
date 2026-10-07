import UIKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Runs inside the app's own Documents directory, so a broken picker cannot hide
/// the actual registered UTI or the result returned by the system thumbnail service.
@MainActor
final class ThumbnailProbe {
    struct Result {
        let message: String
        let image: UIImage?
    }
    private var continuation: CheckedContinuation<Result, Never>?
    private var request: QLThumbnailGenerator.Request?
    private var timeout: Task<Void, Never>?

    func run(url: URL, contentType: String?) async -> Result {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let request = QLThumbnailGenerator.Request(fileAt: url,
                size: CGSize(width: 128, height: 128), scale: 2, representationTypes: .thumbnail)
            if let contentType, let type = UTType(contentType) { request.contentType = type }
            self.request = request
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, error in
                Task { @MainActor in
                    let text: String
                    if representation?.type == .thumbnail {
                        text = "系统返回内容缩略图。"
                    } else if let error = error as NSError? {
                        var lines = ["系统未返回内容缩略图：\(error.domain) (\(error.code)) · \(error.localizedDescription)"]
                        if let inner = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                            lines.append("底层错误：\(inner.domain) (\(inner.code)) · \(inner.localizedDescription)")
                        }
                        text = lines.joined(separator: "\n")
                    } else { text = "系统没有返回内容缩略图。" }
                    self?.finish(Result(message: text, image: representation?.uiImage))
                }
            }
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 12_000_000_000) }
                catch { return }
                guard let self else { return }
                self.finish(Result(message: "系统请求超时（12 秒）。", image: nil))
                QLThumbnailGenerator.shared.cancel(request)
            }
        }
    }

    private func finish(_ result: Result) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil; request = nil
        continuation.resume(returning: result)
    }
}
