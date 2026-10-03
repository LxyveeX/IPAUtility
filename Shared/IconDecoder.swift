import UIKit
import ImageIO
import zlib

enum IconDecoder {
    static func image(_ data: Data) -> UIImage? {
        // CgBI is Apple's crushed PNG: raw DEFLATE and premultiplied BGR(A).
        if data.count > 16 && String(data: data.subdata(in: 12..<16), encoding: .ascii) == "CgBI" {
            return crushedPNG(data)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192,
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func scaled(_ image: UIImage, maximum: CGFloat) -> UIImage {
        let ratio = min(1, maximum / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * ratio), height: max(1, image.size.height * ratio))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func crushedPNG(_ data: Data) -> UIImage? {
        let bytes = [UInt8](data)
        func uint32(_ p: Int) -> Int {
            (Int(bytes[p]) << 24) | (Int(bytes[p+1]) << 16) | (Int(bytes[p+2]) << 8) | Int(bytes[p+3])
        }
        guard Array(bytes.prefix(8)) == [137,80,78,71,13,10,26,10] else { return nil }
        var p = 8, width = 0, height = 0, channels = 0
        var compressed = Data()
        while p <= bytes.count - 12 {
            let length = uint32(p)
            guard length <= bytes.count - p - 12 else { return nil }
            let type = String(bytes: bytes[(p+4)..<(p+8)], encoding: .ascii)
            if type == "IHDR" {
                guard length == 13, bytes[p+16] == 8, bytes[p+18] == 0, bytes[p+19] == 0, bytes[p+20] == 0 else { return nil }
                width = uint32(p+8); height = uint32(p+12)
                channels = bytes[p+17] == 6 ? 4 : (bytes[p+17] == 2 ? 3 : 0)
            } else if type == "IDAT" { compressed.append(contentsOf: bytes[(p+8)..<(p+8+length)]) }
            p += length + 12
            if type == "IEND" { break }
        }
        guard width > 0, height > 0, width <= 2048, height <= 2048, channels > 0, !compressed.isEmpty else { return nil }
        let rowBytes = width * channels
        var raw = [UInt8](repeating: 0, count: (rowBytes+1)*height)
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        let rawCount = raw.count
        let status: Int32 = compressed.withUnsafeBytes { input in
            raw.withUnsafeMutableBytes { output in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress!)
                stream.avail_in = uInt(compressed.count)
                stream.next_out = output.bindMemory(to: Bytef.self).baseAddress!
                stream.avail_out = uInt(rawCount)
                return inflate(&stream, Z_FINISH)
            }
        }
        let size = stream.total_out
        inflateEnd(&stream)
        guard status == Z_STREAM_END, size == rawCount else { return nil }
        var decoded = [UInt8](repeating: 0, count: rowBytes * height)
        for y in 0..<height {
            let filter = raw[y*(rowBytes+1)]
            guard filter <= 4 else { return nil }
            for x in 0..<rowBytes {
                let i = y*rowBytes+x
                let a = x >= channels ? Int(decoded[i-channels]) : 0
                let b = y > 0 ? Int(decoded[i-rowBytes]) : 0
                let c = y > 0 && x >= channels ? Int(decoded[i-rowBytes-channels]) : 0
                let prediction: Int
                switch filter {
                case 1: prediction = a
                case 2: prediction = b
                case 3: prediction = (a+b)/2
                case 4:
                    let q = a+b-c, pa = abs(q-a), pb = abs(q-b), pc = abs(q-c)
                    prediction = pa <= pb && pa <= pc ? a : (pb <= pc ? b : c)
                default: prediction = 0
                }
                decoded[i] = raw[y*(rowBytes+1)+1+x] &+ UInt8(prediction)
            }
        }
        var rgba = [UInt8](repeating: 255, count: width*height*4)
        for i in 0..<(width*height) {
            rgba[i*4] = decoded[i*channels+2]
            rgba[i*4+1] = decoded[i*channels+1]
            rgba[i*4+2] = decoded[i*channels]
            if channels == 4 { rgba[i*4+3] = decoded[i*channels+3] }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return scaled(UIImage(cgImage: cg), maximum: 512)
    }
}
