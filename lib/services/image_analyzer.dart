import 'dart:io';
import 'package:image/image.dart' as img;
import 'opencv_service.dart';
import 'analysis_result.dart';

// Re-export DrinkLevel from opencv_service for backward compatibility
export 'opencv_service.dart' show DrinkLevel;
export 'analysis_result.dart' show AnalysisResult;

class ImageAnalyzer {
  /// Analyzes the image using OpenCV (preferred) or fallback to basic processing
  /// Returns the drink level status
  static Future<DrinkLevel> analyzeImage(String imagePath) async {
    final result = await analyzeImageWithDetails(imagePath);
    return result.level;
  }

  /// Analyzes image and returns detailed result with positions
  static Future<AnalysisResult> analyzeImageWithDetails(
    String imagePath,
  ) async {
    try {
      // Try platform channel OpenCV first (Android/iOS) - best performance
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          final level = await OpenCVService.analyzeImage(imagePath);
          // Get positions from fallback for line display
          final positions = await _getPositions(imagePath);
          return AnalysisResult(
            level: level,
            darkLiquidTopPosition: positions['darkLiquidTop'] as double,
            guinnessWordPosition: positions['guinnessWord'] as double,
          );
        } catch (e) {
          print('Platform OpenCV failed, using fallback: $e');
        }
      }

      // Fallback: Basic image processing
      return await _analyzeImageBasic(imagePath);
    } catch (e) {
      throw Exception('Error analyzing image: $e');
    }
  }

  /// Get positions for line display
  static Future<Map<String, double>> _getPositions(
    String imagePath, {
    double? manualGuinnessPosition,
  }) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        throw Exception('Could not decode image');
      }

      // Detect liquid level using image processing
      final glassParts = _detectGlassParts(image);
      final darkLiquidTop = glassParts['darkLiquidTop'] as double;

      // Use manual position if provided, otherwise use fixed 50%
      final guinnessWordPosition = manualGuinnessPosition ?? 0.50;

      print(
        'Using GUINNESS position: $guinnessWordPosition ${manualGuinnessPosition != null ? "(Manual)" : "(Default)"}',
      );
      print('Dark liquid top: $darkLiquidTop');

      return {
        'guinnessWord': guinnessWordPosition,
        'darkLiquidTop': darkLiquidTop,
      };
    } catch (e) {
      print('Position detection error: $e');
      return {
        'guinnessWord': manualGuinnessPosition ?? 0.50,
        'darkLiquidTop': 0.5,
      };
    }
  }

  /// Basic image analysis (fallback method)
  static Future<AnalysisResult> _analyzeImageBasic(String imagePath) async {
    try {
      // Read image file
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        throw Exception('Could not decode image');
      }

      // Detect GUINNESS word position
      final guinnessWordPosition = _detectGuinnessWord(image);

      // Detect 2 parts of glass: black drink and foam
      final glassParts = _detectGlassParts(image);

      // Get dark liquid (black drink) top edge
      final darkLiquidTop = glassParts['darkLiquidTop'] as double;

      // Compare GUINNESS word with dark liquid level
      final level = _compareLevels(guinnessWordPosition, darkLiquidTop);

      return AnalysisResult(
        level: level,
        darkLiquidTopPosition: darkLiquidTop,
        guinnessWordPosition: guinnessWordPosition,
      );
    } catch (e) {
      throw Exception('Error in basic analysis: $e');
    }
  }

  /// Detects the GUINNESS word position
  static double _detectGuinnessWord(img.Image image) {
    // Convert to grayscale
    final gray = img.grayscale(img.copyResize(image, width: 400));
    final height = gray.height;
    final width = gray.width;

    // Focus on LOWER portion (35% to 70% of height) where GUINNESS word on black label is
    // Not the top foam area!
    final startY = (height * 0.35).round();
    final endY = (height * 0.70).round();
    final startX = (width * 0.3).round();
    final endX = (width * 0.7).round();

    // Look for white text on DARK background - GUINNESS word on black label
    List<Map<String, dynamic>> candidateRows = [];

    for (int y = startY; y < endY; y++) {
      int brightPixels = 0;
      int darkPixels = 0;
      int totalPixels = 0;
      int rowIntensity = 0;
      int consecutiveBright = 0;
      int maxConsecutiveBright = 0;

      for (int x = startX; x < endX; x++) {
        final pixel = gray.getPixel(x, y);
        final intensity = (img.getLuminance(pixel) * 255).round();
        totalPixels++;
        rowIntensity += intensity;

        // White/light pixels (GUINNESS word text)
        if (intensity > 180) {
          brightPixels++;
          consecutiveBright++;
          maxConsecutiveBright = consecutiveBright > maxConsecutiveBright
              ? consecutiveBright
              : maxConsecutiveBright;
        } else {
          consecutiveBright = 0;
          // Count dark background pixels
          if (intensity < 80) {
            darkPixels++;
          }
        }
      }

      // Calculate metrics for GUINNESS word detection
      final brightRatio = brightPixels / totalPixels;
      final darkRatio = darkPixels / totalPixels;
      final avgIntensity = rowIntensity / totalPixels;

      // GUINNESS word: white text on BLACK background
      // Must have dark background (not foam which is light)
      if (brightRatio > 0.08 &&
          darkRatio > 0.30 && // Must have significant dark background
          avgIntensity < 120 && // Overall row should be dark (not foam)
          maxConsecutiveBright > 10) {
        candidateRows.add({
          'y': y,
          'brightRatio': brightRatio,
          'darkRatio': darkRatio,
          'avgIntensity': avgIntensity,
          'score': brightRatio * darkRatio * 100 * (maxConsecutiveBright / 10),
        });
      }
    }

    // Find the best candidate (highest score)
    if (candidateRows.isNotEmpty) {
      candidateRows.sort(
        (a, b) => (b['score'] as double).compareTo(a['score'] as double),
      );
      final logoY = candidateRows.first['y'] as int;

      // Find center of GUINNESS word by checking surrounding rows
      int totalY = logoY;
      int count = 1;

      for (int offset = 1; offset <= 15; offset++) {
        if (logoY + offset < endY) {
          final checkY = logoY + offset;
          int brightCount = 0;
          int darkCount = 0;
          for (int x = startX; x < endX; x++) {
            final pixel = gray.getPixel(x, checkY);
            final intensity = (img.getLuminance(pixel) * 255).round();
            if (intensity > 180) {
              brightCount++;
            } else if (intensity < 80) {
              darkCount++;
            }
          }
          // Must have both bright text and dark background
          if (brightCount > (endX - startX) * 0.08 &&
              darkCount > (endX - startX) * 0.25) {
            totalY += checkY;
            count++;
          }
        }
        if (logoY - offset >= startY) {
          final checkY = logoY - offset;
          int brightCount = 0;
          int darkCount = 0;
          for (int x = startX; x < endX; x++) {
            final pixel = gray.getPixel(x, checkY);
            final intensity = (img.getLuminance(pixel) * 255).round();
            if (intensity > 180) {
              brightCount++;
            } else if (intensity < 80) {
              darkCount++;
            }
          }
          // Must have both bright text and dark background
          if (brightCount > (endX - startX) * 0.08 &&
              darkCount > (endX - startX) * 0.25) {
            totalY += checkY;
            count++;
          }
        }
      }

      final avgLogoY = totalY / count;
      return avgLogoY / height;
    }

    // Fallback: if no clear GUINNESS word found, assume middle position on label
    return 0.50;
  }

  /// IMPROVED: Multi-point sampling for accurate liquid detection
  static Map<String, double> _detectGlassParts(img.Image image) {
    final height = image.height;
    final width = image.width;

    // Sample at MULTIPLE vertical lines for better accuracy
    final samplePositions = [
      width * 0.45, // Left-center
      width * 0.50, // Exact center
      width * 0.55, // Right-center
    ];

    List<double> detectedPositions = [];

    for (double xRatio in samplePositions) {
      final sampleX = xRatio.round().clamp(0, width - 1);
      final position = _detectLiquidAtVerticalLine(image, sampleX, height);
      if (position != null) {
        detectedPositions.add(position);
        print(
          'Detected at X: $sampleX (${(xRatio / width * 100).toStringAsFixed(0)}%): ${(position * 100).toStringAsFixed(1)}%',
        );
      }
    }

    // Use median for robustness (handles outliers)
    if (detectedPositions.isNotEmpty) {
      detectedPositions.sort();
      final median = detectedPositions[detectedPositions.length ~/ 2];
      print(
        'Final liquid position (median): ${(median * 100).toStringAsFixed(1)}% from ${detectedPositions.length} samples',
      );
      return {'darkLiquidTop': median};
    }

    // Fallback
    print('Liquid detection failed, using default 50%');
    return {'darkLiquidTop': 0.50};
  }

  /// Detect liquid position at a specific vertical line
  static double? _detectLiquidAtVerticalLine(
    img.Image image,
    int x,
    int height,
  ) {
    // Scan from TOP to BOTTOM
    // Strategy: Find foam first, then dark liquid below it

    bool foundFoam = false;
    int foamStartY = 0;

    // Step 1: Find foam region (light/cream colored)
    for (int y = (height * 0.1).round(); y < (height * 0.7).round(); y++) {
      final pixel = image.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      final brightness = (r + g + b) / 3;

      // Foam: light colored (brightness 100-220) with yellow/cream tint
      if (!foundFoam && brightness > 100 && brightness < 220) {
        // Check for cream/yellow tint (R+G > B)
        if ((r + g) / 2 > b * 1.05) {
          foundFoam = true;
          foamStartY = y;
          break;
        }
      }
    }

    // Step 2: If foam found, scan below it for dark liquid
    if (foundFoam) {
      for (int y = foamStartY; y < (height * 0.9).round(); y++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final brightness = (r + g + b) / 3;

        // Very dark = black liquid (Guinness)
        if (brightness < 50) {
          // Verify it's consistently dark for next 15 pixels
          int darkCount = 0;
          for (
            int verifyY = y;
            verifyY < (y + 15).clamp(0, height);
            verifyY++
          ) {
            final verifyPixel = image.getPixel(x, verifyY);
            final verifyBrightness =
                (verifyPixel.r.toInt() +
                    verifyPixel.g.toInt() +
                    verifyPixel.b.toInt()) /
                3;
            if (verifyBrightness < 50) darkCount++;
          }

          // Need at least 10 dark pixels out of 15 (consistent dark region)
          if (darkCount >= 10) {
            return y / height;
          }
        }
      }
    } else {
      // No foam found - directly look for dark liquid from top
      for (int y = (height * 0.2).round(); y < (height * 0.9).round(); y++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final brightness = (r + g + b) / 3;

        // Very dark = black liquid
        if (brightness < 45) {
          // Verify consistency
          int darkCount = 0;
          for (
            int verifyY = y;
            verifyY < (y + 15).clamp(0, height);
            verifyY++
          ) {
            final verifyPixel = image.getPixel(x, verifyY);
            final verifyBrightness =
                (verifyPixel.r.toInt() +
                    verifyPixel.g.toInt() +
                    verifyPixel.b.toInt()) /
                3;
            if (verifyBrightness < 45) darkCount++;
          }

          if (darkCount >= 10) {
            return y / height;
          }
        }
      }
    }

    return null;
  }

  /// Compares GUINNESS word position and dark liquid level
  static DrinkLevel _compareLevels(
    double guinnessWordPosition,
    double darkLiquidTop,
  ) {
    // Image coordinates: Y=0 is TOP, Y=1 is BOTTOM
    // So smaller Y value = HIGHER in image (UPER)
    // Larger Y value = LOWER in image (NEECHE)

    // If darkLiquidTop < guinnessWordPosition = liquid is ABOVE/UPER = HIGH
    // If darkLiquidTop > guinnessWordPosition = liquid is BELOW/NEECHE = LOW

    // PERFECT zone = GUINNESS word ki height (estimated 3-4% of glass height)
    // GUINNESS word typically 3-4% tall hai glass par
    const wordHeightHalf = 0.02; // Half of word height (±2% = 4% total height)

    const lowThreshold = wordHeightHalf; // Below word bottom edge
    const highThreshold = -wordHeightHalf; // Above word top edge

    final difference = darkLiquidTop - guinnessWordPosition;

    // Debug print
    print('');
    print('==================== COMPARISON ====================');
    print('GUINNESS Word: ${guinnessWordPosition.toStringAsFixed(3)}');
    print('Dark Liquid Top: ${darkLiquidTop.toStringAsFixed(3)}');
    print('Difference: ${difference.toStringAsFixed(3)}');
    print('highThreshold: $highThreshold (if diff < this = HIGH)');
    print('lowThreshold: $lowThreshold (if diff > this = LOW)');
    print(
      'PERFECT zone: ${(guinnessWordPosition - wordHeightHalf).toStringAsFixed(3)} to ${(guinnessWordPosition + wordHeightHalf).toStringAsFixed(3)}',
    );
    print('');
    print(
      'Check: difference ($difference) < highThreshold ($highThreshold) = ${difference < highThreshold}',
    );
    print(
      'Check: difference ($difference) > lowThreshold ($lowThreshold) = ${difference > lowThreshold}',
    );
    print('');

    if (difference < highThreshold) {
      // Dark liquid is ABOVE GUINNESS word top edge (smaller Y value) = HIGH
      print(
        '✓ RESULT: HIGH (liquid ${(-difference * 100).toStringAsFixed(1)}% above GUINNESS word)',
      );
      print('====================================================');
      return DrinkLevel.high;
    } else if (difference > lowThreshold) {
      // Dark liquid is BELOW GUINNESS word bottom edge (larger Y value) = LOW
      print(
        '✓ RESULT: LOW (liquid ${(difference * 100).toStringAsFixed(1)}% below GUINNESS word)',
      );
      print('====================================================');
      return DrinkLevel.low;
    } else {
      // Dark liquid is within GUINNESS word height (perfect range)
      print(
        '✓ RESULT: PERFECT (liquid within GUINNESS word height, diff: ${(difference * 100).toStringAsFixed(1)}%)',
      );
      print('====================================================');
      return DrinkLevel.perfect;
    }
  }

  /// Enhanced detection using OpenCV (preferred) or advanced fallback
  static Future<DrinkLevel> analyzeImageAdvanced(String imagePath) async {
    final result = await analyzeImageAdvancedWithDetails(imagePath);
    return result.level;
  }

  /// Enhanced detection with details
  /// If manualGuinnessPosition is provided, uses that instead of auto-detection
  static Future<AnalysisResult> analyzeImageAdvancedWithDetails(
    String imagePath, {
    double? manualGuinnessPosition,
  }) async {
    try {
      // ALWAYS use Dart fallback when manual position is provided (for accurate comparison)
      // Skip Android native to avoid comparison issues
      if (false &&
          (Platform.isAndroid || Platform.isIOS) &&
          manualGuinnessPosition == null) {
        try {
          final level = await OpenCVService.analyzeImage(
            imagePath,
            manualGuinnessPosition: manualGuinnessPosition,
          );
          // Get positions from fallback for line display
          final positions = await _getPositions(
            imagePath,
            manualGuinnessPosition: manualGuinnessPosition,
          );
          return AnalysisResult(
            level: level,
            darkLiquidTopPosition: positions['darkLiquidTop'] as double,
            guinnessWordPosition: positions['guinnessWord'] as double,
          );
        } catch (e) {
          print('Platform OpenCV failed, using fallback: $e');
        }
      }

      // Always use Dart fallback when manual position is provided (more reliable)
      print('Using Dart fallback (manual position provided or OpenCV failed)');

      // Fallback: Advanced image processing
      return await _analyzeImageAdvancedFallback(
        imagePath,
        manualGuinnessPosition: manualGuinnessPosition,
      );
    } catch (e) {
      throw Exception('Error in advanced analysis: $e');
    }
  }

  /// Advanced fallback detection
  static Future<AnalysisResult> _analyzeImageAdvancedFallback(
    String imagePath, {
    double? manualGuinnessPosition,
  }) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        throw Exception('Could not decode image');
      }

      // Use manual position if provided, otherwise detect
      final guinnessWordPosition =
          manualGuinnessPosition ?? _detectGuinnessWord(image);

      print('=== FALLBACK ANALYSIS ===');
      print('Manual position provided: ${manualGuinnessPosition != null}');
      print('GUINNESS position to use: $guinnessWordPosition');

      // Detect 2 parts of glass
      final glassParts = _detectGlassParts(image);
      final darkLiquidTop = glassParts['darkLiquidTop'] as double;

      print('Dark liquid top detected: $darkLiquidTop');

      // Compare
      final level = _compareLevels(guinnessWordPosition, darkLiquidTop);

      print('Final level from comparison: $level');
      print('===========================');

      return AnalysisResult(
        level: level,
        darkLiquidTopPosition: darkLiquidTop,
        guinnessWordPosition: guinnessWordPosition,
      );
    } catch (e) {
      throw Exception('Error in advanced fallback: $e');
    }
  }
}
