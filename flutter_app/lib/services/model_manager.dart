import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Point 13: Model Manager class that loads both TFLite models at app startup.
/// Loads cnn.tflite as cnnInterpreter and lstm.tflite as lstmInterpreter.
class ModelManager {
  Interpreter? _cnnInterpreter;
  Interpreter? _lstmInterpreter;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  Interpreter get cnnInterpreter => _cnnInterpreter!;
  Interpreter get lstmInterpreter => _lstmInterpreter!;

  Future<void> loadModels() async {
    if (_isLoaded) return;

    try {
      // Configure interpreter options (use GPU delegate if available, else 4 CPU threads)
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
      print('ModelManager: Both CNN and LSTM TFLite models loaded successfully.');
    } catch (e) {
      print('ModelManager Error loading models: $e');
      rethrow;
    }
  }

  /// Runs CNN inference on a preprocessed (1, 3, 224, 224) input tensor
  /// Returns a 512-dimensional embedding List<double>
  List<double> runCnnInference(List<List<List<List<double>>>> inputImageTensor) {
    if (!_isLoaded) throw Exception('Models not loaded');

    // Output shape: [1, 512]
    var output = List.generate(1, (_) => List<double>.filled(512, 0.0));
    _cnnInterpreter!.run(inputImageTensor, output);
    return output[0];
  }

  /// Runs LSTM inference on a (1, 30, 512) sequence tensor
  /// Returns 3 class logits: [Alert, Low Vigilant, Drowsy]
  List<double> runLstmInference(List<List<List<double>>> inputSequenceTensor) {
    if (!_isLoaded) throw Exception('Models not loaded');

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
