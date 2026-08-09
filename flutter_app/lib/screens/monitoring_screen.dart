import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/alert_service.dart';
import '../services/camera_processor.dart';
import '../services/drowsiness_pipeline.dart';
import '../services/model_manager.dart';

/// Points 22, 23, 24, 25: Main Monitoring Screen
/// Fullscreen camera preview, animated status pill, 30s calibration bar, and full-screen alarm overlay.
class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  final ModelManager _modelManager = ModelManager();
  final CameraProcessor _cameraProcessor = CameraProcessor();
  late DrowsinessPipeline _pipeline;
  final AlertService _alertService = AlertService();

  bool _isLoading = true;
  String _statusMessage = 'Initializing camera and models...';
  Timer? _processingTimer;

  @override
  void initState() {
    super.initState();
    _pipeline = DrowsinessPipeline(modelManager: _modelManager);
    _initializeAll();
  }

  Future<void> _initializeAll() async {
    try {
      setState(() => _statusMessage = 'Loading TFLite models...');
      await _modelManager.loadModels();

      setState(() => _statusMessage = 'Initializing front camera...');
      await _cameraProcessor.initializeCamera();

      setState(() => _isLoading = false);

      // Start 1-second live inference loop
      _startInferenceLoop();
    } catch (e) {
      setState(() {
        _statusMessage = 'Error starting app: $e';
      });
    }
  }

  /// 1-second periodic loop running:
  /// ML Kit Face Crop -> CNN TFLite Embedding -> 30s Calibration / Normalization -> Sequence Buffer -> LSTM TFLite -> Alert Trigger
  void _startInferenceLoop() {
    _processingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _processSingleFrame();
    });
  }

  Future<void> _processSingleFrame() async {
    if (!_cameraProcessor.isInitialized ||
        _cameraProcessor.controller == null ||
        !_cameraProcessor.controller!.value.isInitialized) {
      return;
    }

    try {
      // 1. Capture photo, run ML Kit face detection, crop face with 20px padding, resize 224x224, normalize /255.0
      final inputTensor = await _cameraProcessor.processNextFrameTensor();
      if (inputTensor == null) {
        print('No face detected in this frame.');
        return;
      }

      // 2. Run CNN TFLite interpreter to extract 512-dim spatial embedding
      final List<double> embedding = _modelManager.runCnnInference(inputTensor);

      // 3. Pass embedding to calibration / rolling buffer pipeline
      _pipeline.processEmbedding(embedding);

      // 4. Update alert audio/vibration state
      if (mounted) {
        setState(() {
          _alertService.updateAlertState(
            _pipeline.currentState,
            onEscalateToDrowsy: () {
              if (mounted) setState(() {});
            },
          );
        });
      }
    } catch (e) {
      print('Inference loop error: $e');
    }
  }

  @override
  void dispose() {
    _processingTimer?.cancel();
    _alertService.dispose();
    _cameraProcessor.dispose();
    _modelManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.blueAccent),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    final isCalibrated = _pipeline.isCalibrated;
    final progress = _pipeline.calibrationProgress;
    final state = _pipeline.currentState;
    final isDrowsyActive = _alertService.isDrowsyAlertActive;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Point 22: Fullscreen Camera Preview
          Positioned.fill(
            child: CameraPreview(_cameraProcessor.controller!),
          ),

          // Point 22 & 23: Top Status Pill & Calibration Progress
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Status Bar Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      // Point 23: Animated Status Indicator Pill
                      _buildStatusPill(isCalibrated, state),
                      const SizedBox(width: 48), // Balance back button
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Point 22: Calibration Progress Bar (first 30s)
                  if (!isCalibrated) _buildCalibrationBar(progress),
                ],
              ),
            ),
          ),

          // Point 24: Fullscreen Red Overlay for Drowsy Alert
          if (isDrowsyActive) _buildDrowsyAlarmOverlay(),
        ],
      ),
    );
  }

  /// Point 23: AnimatedContainer for status pill (Alert=Green, LowVigilant=Amber, Drowsy=Red)
  Widget _buildStatusPill(bool isCalibrated, DrowsinessState state) {
    Color color;
    String text;
    IconData icon;

    if (!isCalibrated) {
      color = Colors.blueAccent;
      text = 'CALIBRATING';
      icon = Icons.sync_rounded;
    } else {
      switch (state) {
        case DrowsinessState.alert:
          color = Colors.green;
          text = 'ALERT';
          icon = Icons.check_circle_outline;
          break;
        case DrowsinessState.lowVigilant:
          color = Colors.amber.shade800;
          text = 'LOW VIGILANT';
          icon = Icons.warning_amber_rounded;
          break;
        case DrowsinessState.drowsy:
          color = Colors.red;
          text = 'DROWSY';
          icon = Icons.dangerous_rounded;
          break;
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 12,
            spreadRadius: 2,
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  /// Point 22: Calibration Progress Bar Indicator
  Widget _buildCalibrationBar(int progress) {
    final double percent = (progress / 30.0).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Learning Baseline...',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Text(
                '$progress / 30s',
                style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.white24,
              color: Colors.blueAccent,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  /// Point 24: Fullscreen Red Overlay with Dismiss Button
  Widget _buildDrowsyAlarmOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.red.withOpacity(0.92),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.warning_rounded,
              size: 96,
              color: Colors.white,
            ),
            const SizedBox(height: 24),
            const Text(
              'STOP!',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'DROWSINESS DETECTED',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 6,
                ),
                onPressed: () {
                  setState(() {
                    _alertService.dismissDrowsyAlert();
                  });
                },
                child: const Text(
                  'DISMISS',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
