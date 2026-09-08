import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/trip_session.dart';
import '../services/alert_service.dart';
import '../services/camera_processor.dart';
import '../services/drowsiness_pipeline.dart';
import '../services/model_manager.dart';
import '../services/settings_service.dart';
import '../services/trip_storage_service.dart';
import '../widgets/status_pill.dart';
import '../widgets/vigilance_gauge.dart';
import 'trip_summary_screen.dart';

/// Fullscreen live driving monitoring screen.
/// Runs camera capture, CNN feature extraction, LSTM inference,
/// live vigilance gauge, and high-priority red alert overlay.
class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  final ModelManager _modelManager = ModelManager();
  final CameraProcessor _cameraProcessor = CameraProcessor();
  late DrowsinessPipeline _pipeline;
  late AlertService _alertService;

  bool _isLoading = true;
  String _statusMessage = 'Initializing AI models and camera...';
  Timer? _processingTimer;
  Timer? _tripTimer;
  int _tripSeconds = 0;
  final DateTime _sessionStart = DateTime.now();

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();

    _alertService = AlertService(settingsService: settings);
    _pipeline = DrowsinessPipeline(
      modelManager: _modelManager,
      smoothingWindowSize: settings.smoothingWindow,
    );

    // Setup Emergency SOS listener
    _alertService.onEmergencySosTriggered = _onSosTriggered;

    _initializePipeline();
  }

  Future<void> _initializePipeline() async {
    try {
      setState(() => _statusMessage = 'Loading CNN & LSTM TFLite models...');
      await _modelManager.loadModels();

      setState(() => _statusMessage = 'Initializing front camera feed...');
      await _cameraProcessor.initializeCamera();

      if (!mounted) return;
      setState(() => _isLoading = false);

      // Start 1-second inference loop
      _startInferenceLoop();

      // Start trip timer
      _tripTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _tripSeconds++);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error initializing: $e';
        });
      }
    }
  }

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
      // 1. Capture front camera frame & extract 20px padded 224x224 normalized face tensor
      final inputTensor = await _cameraProcessor.processNextFrameTensor();
      if (inputTensor == null) return; // No face detected in frame

      // 2. Run CNN feature extractor -> 512-dim embedding
      final List<double> embedding = _modelManager.runCnnInference(inputTensor);

      // 3. Process through calibration / rolling buffer / LSTM pipeline
      _pipeline.processEmbedding(embedding);

      // 4. Update audio and vibration alert
      if (mounted) {
        setState(() {
          _alertService.updateAlertState(_pipeline.currentState);
        });
      }
    } catch (e) {
      debugPrint('Inference frame loop error: $e');
    }
  }

  void _onSosTriggered() {
    final contact = context.read<SettingsService>().emergencyContact;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFEF4444),
        duration: const Duration(seconds: 8),
        content: Text(
          contact.isNotEmpty
              ? 'EMERGENCY SOS: Notifying $contact of unresponsive driver!'
              : 'EMERGENCY SOS: Unresponsive driver detected!',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> _endTrip() async {
    // Stop timers
    _processingTimer?.cancel();
    _tripTimer?.cancel();
    _alertService.dismissDrowsyAlert();

    // Calculate average vigilance
    double avgScore = 100.0;
    if (_pipeline.timeline.isNotEmpty) {
      final total = _pipeline.timeline.map((p) => p.vigilanceScore).reduce((a, b) => a + b);
      avgScore = total / _pipeline.timeline.length;
    }

    // Construct TripSession
    final session = TripSession(
      id: const Uuid().v4(),
      startTime: _sessionStart,
      durationSeconds: _tripSeconds > 0 ? _tripSeconds : 1,
      drowsyEventsCount: _pipeline.drowsyEventsCount,
      averageVigilance: avgScore,
      timeline: _pipeline.timeline,
    );

    // Save to Hive
    await context.read<TripStorageService>().saveTrip(session);

    if (!mounted) return;

    // Navigate to TripSummaryScreen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TripSummaryScreen(session: session),
      ),
    );
  }

  String _formatTimer(int totalSecs) {
    final mins = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSecs % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  void dispose() {
    _processingTimer?.cancel();
    _tripTimer?.cancel();
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
              const CircularProgressIndicator(color: Color(0xFF38BDF8)),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    final isCalibrated = _pipeline.isCalibrated;
    final calProgress = _pipeline.calibrationProgress;
    final state = _pipeline.currentState;
    final isDrowsyActive = _alertService.isDrowsyAlertActive;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Fullscreen Camera Preview
          Positioned.fill(
            child: CameraPreview(_cameraProcessor.controller!),
          ),

          // 2. Top HUD Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // End Trip Button
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                        ),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1E293B),
                              title: const Text('End Monitoring?', style: TextStyle(color: Colors.white)),
                              content: const Text(
                                'End session and generate your driving vigilance summary?',
                                style: TextStyle(color: Colors.white70),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('Continue Drive'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF38BDF8),
                                    foregroundColor: const Color(0xFF0F172A),
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: const Text('End Trip'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            _endTrip();
                          }
                        },
                      ),

                      // Animated Status Pill
                      StatusPill(state: state),

                      // Trip Timer Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.timer_outlined, color: Colors.white70, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              _formatTimer(_tripSeconds),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // 30-Second Baseline Calibration Progress Bar
                  if (!isCalibrated) ...[
                    const SizedBox(height: 12),
                    _buildCalibrationBar(calProgress),
                  ],
                ],
              ),
            ),
          ),

          // 3. Bottom HUD: Live Vigilance Gauge Widget (0–100%)
          Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: Column(
              children: [
                VigilanceGauge(
                  score: _pipeline.currentVigilanceScore,
                  isCalibrating: !isCalibrated,
                  size: 190,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    isCalibrated
                        ? 'Monitoring driver facial features • 1s inference'
                        : 'Please look forward while calibrating facial baseline',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // 4. Full-Screen Red Alert Overlay (identical for low vigilant and drowsy)
          if (isDrowsyActive) _buildRedAlertOverlay(),
        ],
      ),
    );
  }

  Widget _buildCalibrationBar(int progress) {
    final double percent = (progress / 30.0).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Learning Facial Baseline...',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Text(
                '$progress / 30s',
                style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              backgroundColor: Colors.white12,
              color: const Color(0xFF38BDF8),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRedAlertOverlay() {
    final sosSecs = _alertService.sosCountdownSeconds;

    return Positioned.fill(
      child: Container(
        color: const Color(0xFFEF4444).withValues(alpha: 0.95),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.warning_rounded,
              size: 100,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            const Text(
              'STOP!',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'SOS Alert Escalation in ${sosSecs}s',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFEF4444),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 8,
                ),
                onPressed: () {
                  setState(() {
                    _alertService.dismissDrowsyAlert();
                  });
                },
                child: const Text(
                  'DISMISS ALARM',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
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
