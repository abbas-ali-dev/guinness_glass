import CoreImage
import Foundation
import UIKit

// Note: For full OpenCV functionality, you need to add OpenCV iOS framework
// Download from: https://opencv.org/releases/
// Add OpenCV2.framework to your iOS project

class OpenCVProcessor {
    static func analyzeImage(imagePath: String) -> String {
        // For now, using CoreImage as fallback
        // To use full OpenCV, add OpenCV2.framework and uncomment OpenCV code

        guard let image = UIImage(contentsOfFile: imagePath),
            let cgImage = image.cgImage
        else {
            return "perfect"  // Default fallback
        }

        // Convert to grayscale for analysis
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()

        // Get image dimensions
        let width = cgImage.width
        let height = cgImage.height

        // Detect logo position (middle-upper portion)
        let logoY = detectLogoPosition(cgImage: cgImage, width: width, height: height)

        // Detect liquid level
        let liquidY = detectLiquidLevel(cgImage: cgImage, width: width, height: height)

        // Compare levels
        return compareLevels(logoPosition: logoY, liquidLevel: liquidY)
    }

    private static func detectLogoPosition(cgImage: CGImage, width: Int, height: Int) -> Double {
        // Focus on LOWER portion (35% to 70% of height) where GUINNESS word on black label is
        let startY = Int(Double(height) * 0.35)
        let endY = Int(Double(height) * 0.70)

        var bestScore: Double = 0
        var logoY = startY

        // Sample middle portion horizontally
        let startX = Int(Double(width) * 0.3)
        let endX = Int(Double(width) * 0.7)

        for y in startY..<endY {
            var brightPixels = 0
            var darkPixels = 0
            var totalPixels = 0
            var rowIntensity: Double = 0

            for x in startX..<endX {
                if let pixelData = getPixelData(cgImage: cgImage, x: x, y: y) {
                    let r = Double(pixelData[0])
                    let g = Double(pixelData[1])
                    let b = Double(pixelData[2])
                    let intensity = 0.299 * r + 0.587 * g + 0.114 * b
                    totalPixels += 1
                    rowIntensity += intensity

                    // Count bright pixels (white text)
                    if intensity > 180 {
                        brightPixels += 1
                    } else if intensity < 80 {
                        // Count dark background pixels
                        darkPixels += 1
                    }
                }
            }

            let brightRatio = Double(brightPixels) / Double(totalPixels)
            let darkRatio = Double(darkPixels) / Double(totalPixels)
            let avgIntensity = rowIntensity / Double(totalPixels)

            // GUINNESS word: white text on BLACK background (not foam)
            // Must have significant dark background
            if brightRatio > 0.08 && darkRatio > 0.30 && avgIntensity < 120 {
                let score = brightRatio * darkRatio * 100
                if score > bestScore {
                    bestScore = score
                    logoY = y
                }
            }
        }

        return Double(logoY) / Double(height)
    }

    private static func detectLiquidLevel(cgImage: CGImage, width: Int, height: Int) -> Double {
        // Sample only center of glass to avoid hand/thumb on edges (40% to 60% width)
        let darkThreshold: Double = 50.0  // Stricter threshold to avoid hand detection
        let lightThreshold: Double = 150.0  // Light foam threshold

        let startX = Int(Double(width) * 0.4)
        let endX = Int(Double(width) * 0.6)

        // First, find the bottom of the glass (where dark liquid definitely exists)
        var darkLiquidBottom = height - 1
        for y in stride(from: height - 1, through: Int(Double(height) * 0.7), by: -1) {
            var darkCount = 0
            var sampleCount = 0
            for x in startX..<endX {
                if let pixelData = getPixelData(cgImage: cgImage, x: x, y: y) {
                    let r = Double(pixelData[0])
                    let g = Double(pixelData[1])
                    let b = Double(pixelData[2])
                    let brightness = (r + g + b) / 3.0
                    sampleCount += 1
                    // Stricter threshold to avoid hand detection
                    if brightness < darkThreshold {
                        darkCount += 1
                    }
                }
            }
            // More strict: need 70% dark pixels
            if darkCount > Int(Double(sampleCount) * 0.70) {
                darkLiquidBottom = y
                break
            }
        }

        // Now scan from bottom UP to find where dark liquid ends (top edge of dark beer)
        for y in stride(from: darkLiquidBottom, through: 0, by: -1) {
            var darkCount = 0
            var lightCount = 0
            var totalPixels = 0

            for x in startX..<endX {
                if let pixelData = getPixelData(cgImage: cgImage, x: x, y: y) {
                    let r = Double(pixelData[0])
                    let g = Double(pixelData[1])
                    let b = Double(pixelData[2])
                    let brightness = (r + g + b) / 3.0
                    totalPixels += 1

                    if brightness < darkThreshold {
                        darkCount += 1
                    } else if brightness > lightThreshold {
                        lightCount += 1
                    }
                }
            }

            // If we're in dark region and see light above, this is the boundary
            if darkCount > Int(Double(totalPixels) * 0.5) && y > 5 {
                var transitionFound = true
                for checkY in max(y - 5, 0)..<y {
                    var checkLight = 0
                    for checkX in startX..<endX {
                        if let pixelData = getPixelData(cgImage: cgImage, x: checkX, y: checkY) {
                            let r = Double(pixelData[0])
                            let g = Double(pixelData[1])
                            let b = Double(pixelData[2])
                            let brightness = (r + g + b) / 3.0
                            if brightness > lightThreshold {
                                checkLight += 1
                            }
                        }
                    }
                    if checkLight < Int(Double(totalPixels) * 0.3) {
                        transitionFound = false
                        break
                    }
                }
                if transitionFound {
                    return Double(y) / Double(height)
                }
            }
        }

        return 0.5  // Default middle position
    }

    private static func compareLevels(logoPosition: Double, liquidLevel: Double) -> String {
        // PERFECT zone = GUINNESS word height (±2% = 4% total)
        let wordHeightHalf = 0.02
        let lowThreshold = wordHeightHalf  // Below word
        let highThreshold = -wordHeightHalf  // Above word
        let difference = liquidLevel - logoPosition

        if difference < highThreshold {
            return "high"  // Liquid ABOVE word
        } else if difference > lowThreshold {
            return "low"  // Liquid BELOW word
        } else {
            return "perfect"  // Within word height
        }
    }

    private static func getPixelData(cgImage: CGImage, x: Int, y: Int) -> [UInt8]? {
        guard x >= 0 && x < cgImage.width && y >= 0 && y < cgImage.height else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * cgImage.width
        let bitsPerComponent = 8

        var pixelData = [UInt8](repeating: 0, count: bytesPerPixel)

        guard
            let context = CGContext(
                data: &pixelData,
                width: 1,
                height: 1,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        context.translateBy(x: -CGFloat(x), y: CGFloat(y) - CGFloat(cgImage.height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        return pixelData
    }
}
