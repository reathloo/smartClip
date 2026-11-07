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
}
