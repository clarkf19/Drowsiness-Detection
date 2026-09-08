import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/trip_session.dart';
import 'model_manager.dart';

/// App-level drowsiness safety state.
/// Both Low Vigilant and Drowsy model outputs trigger [drowsy] state.
enum DrowsinessState { calibrating, alert, drowsy }

class DrowsinessPipeline extends ChangeNotifier {
  final ModelManager modelManager;

  // Calibration state (first 30 frames / ~30s)
  bool _isCalibrated = false;
  final List<List<double>> _calibrationBuffer = [];
  List<double>? _meanVector;
  List<double>? _stdVector;

  // Rolling sequence buffer of 30 normalized embeddings
  final List<List<double>> _rollingBuffer = [];

  // Temporal smoothing window (default 3, range 2 to 5)
  int smoothingWindowSize = 3;
  final List<int> _predictionHistory = [];
  int _currentRawPrediction = 0; // 0=Alert, 1=Low Vigilant, 2=Drowsy
  DrowsinessState _currentState = DrowsinessState.calibrating;

  // Real-time metrics
  List<double> _lastSoftmaxScores = [1.0, 0.0, 0.0];
  double _currentVigilanceScore = 100.0; // 0.0 to 100.0%
  int _drowsyEventsCount = 0;
  bool _wasPreviousDrowsy = false;

  // Timeline tracking for trip analytics
  final List<VigilancePoint> _timeline = [];
  DateTime? _sessionStartTime;

  // Getters
  bool get isCalibrated => _isCalibrated;
  int get calibrationProgress => _calibrationBuffer.length; // 0 to 30
  DrowsinessState get currentState => _currentState;
  int get currentRawPrediction => _currentRawPrediction;
  List<double> get lastSoftmaxScores => List.unmodifiable(_lastSoftmaxScores);
  double get currentVigilanceScore => _currentVigilanceScore;
  int get drowsyEventsCount => _drowsyEventsCount;
  List<VigilancePoint> get timeline => List.unmodifiable(_timeline);

  DrowsinessPipeline({
    required this.modelManager,
    this.smoothingWindowSize = 3,
  });

  /// Reset the entire pipeline for a new session
  void reset({int? newSmoothingWindow}) {
    if (newSmoothingWindow != null) {
      smoothingWindowSize = newSmoothingWindow.clamp(2, 5);
    }
    _isCalibrated = false;
    _calibrationBuffer.clear();
    _meanVector = null;
    _stdVector = null;
    _rollingBuffer.clear();
    _predictionHistory.clear();
    _currentRawPrediction = 0;
    _currentState = DrowsinessState.calibrating;
    _lastSoftmaxScores = [1.0, 0.0, 0.0];
    _currentVigilanceScore = 100.0;
    _drowsyEventsCount = 0;
    _wasPreviousDrowsy = false;
    _timeline.clear();
    _sessionStartTime = DateTime.now();
    notifyListeners();
  }

  /// Process a newly extracted 512-dim embedding frame
  void processEmbedding(List<double> rawEmbedding) {
    if (rawEmbedding.length != 512) return;

    _sessionStartTime ??= DateTime.now();

    // 1. Calibration phase (first 30 frames)
    if (!_isCalibrated) {
      _calibrationBuffer.add(rawEmbedding);
      _currentState = DrowsinessState.calibrating;
      notifyListeners();

      if (_calibrationBuffer.length >= 30) {
        _computeSubjectNormalization();
        _isCalibrated = true;
        _currentState = DrowsinessState.alert;
        debugPrint('Subject calibration complete! Mean & std calculated.');
        notifyListeners();
      }
      return;
    }

    // 2. Apply Subject Normalization: (x - mean) / max(std, 1e-2)
    final List<double> normalizedEmbedding = List.filled(512, 0.0);
    for (int i = 0; i < 512; i++) {
      final double std = _stdVector![i] < 1e-2 ? 1e-2 : _stdVector![i];
      normalizedEmbedding[i] = (rawEmbedding[i] - _meanVector![i]) / std;
    }

    // 3. FIFO Rolling Buffer (max size 30)
    _rollingBuffer.add(normalizedEmbedding);
    if (_rollingBuffer.length > 30) {
      _rollingBuffer.removeAt(0);
    }

    // 4. Run LSTM Inference when rolling buffer has 30 frames
    if (_rollingBuffer.length == 30) {
      _runLstmInference();
    }
  }

  /// Compute mean and std vector across 30 calibration embeddings
  void _computeSubjectNormalization() {
    _meanVector = List.filled(512, 0.0);
    _stdVector = List.filled(512, 0.0);

    final int count = _calibrationBuffer.length;

    // Mean
    for (var emb in _calibrationBuffer) {
      for (int i = 0; i < 512; i++) {
        _meanVector![i] += emb[i];
      }
    }
    for (int i = 0; i < 512; i++) {
      _meanVector![i] /= count;
    }

    // Std
    for (var emb in _calibrationBuffer) {
      for (int i = 0; i < 512; i++) {
        final double diff = emb[i] - _meanVector![i];
        _stdVector![i] += diff * diff;
      }
    }
    for (int i = 0; i < 512; i++) {
      _stdVector![i] = sqrt(_stdVector![i] / count);
    }
  }

  /// Run LSTM sequence model, compute probabilities, and apply unified safety classification
  void _runLstmInference() {
    // Input tensor shape: [1, 30, 512]
    var inputSequenceTensor = List.generate(
      1,
      (_) => List.generate(
        30,
        (t) => _rollingBuffer[t],
      ),
    );

    final List<double> rawLogits = modelManager.runLstmInference(inputSequenceTensor);

    // Apply Softmax: [P(Alert), P(LowVigilant), P(Drowsy)]
    _lastSoftmaxScores = _softmax(rawLogits);

    // Argmax prediction: 0 = Alert, 1 = Low Vigilant, 2 = Drowsy
    int rawPrediction = 0;
    double maxProb = _lastSoftmaxScores[0];
    for (int i = 1; i < 3; i++) {
      if (_lastSoftmaxScores[i] > maxProb) {
        maxProb = _lastSoftmaxScores[i];
        rawPrediction = i;
      }
    }
    _currentRawPrediction = rawPrediction;

    // Vigilance Score Formula: P(Alert) * 100.0 (drops if either low vigilant or drowsy increases)
    _currentVigilanceScore = (_lastSoftmaxScores[0] * 100.0).clamp(0.0, 100.0);

    // Temporal smoothing
    _applyTemporalSmoothing(rawPrediction);

    // Record timeline datapoint
    final int elapsedSeconds = DateTime.now().difference(_sessionStartTime!).inSeconds;
    final bool isDrowsyNow = (_currentState == DrowsinessState.drowsy);

    // Track incident transition
    if (isDrowsyNow && !_wasPreviousDrowsy) {
      _drowsyEventsCount++;
    }
    _wasPreviousDrowsy = isDrowsyNow;

    _timeline.add(
      VigilancePoint(
        secondOffset: elapsedSeconds,
        vigilanceScore: _currentVigilanceScore,
        isDrowsy: isDrowsyNow,
      ),
    );

    notifyListeners();
  }

  /// Temporal smoothing: only change state if N consecutive predictions agree
  /// Note: Both class 1 (Low Vigilant) and class 2 (Drowsy) map to DrowsinessState.drowsy
  void _applyTemporalSmoothing(int rawPrediction) {
    // Binary safety mapping: 0 -> 0 (Alert), 1 or 2 -> 2 (Drowsy)
    final int safetyClass = (rawPrediction == 0) ? 0 : 2;

    _predictionHistory.add(safetyClass);
    if (_predictionHistory.length > smoothingWindowSize) {
      _predictionHistory.removeAt(0);
    }

    if (_predictionHistory.length == smoothingWindowSize) {
      final bool allAgree = _predictionHistory.every((p) => p == _predictionHistory.first);
      if (allAgree) {
        _currentState = (_predictionHistory.first == 0)
            ? DrowsinessState.alert
            : DrowsinessState.drowsy;
      }
    }
  }

  List<double> _softmax(List<double> logits) {
    final double maxLogit = logits.reduce(max);
    final List<double> expValues = logits.map((l) => exp(l - maxLogit)).toList();
    final double sumExp = expValues.reduce((a, b) => a + b);
    return expValues.map((e) => e / sumExp).toList();
  }
}
