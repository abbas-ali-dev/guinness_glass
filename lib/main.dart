import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'services/image_analyzer.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guinness Glass Analyzer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF000000), // Guinness black
          primary: const Color(0xFF000000),
          secondary: const Color(0xFFFFC72C), // Guinness gold
        ),
        useMaterial3: true,
      ),
      home: const GuinnessAnalyzerPage(),
    );
  }
}

class GuinnessAnalyzerPage extends StatefulWidget {
  const GuinnessAnalyzerPage({super.key});

  @override
  State<GuinnessAnalyzerPage> createState() => _GuinnessAnalyzerPageState();
}

class _GuinnessAnalyzerPageState extends State<GuinnessAnalyzerPage> {
  File? _selectedImage;
  DrinkLevel? _drinkLevel;
  bool _isAnalyzing = false;
  double? _darkLiquidTopPosition; // Position for red line (0.0 to 1.0)
  double? _guinnessWordPosition; // Position for green line (0.0 to 1.0)
  bool _needsCalibration = false; // Show tap instruction
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _drinkLevel = null; // Reset previous result
          _darkLiquidTopPosition = null; // Reset red line position
          _guinnessWordPosition = null; // Reset green line position
          _needsCalibration = true; // Show tap instruction
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
      }
    }
  }

  Future<void> _analyzeImage() async {
    if (_selectedImage == null) return;

    // Check if calibration is needed
    if (_guinnessWordPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please tap on GUINNESS word first!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _drinkLevel = null;
      _darkLiquidTopPosition = null;
    });

    try {
      // Use manual GUINNESS position
      final result = await ImageAnalyzer.analyzeImageAdvancedWithDetails(
        _selectedImage!.path,
        manualGuinnessPosition: _guinnessWordPosition,
      );

      print('=== FINAL RESULT ===');
      print(
        'GUINNESS (Green line): ${(_guinnessWordPosition! * 100).toStringAsFixed(1)}%',
      );
      print(
        'Liquid (Red line): ${(result.darkLiquidTopPosition * 100).toStringAsFixed(1)}%',
      );
      print(
        'Difference: ${((result.darkLiquidTopPosition - _guinnessWordPosition!) * 100).toStringAsFixed(1)}%',
      );
      print('Result: ${result.level.toString().split('.').last.toUpperCase()}');

      setState(() {
        _drinkLevel = result.level;
        _darkLiquidTopPosition = result.darkLiquidTopPosition;
        _isAnalyzing = false;
        _needsCalibration = false;
      });
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Analysis error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Get image size for accurate line positioning
  Future<Size> _getImageSize(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  }

  Widget _buildLevelIndicator() {
    if (_drinkLevel == null) return const SizedBox.shrink();

    Color levelColor;
    String levelText;
    IconData levelIcon;

    switch (_drinkLevel!) {
      case DrinkLevel.low:
        levelColor = Colors.orange;
        levelText = 'LOW';
        levelIcon = Icons.arrow_downward;
        break;
      case DrinkLevel.perfect:
        levelColor = Colors.green;
        levelText = 'PERFECT';
        levelIcon = Icons.check_circle;
        break;
      case DrinkLevel.high:
        levelColor = Colors.red;
        levelText = 'HIGH';
        levelIcon = Icons.arrow_upward;
        break;
    }

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: levelColor.withOpacity(0.1),
        border: Border.all(color: levelColor, width: 2),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(levelIcon, size: 50, color: levelColor),
          const SizedBox(height: 10),
          Text(
            levelText,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: levelColor,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _getLevelDescription(_drinkLevel!),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  String _getLevelDescription(DrinkLevel level) {
    switch (level) {
      case DrinkLevel.low:
        return 'Drink level is below the Guinness logo';
      case DrinkLevel.perfect:
        return 'Drink level is at the perfect position!';
      case DrinkLevel.high:
        return 'Drink level is above the Guinness logo';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Guinness Glass Analyzer',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Instructions
              Card(
                color: Colors.grey[100],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          const Text(
                            'How to use:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '1. Take or select a photo of your Guinness glass\n'
                        '2. Tap "Analyze Image" to check the drink level\n'
                        '3. See if your pour is LOW, PERFECT, or HIGH',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Image selection buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Camera'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.secondary,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Selected image display with horizontal line overlay
              if (_selectedImage != null) ...[
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return FutureBuilder<Size>(
                          future: _getImageSize(_selectedImage!),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return Image.file(
                                _selectedImage!,
                                fit: BoxFit.contain,
                                height: 300,
                              );
                            }

                            final imageSize = snapshot.data!;
                            final containerWidth = constraints.maxWidth;
                            final containerHeight = 300.0;

                            // Calculate actual displayed image size (with BoxFit.contain)
                            final imageAspectRatio =
                                imageSize.width / imageSize.height;
                            final containerAspectRatio =
                                containerWidth / containerHeight;

                            double displayedHeight;
                            double displayedWidth;
                            double offsetY = 0;
                            double offsetX = 0;

                            if (imageAspectRatio > containerAspectRatio) {
                              // Image is wider - fit to width
                              displayedWidth = containerWidth;
                              displayedHeight =
                                  containerWidth / imageAspectRatio;
                              offsetY = (containerHeight - displayedHeight) / 2;
                            } else {
                              // Image is taller - fit to height
                              displayedHeight = containerHeight;
                              displayedWidth =
                                  containerHeight * imageAspectRatio;
                              offsetX = (containerWidth - displayedWidth) / 2;
                            }

                            return Stack(
                              children: [
                                Image.file(
                                  _selectedImage!,
                                  fit: BoxFit.contain,
                                  height: 300,
                                ),
                                // Horizontal line at dark liquid top position
                                if (_darkLiquidTopPosition != null)
                                  Positioned(
                                    left: offsetX,
                                    right: offsetX,
                                    top:
                                        offsetY +
                                        (displayedHeight *
                                            _darkLiquidTopPosition!),
                                    child: Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.red.withOpacity(0.5),
                                            blurRadius: 4,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 20,
                                            height: 3,
                                            color: Colors.red,
                                          ),
                                          Expanded(
                                            child: Container(
                                              height: 1,
                                              color: Colors.red,
                                            ),
                                          ),
                                          Container(
                                            width: 20,
                                            height: 3,
                                            color: Colors.red,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                // Green horizontal line at GUINNESS word position
                                if (_guinnessWordPosition != null)
                                  Positioned(
                                    left: offsetX,
                                    right: offsetX,
                                    top:
                                        offsetY +
                                        (displayedHeight *
                                            _guinnessWordPosition!),
                                    child: Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.green.withOpacity(
                                              0.5,
                                            ),
                                            blurRadius: 4,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 20,
                                            height: 3,
                                            color: Colors.green,
                                          ),
                                          Expanded(
                                            child: Container(
                                              height: 1,
                                              color: Colors.green,
                                            ),
                                          ),
                                          Container(
                                            width: 20,
                                            height: 3,
                                            color: Colors.green,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                // Tap overlay for calibration
                                if (_needsCalibration &&
                                    _guinnessWordPosition == null)
                                  Positioned.fill(
                                    child: GestureDetector(
                                      onTapDown: (details) {
                                        // Calculate normalized Y position
                                        final localY = details.localPosition.dy;
                                        final normalizedY =
                                            (localY - offsetY) /
                                            displayedHeight;

                                        if (normalizedY >= 0 &&
                                            normalizedY <= 1) {
                                          setState(() {
                                            _guinnessWordPosition = normalizedY;
                                            _needsCalibration = false;
                                          });
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '✓ GUINNESS position set at ${(normalizedY * 100).toStringAsFixed(1)}%',
                                              ),
                                              backgroundColor: Colors.green,
                                              duration: const Duration(
                                                seconds: 2,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      child: Container(
                                        color: Colors.black.withOpacity(0.3),
                                        child: const Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.touch_app,
                                                color: Colors.white,
                                                size: 48,
                                              ),
                                              SizedBox(height: 10),
                                              Text(
                                                'TAP on GUINNESS word',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  shadows: [
                                                    Shadow(
                                                      blurRadius: 10,
                                                      color: Colors.black,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Calibration instruction or reset button
                if (_needsCalibration && _guinnessWordPosition == null)
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      border: Border.all(color: Colors.orange, width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange,
                          size: 24,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Step 1: Tap on the GUINNESS word to set position',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_guinnessWordPosition != null)
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            border: Border.all(color: Colors.green, width: 1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'GUINNESS position set at ${(_guinnessWordPosition! * 100).toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _guinnessWordPosition = null;
                            _needsCalibration = true;
                            _drinkLevel = null;
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Reset calibration',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 20),

                // Analyze button
                ElevatedButton(
                  onPressed: _isAnalyzing ? null : _analyzeImage,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isAnalyzing
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 10),
                            Text('Analyzing...'),
                          ],
                        )
                      : const Text(
                          'Analyze Image',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 20),

                // Level indicator
                _buildLevelIndicator(),
              ] else ...[
                // Placeholder when no image selected
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    border: Border.all(
                      color: Colors.grey[300]!,
                      width: 2,
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image_outlined,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No image selected',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
