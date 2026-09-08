import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Manages loading and running inference for the CNN feature extractor
/// and LSTM sequence classifier via TFLite.
class ModelManager {
  Interpreter? _cnnInterpreter;
  Interpreter? _lstmInterpreter;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  Interpreter get cnnInterpreter => _cnnInterpreter!;
  Interpreter get lstmInterpreter => _lstmInterpreter!;

  /// Loads both TFLite models from app assets
  Future<void> loadModels() async {
    if (_isLoaded) return;

    try {
      // 4 CPU threads for balanced performance and battery life
      final options = InterpreterOptions()..threads = 4;

      _cnnInterpreter = await Interpreter.fromAsset(
        'assets/models/cnn.tflite',
        options: options,
      );

      _lstmInterpreter = await Interpreter.fromAsset(
        'assets/models/lstm.tflite',
        options: options,
      );

      _isLoaded = true;
      debugPrint('ModelManager: Both CNN and LSTM TFLite models loaded successfully.');
    } catch (e) {
      debugPrint('ModelManager Error loading models: $e');
      rethrow;
    }
  }

  /// Runs CNN inference on a preprocessed (1, 3, 224, 224) input tensor
  /// Returns a 512-dimensional embedding `List<double>`
  List<double> runCnnInference(List<List<List<List<double>>>> inputImageTensor) {
    if (!_isLoaded) throw StateError('Models not loaded');

    // Output shape: [1, 512]
    var output = List.generate(1, (_) => List<double>.filled(512, 0.0));
    _cnnInterpreter!.run(inputImageTensor, output);
    return output[0];
  }

  /// Runs LSTM inference on a (1, 30, 512) sequence tensor
  /// Returns 3 class logits: [Alert, Low Vigilant, Drowsy]
  List<double> runLstmInference(List<List<List<double>>> inputSequenceTensor) {
    if (!_isLoaded) throw StateError('Models not loaded');

    // Output shape: [1, 3]
    var output = List.generate(1, (_) => List<double>.filled(3, 0.0));
    _lstmInterpreter!.run(inputSequenceTensor, output);
    return output[0];
  }

  void dispose() {
    _cnnInterpreter?.close();
    _lstmInterpreter?.close();
    _isLoaded = false;
  }
}
