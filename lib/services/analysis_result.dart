import 'opencv_service.dart';

class AnalysisResult {
  final DrinkLevel level;
  final double darkLiquidTopPosition; // Normalized position (0.0 to 1.0)
  final double guinnessWordPosition; // Normalized position (0.0 to 1.0)

  AnalysisResult({
    required this.level,
    required this.darkLiquidTopPosition,
    required this.guinnessWordPosition,
  });
}

