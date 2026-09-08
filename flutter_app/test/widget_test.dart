import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drowsiness_app/models/trip_session.dart';
import 'package:drowsiness_app/services/drowsiness_pipeline.dart';
import 'package:drowsiness_app/services/model_manager.dart';
import 'package:drowsiness_app/widgets/status_pill.dart';
import 'package:drowsiness_app/widgets/vigilance_gauge.dart';

/// Mock ModelManager for unit testing the pipeline without native binaries
class MockModelManager extends ModelManager {
  List<double> nextLstmOutput = [1.0, 0.0, 0.0]; // Default Alert

  @override
  bool get isLoaded => true;

  @override
  List<double> runCnnInference(List<List<List<List<double>>>> inputImageTensor) {
    return List<double>.filled(512, 0.5);
  }

  @override
  List<double> runLstmInference(List<List<List<double>>> inputSequenceTensor) {
    return nextLstmOutput;
  }
}

void main() {
  group('TripSession Model Tests', () {
    test('TripSession model serialization and safety rating', () {
      final session = TripSession(
        id: 'test-123',
        startTime: DateTime(2026, 1, 1, 10, 0),
        durationSeconds: 125,
        drowsyEventsCount: 0,
        averageVigilance: 92.0,
        timeline: const [
          VigilancePoint(secondOffset: 0, vigilanceScore: 95.0, isDrowsy: false),
          VigilancePoint(secondOffset: 60, vigilanceScore: 89.0, isDrowsy: false),
        ],
      );

      final map = session.toMap();
      final restored = TripSession.fromMap(map);

      expect(restored.id, 'test-123');
      expect(restored.durationSeconds, 125);
      expect(restored.formattedDuration, '02:05');
      expect(restored.safetyRating, 'A+');
      expect(restored.drowsyEventsCount, 0);
      expect(restored.timeline.length, 2);
    });

    test('TripSession rating drops on frequent drowsy events', () {
      final session = TripSession(
        id: 'test-456',
        startTime: DateTime(2026, 1, 1, 10, 0),
        durationSeconds: 3600,
        drowsyEventsCount: 6,
        averageVigilance: 45.0,
        timeline: const [],
      );

      expect(session.safetyRating, 'D');
      expect(session.formattedDuration, '01:00:00');
    });
  });

  group('DrowsinessPipeline Tests', () {
    late MockModelManager mockManager;
    late DrowsinessPipeline pipeline;

    setUp(() {
      mockManager = MockModelManager();
      pipeline = DrowsinessPipeline(modelManager: mockManager, smoothingWindowSize: 3);
    });

    test('Initial state is calibrating and calibration completes at 30 frames', () {
      expect(pipeline.isCalibrated, false);
      expect(pipeline.currentState, DrowsinessState.calibrating);

      // Feed 29 frames of 512-dim embeddings
      final dummyEmb = List<double>.filled(512, 1.0);
      for (int i = 0; i < 29; i++) {
        pipeline.processEmbedding(dummyEmb);
      }
      expect(pipeline.isCalibrated, false);
      expect(pipeline.calibrationProgress, 29);

      // 30th frame completes calibration
      pipeline.processEmbedding(dummyEmb);
      expect(pipeline.isCalibrated, true);
      expect(pipeline.currentState, DrowsinessState.alert);
    });

    test('Rolling buffer and LSTM inference runs after 30 post-calibration frames', () {
      final dummyEmb = List<double>.filled(512, 1.0);

      // 1. Calibrate (30 frames)
      for (int i = 0; i < 30; i++) {
        pipeline.processEmbedding(dummyEmb);
      }
      expect(pipeline.isCalibrated, true);

      // 2. Feed 29 post-calibration frames (rolling buffer has 29)
      for (int i = 0; i < 29; i++) {
        pipeline.processEmbedding(dummyEmb);
      }
      expect(pipeline.timeline.length, 0); // Not full yet

      // 3. 30th post-calibration frame triggers LSTM
      pipeline.processEmbedding(dummyEmb);
      expect(pipeline.timeline.length, 1);
      expect(pipeline.currentVigilanceScore, greaterThan(0.0));
    });

    test('Unified Safety Policy: Low Vigilant (class 1) triggers Drowsy state', () {
      final dummyEmb = List<double>.filled(512, 1.0);

      // Calibrate (30 frames)
      for (int i = 0; i < 30; i++) {
        pipeline.processEmbedding(dummyEmb);
      }

      // Fill rolling buffer to 29 frames with Alert logits [5.0, 0.0, 0.0]
      mockManager.nextLstmOutput = [5.0, 0.0, 0.0];
      for (int i = 0; i < 29; i++) {
        pipeline.processEmbedding(dummyEmb);
      }

      // Now set mock LSTM to predict Low Vigilant (class 1): [0.0, 5.0, 0.0]
      mockManager.nextLstmOutput = [0.0, 5.0, 0.0];

      // Feed 3 consecutive frames with window size 3
      pipeline.processEmbedding(dummyEmb);
      pipeline.processEmbedding(dummyEmb);
      pipeline.processEmbedding(dummyEmb);

      // Both Low Vigilant and Drowsy MUST trigger DrowsinessState.drowsy!
      expect(pipeline.currentState, DrowsinessState.drowsy);
      expect(pipeline.drowsyEventsCount, greaterThanOrEqualTo(1));
    });

    test('Unified Safety Policy: Drowsy (class 2) triggers Drowsy state', () {
      final dummyEmb = List<double>.filled(512, 1.0);

      // Calibrate
      for (int i = 0; i < 30; i++) {
        pipeline.processEmbedding(dummyEmb);
      }

      // Fill rolling buffer
      for (int i = 0; i < 29; i++) {
        pipeline.processEmbedding(dummyEmb);
      }

      // Set mock LSTM to Drowsy (class 2): [0.0, 0.0, 5.0]
      mockManager.nextLstmOutput = [0.0, 0.0, 5.0];

      // Feed 3 consecutive frames
      pipeline.processEmbedding(dummyEmb);
      pipeline.processEmbedding(dummyEmb);
      pipeline.processEmbedding(dummyEmb);

      expect(pipeline.currentState, DrowsinessState.drowsy);
      expect(pipeline.currentVigilanceScore, lessThan(10.0));
    });
  });

  group('Widget Rendering Tests', () {
    testWidgets('VigilanceGauge renders score and label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VigilanceGauge(score: 85.0),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('85%'), findsOneWidget);
      expect(find.text('ALERT'), findsOneWidget);
    });

    testWidgets('StatusPill renders states accurately', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatusPill(state: DrowsinessState.drowsy),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('DROWSY'), findsOneWidget);
    });
  });
}
