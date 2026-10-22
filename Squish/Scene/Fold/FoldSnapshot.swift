import CoreGraphics
import UIKit

/// Snapshot sanity for Fold Press: an ARView that never rendered returns a flat image (clear or background only).
enum FoldSnapshot {
    /// True when a 16 × 16 downsample has (almost) no variation: nothing but the background was drawn.
    static func isBlank(_ image: UIImage, tolerance: Int = 6) -> Bool {
        guard let cg = image.cgImage else { return true }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return true }
        for channel in 0..<4 {
            var lo = 255, hi = 0
            for i in stride(from: channel, to: pixels.count, by: 4) {
                lo = min(lo, Int(pixels[i]))
                hi = max(hi, Int(pixels[i]))
            }
            if hi - lo > tolerance { return false }
        }
        return true
    }
}
