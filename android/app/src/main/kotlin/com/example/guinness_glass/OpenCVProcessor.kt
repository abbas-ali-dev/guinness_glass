package com.example.guinness_glass

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import java.io.File

class OpenCVProcessor {
    companion object {
        // Analyze image and return drink level
        // Returns: "low", "perfect", or "high"
        // Note: This uses OpenCV-style algorithms without requiring OpenCV library
        // For full OpenCV support, add OpenCV Android SDK and uncomment OpenCV code
        fun analyzeImage(imagePath: String): String {
            try {
                // Load image
                val bitmap = BitmapFactory.decodeFile(imagePath)
                if (bitmap == null) {
                    throw Exception("Could not load image")
                }

                // Detect Guinness logo position
                val logoY = detectLogoPosition(bitmap)

                // Detect liquid level
                val liquidY = detectLiquidLevel(bitmap)

                // Compare and return result
                return compareLevels(logoY, liquidY)
            } catch (e: Exception) {
                throw Exception("Image processing error: ${e.message}")
            }
        }

        private fun detectLogoPosition(bitmap: Bitmap): Double {
            val height = bitmap.height.toDouble()
            val width = bitmap.width.toDouble()

            // Focus on LOWER portion (35% to 70% of height) where GUINNESS word on black label is
            val startY = (height * 0.35).toInt()
            val endY = (height * 0.70).toInt()
            val startX = (width * 0.3).toInt()
            val endX = (width * 0.7).toInt()

            data class CandidateRow(val y: Int, val brightRatio: Double, val avgIntensity: Double, val maxConsecutive: Int, val darkRatio: Double = 0.0) {
                val score: Double = brightRatio * darkRatio * 100 * (maxConsecutive / 10.0)
            }

            val candidateRows = mutableListOf<CandidateRow>()

            // Look for white text on DARK background - GUINNESS word on black label
            for (y in startY until endY) {
                var brightPixels = 0
                var darkPixels = 0
                var totalPixels = 0
                var rowIntensity = 0.0
                var consecutiveBright = 0
                var maxConsecutiveBright = 0

                for (x in startX until endX) {
                    val pixel = bitmap.getPixel(x, y)
                    val r = Color.red(pixel)
                    val g = Color.green(pixel)
                    val b = Color.blue(pixel)
                    val intensity = 0.299 * r + 0.587 * g + 0.114 * b
                    
                    totalPixels++
                    rowIntensity += intensity

                    // White/light pixels (logo text)
                    if (intensity > 180) {
                        brightPixels++
                        consecutiveBright++
                        maxConsecutiveBright = maxOf(maxConsecutiveBright, consecutiveBright)
                    } else {
                        consecutiveBright = 0
                        // Count dark background pixels
                        if (intensity < 80) {
                            darkPixels++
                        }
                    }
                }

                val brightRatio = brightPixels.toDouble() / totalPixels
                val darkRatio = darkPixels.toDouble() / totalPixels
                val avgIntensity = rowIntensity / totalPixels

                // GUINNESS word: white text on BLACK background (not foam)
                if (brightRatio > 0.08 && 
                    darkRatio > 0.30 && 
                    avgIntensity < 120 && 
                    maxConsecutiveBright > 10) {
                    candidateRows.add(CandidateRow(y, brightRatio, avgIntensity, maxConsecutiveBright, darkRatio))
                }
            }

            // Find the best candidate (highest score)
            if (candidateRows.size > 0) {
                candidateRows.sortByDescending { it.score }
                var logoY = candidateRows.first().y

                // Check rows around to find the center of the logo text
                var totalY = logoY
                var count = 1

                for (offset in 1..15) {
                    if (logoY + offset < endY) {
                        val checkY = logoY + offset
                        var brightCount = 0
                        var darkCount = 0
                        for (x in startX until endX) {
                            val pixel = bitmap.getPixel(x, checkY)
                            val r = Color.red(pixel)
                            val g = Color.green(pixel)
                            val b = Color.blue(pixel)
                            val intensity = 0.299 * r + 0.587 * g + 0.114 * b
                            if (intensity > 180) {
                                brightCount++
                            } else if (intensity < 80) {
                                darkCount++
                            }
                        }
                        // Must have both bright text and dark background
                        if (brightCount > (endX - startX) * 0.08 && 
                            darkCount > (endX - startX) * 0.25) {
                            totalY += checkY
                            count++
                        }
                    }
                    if (logoY - offset >= startY) {
                        val checkY = logoY - offset
                        var brightCount = 0
                        var darkCount = 0
                        for (x in startX until endX) {
                            val pixel = bitmap.getPixel(x, checkY)
                            val r = Color.red(pixel)
                            val g = Color.green(pixel)
                            val b = Color.blue(pixel)
                            val intensity = 0.299 * r + 0.587 * g + 0.114 * b
                            if (intensity > 180) {
                                brightCount++
                            } else if (intensity < 80) {
                                darkCount++
                            }
                        }
                        // Must have both bright text and dark background
                        if (brightCount > (endX - startX) * 0.08 && 
                            darkCount > (endX - startX) * 0.25) {
                            totalY += checkY
                            count++
                        }
                    }
                }

                val avgLogoY = totalY.toDouble() / count
                return avgLogoY / height
            }

            // Fallback: if no clear GUINNESS word found, assume middle position on label
            return 0.50
        }

        private fun detectLiquidLevel(bitmap: Bitmap): Double {
            val height = bitmap.height.toDouble()
            val width = bitmap.width.toDouble()

            // Detect 2 parts of glass: black drink and foam (yellow/brown)
            // Sample only center of glass to avoid hand/thumb on edges (40% to 60% width)
            val startX = (width * 0.4).toInt()
            val endX = (width * 0.6).toInt()

            // Thresholds - more strict to avoid false detections from hand/thumb
            // 1. Black drink: very dark (R+G+B < 50) - stricter than before
            // 2. Foam: yellow/brown/light (50 <= R+G+B < 160, and R/G ratio indicates yellow/brown)

            var darkLiquidTop = 0.5 // Default middle

            // First, find bottom where black drink definitely exists
            var darkLiquidBottom = height.toInt() - 1
            for (y in (height - 1).toInt() downTo (height * 0.6).toInt()) {
                var darkCount = 0
                var sampleCount = 0

                for (x in startX until endX) {
                    val pixel = bitmap.getPixel(x, y)
                    val r = Color.red(pixel)
                    val g = Color.green(pixel)
                    val b = Color.blue(pixel)
                    val brightness = (r + g + b) / 3.0
                    sampleCount++

                    // Black drink: very dark - stricter to avoid hand detection
                    if (brightness < 50) {
                        darkCount++
                    }
                }

                // More strict: need 70% dark pixels to confirm black drink at bottom
                if (darkCount > sampleCount * 0.70) {
                    darkLiquidBottom = y
                    break
                }
            }

            // Scan from bottom UP to find transition from black drink to foam
            // Only detect 2 parts: drink and foam (ignore empty glass)
            var foundDarkLiquidTop = false
            var consecutiveNonDarkRows = 0

            for (y in darkLiquidBottom downTo (height * 0.1).toInt()) {
                var darkCount = 0
                var foamCount = 0
                var totalPixels = 0

                for (x in startX until endX) {
                    val pixel = bitmap.getPixel(x, y)
                    val r = Color.red(pixel)
                    val g = Color.green(pixel)
                    val b = Color.blue(pixel)
                    val brightness = (r + g + b) / 3.0
                    totalPixels++

                    // Classify pixel into 2 parts only
                    if (brightness < 50) {
                        // Part 1: Black drink - stricter threshold
                        darkCount++
                    } else if (brightness >= 50 && brightness < 160) {
                        // Part 2: Foam (yellow/brown) - check color ratios
                        val rgAvg = (r + g) / 2.0
                        if (rgAvg > b * 1.15) {
                            // Yellow/brown tint detected (foam)
                            foamCount++
                        }
                    }
                }

                val darkRatio = darkCount.toDouble() / totalPixels
                val foamRatio = foamCount.toDouble() / totalPixels

                // Find transition from black drink to foam
                if (!foundDarkLiquidTop) {
                    if (darkRatio < 0.35) {
                        // Dark pixels dropped significantly - might be entering foam
                        consecutiveNonDarkRows++

                        // Check if we have foam above
                        if (foamRatio > 0.25 && consecutiveNonDarkRows >= 3) {
                            // Verify with rows above - must have consistent foam
                            var foamAbove = 0
                            var checkRows = 0
                            for (checkY in (y - 8).coerceAtLeast(0) until y) {
                                checkRows++
                                for (checkX in startX until endX) {
                                    val pixel = bitmap.getPixel(checkX, checkY)
                                    val r = Color.red(pixel)
                                    val g = Color.green(pixel)
                                    val b = Color.blue(pixel)
                                    val brightness = (r + g + b) / 3.0
                                    if (brightness >= 55 && brightness < 160) {
                                        val rgAvg = (r + g) / 2.0
                                        if (rgAvg > b * 1.15) {
                                            foamAbove++
                                        }
                                    }
                                }
                            }
                            // Need 20% foam pixels above to confirm transition
                            if (checkRows > 0 && foamAbove > (checkRows * (endX - startX) * 0.2)) {
                                darkLiquidTop = y / height
                                foundDarkLiquidTop = true
                                break
                            }
                        }
                    } else {
                        consecutiveNonDarkRows = 0
                    }
                }
            }

            return darkLiquidTop
        }

        private fun compareLevels(logoPosition: Double, liquidLevel: Double): String {
            // PERFECT zone = GUINNESS word height (±2% = 4% total)
            val wordHeightHalf = 0.02
            val lowThreshold = wordHeightHalf  // Below word
            val highThreshold = -wordHeightHalf // Above word
            
            val difference = liquidLevel - logoPosition

            android.util.Log.d("GuinnessApp", "==================== COMPARISON ====================")
            android.util.Log.d("GuinnessApp", "GUINNESS Word: ${logoPosition}")
            android.util.Log.d("GuinnessApp", "Liquid Level: ${liquidLevel}")
            android.util.Log.d("GuinnessApp", "Difference: ${difference}")
            android.util.Log.d("GuinnessApp", "highThreshold: $highThreshold (if diff < this = HIGH)")
            android.util.Log.d("GuinnessApp", "lowThreshold: $lowThreshold (if diff > this = LOW)")
            android.util.Log.d("GuinnessApp", "Check: ${difference} < ${highThreshold} = ${difference < highThreshold}")
            android.util.Log.d("GuinnessApp", "Check: ${difference} > ${lowThreshold} = ${difference > lowThreshold}")

            val result = when {
                difference < highThreshold -> {
                    android.util.Log.d("GuinnessApp", "✓ RESULT: HIGH (liquid ${(-difference * 100)}% above)")
                    "high"
                }
                difference > lowThreshold -> {
                    android.util.Log.d("GuinnessApp", "✓ RESULT: LOW (liquid ${(difference * 100)}% below)")
                    "low"
                }
                else -> {
                    android.util.Log.d("GuinnessApp", "✓ RESULT: PERFECT (within word height)")
                    "perfect"
                }
            }
            
            android.util.Log.d("GuinnessApp", "====================================================")
            return result
        }

        // Advanced detection using edge detection-like approach
        fun analyzeImageAdvanced(imagePath: String): String {
            try {
                val bitmap = BitmapFactory.decodeFile(imagePath)
                if (bitmap == null) {
                    throw Exception("Could not load image")
                }

                // Detect logo using edge-like patterns
                val logoY = detectLogoAdvanced(bitmap)

                // Detect liquid using color analysis
                val liquidY = detectLiquidLevelAdvanced(bitmap)

                return compareLevels(logoY, liquidY)
            } catch (e: Exception) {
                throw Exception("Advanced image processing error: ${e.message}")
            }
        }

        // Overloaded version with manual GUINNESS position
        fun analyzeImageAdvanced(imagePath: String, manualGuinnessPosition: Double): String {
            try {
                android.util.Log.d("GuinnessApp", "Using MANUAL GUINNESS position: $manualGuinnessPosition")
                
                val bitmap = BitmapFactory.decodeFile(imagePath)
                if (bitmap == null) {
                    throw Exception("Could not load image")
                }

                // Use manual position instead of detecting
                val logoY = manualGuinnessPosition

                // Detect liquid using color analysis
                val liquidY = detectLiquidLevelAdvanced(bitmap)
                
                android.util.Log.d("GuinnessApp", "Manual logoY: $logoY, Detected liquidY: $liquidY")

                return compareLevels(logoY, liquidY)
            } catch (e: Exception) {
                android.util.Log.e("GuinnessApp", "Error: ${e.message}")
                throw Exception("Advanced image processing error: ${e.message}")
            }
        }

        private fun detectLogoAdvanced(bitmap: Bitmap): Double {
            val height = bitmap.height.toDouble()
            val width = bitmap.width.toDouble()

            val startY = (height * 0.15).toInt()
            val endY = (height * 0.55).toInt()

            val horizontalIntensityVariations = mutableListOf<Int>()

            for (y in startY until endY) {
                var variationCount = 0
                val startX = (width * 0.25).toInt()
                val endX = (width * 0.75).toInt()

                var prevIntensity = -1
                for (x in startX until endX) {
                    val pixel = bitmap.getPixel(x, y)
                    val r = Color.red(pixel)
                    val g = Color.green(pixel)
                    val b = Color.blue(pixel)
                    val intensity = ((r + g + b) / 3).toInt()

                    // Detect intensity changes (like edges)
                    if (prevIntensity >= 0 && kotlin.math.abs(intensity - prevIntensity) > 30) {
                        variationCount++
                    }
                    prevIntensity = intensity
                }
                horizontalIntensityVariations.add(variationCount)
            }

            // Find peak in variations (likely logo area with text edges)
            var maxVariations = 0
            var logoIndex = 0
            for (i in horizontalIntensityVariations.indices) {
                if (horizontalIntensityVariations[i] > maxVariations) {
                    maxVariations = horizontalIntensityVariations[i]
                    logoIndex = i
                }
            }

            val logoY = startY + logoIndex
            return logoY / height
        }

        private fun detectLiquidLevelAdvanced(bitmap: Bitmap): Double {
            val height = bitmap.height.toDouble()
            val width = bitmap.width.toDouble()

            // Find the TOP EDGE of dark liquid (black beer)
            // This is where dark beer ends and light foam begins
            val darkThreshold = 50.0 // Very dark beer (almost black)
            val lightThreshold = 150.0 // Light foam

            val startX = (width * 0.35).toInt()
            val endX = (width * 0.65).toInt()

            // Find bottom of dark liquid first
            var darkLiquidBottom = height.toInt() - 1
            for (y in (height - 1).toInt() downTo (height * 0.7).toInt()) {
                var darkCount = 0
                var sampleCount = 0
                for (x in startX until endX) {
                    val pixel = bitmap.getPixel(x, y)
                    val r = Color.red(pixel)
                    val g = Color.green(pixel)
                    val b = Color.blue(pixel)
                    val brightness = (r + g + b) / 3.0
                    sampleCount++
                    if (brightness < darkThreshold) {
                        darkCount++
                    }
                }
                if (darkCount > sampleCount * 0.6) {
                    darkLiquidBottom = y
                    break
                }
            }

            // Scan from bottom UP to find top edge of dark liquid
            for (y in darkLiquidBottom downTo 0) {
                var darkCount = 0
                var lightCount = 0
                var totalPixels = 0

                for (x in startX until endX) {
                    val pixel = bitmap.getPixel(x, y)
                    val r = Color.red(pixel)
                    val g = Color.green(pixel)
                    val b = Color.blue(pixel)
                    val brightness = (r + g + b) / 3.0
                    totalPixels++

                    if (brightness < darkThreshold) {
                        darkCount++
                    } else if (brightness > lightThreshold) {
                        lightCount++
                    }
                }

                // If we're in dark region and see light above, this is the boundary
                if (darkCount > totalPixels * 0.5 && y > 5) {
                    var transitionFound = true
                    for (checkY in (y - 5).coerceAtLeast(0) until y) {
                        var checkLight = 0
                        for (checkX in startX until endX) {
                            val pixel = bitmap.getPixel(checkX, checkY)
                            val r = Color.red(pixel)
                            val g = Color.green(pixel)
                            val b = Color.blue(pixel)
                            val brightness = (r + g + b) / 3.0
                            if (brightness > lightThreshold) {
                                checkLight++
                            }
                        }
                        if (checkLight < totalPixels * 0.3) {
                            transitionFound = false
                            break
                        }
                    }
                    if (transitionFound) {
                        return y / height
                    }
                }
            }

            return 0.5
        }
    }
}
