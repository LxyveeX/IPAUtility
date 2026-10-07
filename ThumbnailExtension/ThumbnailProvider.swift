import UIKit
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let info = try IPAReader.read(request.fileURL, assetLimit: 24 * 1024 * 1024)
            guard let data = info.icon, let icon = UIImage(data: data) else {
                handler(nil, IPAError.invalid(info.iconSource)); return
            }
            let edge = max(1, min(request.maximumSize.width, request.maximumSize.height))
            let size = CGSize(width: edge, height: edge)
            handler(QLThumbnailReply(contextSize: size, currentContextDrawing: {
                let rect = CGRect(origin: .zero, size: size)
                // Files composites clipped corners onto a white document background.
                // Fill the entire content area with the original icon.
                icon.draw(in: rect)
                return true
            }), nil)
        } catch { handler(nil, error) }
    }
}
