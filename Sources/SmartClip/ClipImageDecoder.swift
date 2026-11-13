import CoreGraphics
import Foundation
import ImageIO

enum ClipImageDecoder {
    /// ImageIO performs the expensive decode away from the main actor. SwiftUI
    /// creates its lightweight NSImage wrapper only after the decoded CGImage returns.
    static func decode(_ data: Data) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }.value
    }

    /// History cards only need a compact preview. Downsampling at decode time
    /// avoids allocating the full bitmap while the user scrolls past images.
    static func decodeThumbnail(_ data: Data, maxPixelSize: Int) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }.value
    }
}
