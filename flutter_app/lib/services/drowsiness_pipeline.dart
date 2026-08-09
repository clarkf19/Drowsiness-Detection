import 'dart:math';
import 'model_manager.dart';

enum DrowsinessState { alert, lowVigilant, drowsy }

class DrowsinessPipeline {
  final ModelManager modelManager;

  // Calibration state (Point 17)
  bool _isCalibrated = false;
  final List<List<double>> _calibrationBuffer = [];
  List<double>? _meanVector;
  List<double>? _stdVector;

  // Rolling sequence buffer of 30 normalized embeddings (Point 18)
  final List<List<double>> _rollingBuffer = [];

  // Temporal smoothing window of 3 predictions (Point 20)
  final List<int> _predictionHistory = [];
  int _currentSmoothedPrediction = 0; // 0=Alert, 1=Low Vigilant, 2=Drowsy

  // Callbacks / status getters
  bool get isCalibrated => _isCalibrated;
  int get calibrationProgress => _calibrationBuffer.length; // Max 30
  DrowsinessState get currentState => DrowsinessState.values[_currentSmoothedPrediction];
  int get currentPredictedClass => _currentSmoothedPrediction;

  List<double> _lastSoftmaxScores = [1.0, 0.0, 0.0];
  List<double> get lastSoftmaxScores => _lastSoftmaxScores;

  DrowsinessPipeline({required this.modelManager});

  /// Reset session pipeline
  void reset() {
    _isCalibrated = false;
    _calibrationBuffer.clear();
    _meanVector = null;
    _stdVector = null;
    _rollingBuffer.clear();
    _predictionHistory.clear();
    _currentSmoothedPrediction = 0;
    _lastSoftmaxScores = [1.0, 0.0, 0.0];
  }

  /// Process a newly extracted 512-dim embedding frame
  void processEmbedding(List<double> rawEmbedding) {
    if (rawEmbedding.length != 512) return;

    // Point 17: Calibration phase (first 30 frames / ~30 seconds)
    if (!_isCalibrated) {
      _calibrationBuffer.add(rawEmbedding);
      print('Calibration buffering: ${_calibrationBuffer.length}/30');

      if (_calibrationBuffer.length >= 30) {
        _computeSubjectNormalization();
        _isCalibrated = true;
        print('Subject calibration COMPLETE! Mean and std computed.');
      }
      return;
    }

    // Apply subject normalization: (x - mean) / max(std, 1e-2)
    final List<double> normalizedEmbedding = List.filled(512, 0.0);
    for (int i = 0; i < 512; i++) {
      double std = _stdVector![i] < 1e-2 ? 1e-2 : _stdVector![i];
      normalizedEmbedding[i] = (rawEmbedding[i] - _meanVector![i]) / std;
    }

    // Point 18: Add to rolling buffer FIFO queue (max size 30)
    _rollingBuffer.add(normalizedEmbedding);
    if (_rollingBuffer.length > 30) {
      _rollingBuffer.removeAt(0);
    }

    // Point 19: Run LSTM inference if rolling buffer is full (30 frames)
    if (_rollingBuffer.length == 30) {
      _runLstmInference();
    }
  }

  /// Point 17: Compute mean and standard deviation vector across 30 calibration embeddings
  void _computeSubjectNormalization() {
    _meanVector = List.filled(512, 0.0);
    _stdVector = List.filled(512, 0.0);

    int count = _calibrationBuffer.length;

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
        double diff = emb[i] - _meanVector![i];
        _stdVector![i] += diff * diff;
      }
    }
    for (int i = 0; i < 512; i++) {
      _stdVector![i] = sqrt(_stdVector![i] / count);
    }
  }

  /// Point 19: Run LSTM inference and apply Softmax + Argmax
  void _runLstmInference() {
    // Input tensor shape: [1, 30, 512]
    var inputSequenceTensor = List.generate(
      1,
      (_) => List.generate(
        30,
        (t) => _rollingBuffer[t],
      ),
    );

    List<double> rawLogits = modelManager.runLstmInference(inputSequenceTensor);

    // Apply Softmax to get probabilities
    _lastSoftmaxScores = _softmax(rawLogits);

    // Argmax prediction
    int rawPrediction = 0;
    double maxProb = _lastSoftmaxScores[0];
    for (int i = 1; i < 3; i++) {
      if (_lastSoftmaxScores[i] > maxProb) {
        maxProb = _lastSoftmaxScores[i];
        rawPrediction = i;
      }
    }

    // Point 20: Temporal smoothing window of last 3 predictions
    _applyTemporalSmoothing(rawPrediction);
  }

  /// Point 20: Temporal smoothing: only change state if 3 consecutive predictions agree
  void _applyTemporalSmoothing(int newPrediction) {
    _predictionHistory.add(newPrediction);
    if (_predictionHistory.length > 3) {
      _predictionHistory.removeAt(0);
    }

    if (_predictionHistory.length == 3) {
      if (_predictionHistory[0] == _predictionHistory[1] &&
          _predictionHistory[1] == _predictionHistory[2]) {
        _currentSmoothedPrediction = _predictionHistory[0];
      }
    }
  }

  List<double> _softmax(List<double> logits) {
    double maxLogit = logits.reduce(max);
    List<double> expValues = logits.map((l) => exp(l - maxLogit)).toList();
    double sumExp = expValues.reduce((a, b) => a + b);
    return expValues.map((e) => e / sumExp).toList();
  }
}
