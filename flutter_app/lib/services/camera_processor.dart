import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Points 14, 15, 16: Camera initialization, ML Kit Face Detection, face cropping (+20px padding),
/// 224x224 resizing, pixel normalization (/255.0), and CHW tensor construction.
class CameraProcessor {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  bool _isProcessing = false;
  bool _isInitialized = false;

  CameraController? get controller => _cameraController;
  bool get isInitialized => _isInitialized;

  /// Point 14: Initialize front-facing camera at Medium resolution (~640x480)
  Future<void> initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();

    // Point 15: ML Kit face detector configured in fast performance mode
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: false,
        enableContours: false,
        enableClassification: false,
      ),
    );

    _isInitialized = true;
  }

  /// Point 16: Capture frame photo & process face region into a [1, 3, 224, 224] CNN input tensor
  Future<List<List<List<List<double>>>>?> processNextFrameTensor() async {
    if (!_isInitialized || _cameraController == null || _isProcessing) {
      return null;
    }

    _isProcessing = true;

    try {
      // Take frame photo from front camera feed
      final XFile photo = await _cameraController!.takePicture();
      final Uint8List bytes = await photo.readAsBytes();

      // 1. Run ML Kit Face Detection on the photo file
      final InputImage inputImage = InputImage.fromFilePath(photo.path);
      final faces = await _faceDetector.processImage(inputImage);

      // Clean up temp photo file
      try {
        final File tempFile = File(photo.path);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}

      if (faces.isEmpty) {
        return null; // No face detected in this frame
      }

      final face = faces.first;
      final boundingBox = face.boundingBox;

      // Decode image bytes
      final img.Image? fullImg = img.decodeImage(bytes);
      if (fullImg == null) return null;

      // 2. Crop face region with 20 pixels of padding on all sides
      const int pad = 20;
      final int x = (boundingBox.left - pad).clamp(0, fullImg.width - 1).toInt();
      final int y = (boundingBox.top - pad).clamp(0, fullImg.height - 1).toInt();
      final int w = (boundingBox.width + pad * 2).clamp(1, fullImg.width - x).toInt();
      final int h = (boundingBox.height + pad * 2).clamp(1, fullImg.height - y).toInt();

      final img.Image croppedFace = img.copyCrop(fullImg, x: x, y: y, width: w, height: h);

      // 3. Resize cropped face to 224x224 pixels
      final img.Image resizedFace = img.copyResize(croppedFace, width: 224, height: 224);

      // 4. Normalize pixel values by dividing by 255.0 -> Tensor shape [1, 3, 224, 224] (CHW format)
      var inputTensor = List.generate(
        1,
        (_) => List.generate(
          3,
          (c) => List.generate(
            224,
            (r) => List.filled(224, 0.0),
          ),
        ),
      );

      for (int r = 0; r < 224; r++) {
        for (int c = 0; c < 224; c++) {
          final pixel = resizedFace.getPixel(c, r);
          inputTensor[0][0][r][c] = pixel.r / 255.0; // Red channel
          inputTensor[0][1][r][c] = pixel.g / 255.0; // Green channel
          inputTensor[0][2][r][c] = pixel.b / 255.0; // Blue channel
        }
      }

      return inputTensor;
    } catch (e) {
      print('CameraProcessor frame processing error: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
  }
}
