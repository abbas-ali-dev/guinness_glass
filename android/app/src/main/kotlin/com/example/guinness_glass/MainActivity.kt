package com.example.guinness_glass

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.guinness_glass/opencv"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Note: For full OpenCV support, initialize here:
        // if (!OpenCVLoader.initLocal()) {
        //     // Handle initialization failure
        // }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "analyzeImage" -> {
                    val imagePath = call.argument<String>("imagePath")
                    val manualGuinnessPosition = call.argument<Double>("manualGuinnessPosition")
                    
                    if (imagePath != null) {
                        try {
                            val level = if (manualGuinnessPosition != null) {
                                OpenCVProcessor.analyzeImageAdvanced(imagePath, manualGuinnessPosition)
                            } else {
                                OpenCVProcessor.analyzeImageAdvanced(imagePath)
                            }
                            result.success(level)
                        } catch (e: Exception) {
                            result.error("ANALYSIS_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Image path is null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
