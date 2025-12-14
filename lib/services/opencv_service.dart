import 'package:flutter/services.dart';
import 'dart:io';

enum DrinkLevel { low, perfect, high }

class OpenCVService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.guinness_glass/opencv',
  );

  /// Analyzes image using OpenCV through platform channels
  /// Returns the drink level status
  /// If manualGuinnessPosition is provided, uses that for comparison
  static Future<DrinkLevel> analyzeImage(String imagePath, {double? manualGuinnessPosition}) async {
    try {
      if (!File(imagePath).existsSync()) {
        throw Exception('Image file does not exist');
      }

      final Map<String, dynamic> arguments = {
        'imagePath': imagePath,
      };
      
      // Add manual position if provided
      if (manualGuinnessPosition != null) {
        arguments['manualGuinnessPosition'] = manualGuinnessPosition;
      }

      final String result = await _channel.invokeMethod('analyzeImage', arguments);

      // Convert string result to DrinkLevel enum
      switch (result.toLowerCase()) {
        case 'low':
          return DrinkLevel.low;
        case 'perfect':
          return DrinkLevel.perfect;
        case 'high':
          return DrinkLevel.high;
        default:
          throw Exception('Unknown result: $result');
      }
    } on PlatformException catch (e) {
      throw Exception('OpenCV platform error: ${e.message}');
    } catch (e) {
      throw Exception('OpenCV analysis error: $e');
    }
  }
}
