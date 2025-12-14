import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// Service for detecting GUINNESS text using Google ML Kit
class TextRecognitionService {
  /// Detects the GUINNESS word position in the image using ML Kit
  /// Returns normalized Y position (0.0 to 1.0) or null if not found
  static Future<double?> detectGuinnessWordPosition(String imagePath) async {
    try {
      // First, preprocess image to enhance text visibility
      final enhancedImagePath = await _enhanceImageForOCR(imagePath);

      final inputImage = InputImage.fromFilePath(enhancedImagePath);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );

      final RecognizedText recognizedText = await textRecognizer.processImage(
        inputImage,
      );

      // Get original image dimensions
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      final image = await _decodeImageFromList(Uint8List.fromList(imageBytes));
      final imageHeight = image.height.toDouble();

      image.dispose();

      // Find "GUINNESS" text block
      double? guinnessY;
      double bestMatchScore = 0;

      // Debug: Print all detected text
      print('=== ML Kit Detected Text ===');
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          print('Text: "${line.text}" at Y: ${line.boundingBox.center.dy}');
        }
      }

      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          String text = line.text.toUpperCase().trim();

          // Check if line contains GUINNESS (with fuzzy matching)
          if (_matchesGuinness(text)) {
            // Calculate match score based on how well it matches
            double score = _calculateMatchScore(text);

            print('Found match: "$text" with score: $score');

            if (score > bestMatchScore) {
              bestMatchScore = score;
              // Get center Y position of the text
              final rect = line.boundingBox;
              guinnessY = (rect.top + rect.bottom) / 2.0;
            }
          }
        }
      }

      await textRecognizer.close();

      // Clean up enhanced image
      try {
        await File(enhancedImagePath).delete();
      } catch (_) {}

      if (guinnessY != null) {
        print(
          'GUINNESS found at Y: $guinnessY (normalized: ${guinnessY / imageHeight})',
        );
        // Return normalized position (0.0 to 1.0)
        return guinnessY / imageHeight;
      }

      print('GUINNESS not found by ML Kit');
      return null;
    } catch (e) {
      print('ML Kit text detection error: $e');
      return null;
    }
  }

  /// Enhance image for better OCR by increasing contrast and sharpness
  static Future<String> _enhanceImageForOCR(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      var image = img.decodeImage(bytes);

      if (image == null) {
        return imagePath; // Return original if can't decode
      }

      // Resize for faster processing
      if (image.width > 1000) {
        image = img.copyResize(image, width: 1000);
      }

      // Increase contrast to make text more visible
      image = img.adjustColor(image, contrast: 1.5, brightness: 1.1);

      // Apply edge detection/sharpening filter
      image = img.gaussianBlur(image, radius: 1);
      image = img.adjustColor(image, contrast: 1.3);

      // Save enhanced image temporarily
      final tempPath = imagePath
          .replaceAll('.jpg', '_enhanced.jpg')
          .replaceAll('.jpeg', '_enhanced.jpg')
          .replaceAll('.png', '_enhanced.png');

      final enhancedFile = File(tempPath);
      await enhancedFile.writeAsBytes(img.encodeJpg(image, quality: 95));

      return tempPath;
    } catch (e) {
      print('Image enhancement error: $e');
      return imagePath; // Return original on error
    }
  }

  /// Helper to decode image for dimensions
  static Future<ui.Image> _decodeImageFromList(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Checks if text matches GUINNESS (with some tolerance for OCR errors)
  static bool _matchesGuinness(String text) {
    // Exact match
    if (text.contains('GUINNESS')) return true;

    // Allow for common OCR errors
    final patterns = [
      'GUINNESS',
      'GUINESS', // Common misspelling
      'CUINNESS', // C/G confusion
      'GUINNES', // Missing S
      'GUINN', // Partial match
      'UINNESS', // Missing G
      'GUIN', // Very partial but might be enough
    ];

    for (String pattern in patterns) {
      if (text.contains(pattern)) {
        return true;
      }
    }

    // Check if at least 60% of "GUINNESS" characters are present
    if (text.length >= 4) {
      int matches = 0;
      String target = 'GUINNESS';
      for (int i = 0; i < text.length && i < target.length; i++) {
        if (text[i] == target[i]) matches++;
      }
      if (matches >= 5) return true; // At least 5 out of 8 characters match
    }

    return false;
  }

  /// Calculates match score (0.0 to 1.0) based on how well text matches GUINNESS
  static double _calculateMatchScore(String text) {
    if (text == 'GUINNESS') return 1.0;
    if (text.contains('GUINNESS')) return 0.95;
    if (text.contains('GUINESS')) return 0.9;
    if (text.contains('CUINNESS')) return 0.85;
    if (text.contains('GUINNES')) return 0.8;
    if (text.contains('GUINN')) return 0.7;

    // Calculate character similarity
    String target = 'GUINNESS';
    int matches = 0;
    int minLength = text.length < target.length ? text.length : target.length;

    for (int i = 0; i < minLength; i++) {
      if (text[i] == target[i]) matches++;
    }

    return matches / target.length;
  }
}
