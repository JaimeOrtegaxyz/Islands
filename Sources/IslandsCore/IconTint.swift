import CoreGraphics

/// Picks the colour that represents an app in the slim stack marker, from its icon.
public enum IconTint {

    public struct Pixel {
        public let r: CGFloat
        public let g: CGFloat
        public let b: CGFloat
        public let a: CGFloat

        public init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
            self.r = r
            self.g = g
            self.b = b
            self.a = a
        }
    }

    /// Pixels at least this saturated and this bright count as "colour".
    static let minSaturation: CGFloat = 0.35
    static let minBrightness: CGFloat = 0.3
    /// Fewer coloured pixels than this share of the opaque ones means the icon has no colour
    /// worth using — Terminal's grey, a black-and-white glyph — and the caller falls back.
    static let minColoredShare: CGFloat = 0.12
    static let hueBins = 12

    /// The icon's dominant colour: the saturated hue covering the most of it (weighted by how
    /// vivid each pixel is), averaged over the pixels of that hue. Takes straight (not
    /// premultiplied) RGBA in 0...1. Returns nil for icons without real colour.
    public static func dominantColor(of pixels: [Pixel]) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        var opaque = 0
        var colored = 0
        var weights = [CGFloat](repeating: 0, count: hueBins)
        var sums = [(r: CGFloat, g: CGFloat, b: CGFloat)](repeating: (0, 0, 0), count: hueBins)

        for pixel in pixels where pixel.a >= 0.5 {
            opaque += 1
            let maxC = max(pixel.r, pixel.g, pixel.b)
            let minC = min(pixel.r, pixel.g, pixel.b)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            guard saturation >= minSaturation, maxC >= minBrightness else { continue }
            colored += 1

            let bin = Int(hue(r: pixel.r, g: pixel.g, b: pixel.b, maxC: maxC, minC: minC) * CGFloat(hueBins)) % hueBins
            let weight = saturation * maxC
            weights[bin] += weight
            sums[bin].r += pixel.r * weight
            sums[bin].g += pixel.g * weight
            sums[bin].b += pixel.b * weight
        }

        guard opaque > 0, CGFloat(colored) >= CGFloat(opaque) * minColoredShare,
              let best = weights.indices.max(by: { weights[$0] < weights[$1] }),
              weights[best] > 0 else { return nil }
        let total = weights[best]
        return (sums[best].r / total, sums[best].g / total, sums[best].b / total)
    }

    /// Hue in 0..<1 for a pixel already known to be saturated (`maxC > minC`).
    private static func hue(r: CGFloat, g: CGFloat, b: CGFloat, maxC: CGFloat, minC: CGFloat) -> CGFloat {
        let delta = maxC - minC
        guard delta > 0 else { return 0 }
        var h: CGFloat
        if maxC == r {
            h = (g - b) / delta
        } else if maxC == g {
            h = (b - r) / delta + 2
        } else {
            h = (r - g) / delta + 4
        }
        h /= 6
        return h < 0 ? h + 1 : h
    }
}
