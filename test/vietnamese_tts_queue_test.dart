import 'dart:async';

import 'package:android_ai_gateway/features/perception/output/vietnamese_tts_queue.dart';
import 'package:android_ai_gateway/features/perception/output/streaming_speech_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VietnameseTtsQueue', () {
    test('serializes speech and prioritizes queued user responses', () async {
      final speaker = _BlockingSpeaker();
      final queue = VietnameseTtsQueue(speaker: speaker);

      await queue.enqueue('Cảnh báo', priority: 4);
      await Future<void>.delayed(Duration.zero);
      await queue.enqueue('Thông báo nền', priority: 1);
      await queue.enqueue('Câu trả lời', priority: 3);

      expect(speaker.started, ['Cảnh báo']);
      speaker.releaseCurrent();
      await Future<void>.delayed(Duration.zero);
      expect(speaker.started, ['Cảnh báo', 'Câu trả lời']);
      speaker.releaseCurrent();
      await Future<void>.delayed(Duration.zero);
      expect(speaker.started, ['Cảnh báo', 'Câu trả lời', 'Thông báo nền']);
      speaker.releaseCurrent();
      await queue.waitUntilIdle();

      expect(speaker.maxConcurrent, 1);
    });

    test(
      'critical warning interrupts current speech and clears lower priorities',
      () async {
        final speaker = _BlockingSpeaker();
        final queue = VietnameseTtsQueue(speaker: speaker);

        await queue.enqueue('Cảnh báo quan trọng', priority: 4);
        await Future<void>.delayed(Duration.zero);
        await queue.enqueue('Câu trả lời', priority: 3);
        await queue.enqueue('Cảnh báo nguy hiểm', priority: 5);
        await Future<void>.delayed(Duration.zero);

        expect(speaker.stopCount, 1);
        expect(speaker.started, ['Cảnh báo quan trọng', 'Cảnh báo nguy hiểm']);
        speaker.releaseCurrent();
        await queue.waitUntilIdle();
        expect(speaker.started, ['Cảnh báo quan trọng', 'Cảnh báo nguy hiểm']);
      },
    );

    test('clear removes queued text and stop interrupts speech', () async {
      final speaker = _BlockingSpeaker();
      final queue = VietnameseTtsQueue(speaker: speaker);

      await queue.enqueue('Đang nói', priority: 2);
      await Future<void>.delayed(Duration.zero);
      await queue.enqueue('Đang chờ', priority: 1);
      queue.clear();
      await queue.stop();
      await queue.waitUntilIdle();

      expect(speaker.stopCount, 1);
      expect(speaker.started, ['Đang nói']);
      expect(queue.queuedCount, 0);
    });

    test(
      'streams completed Vietnamese phrases into the queue progressively',
      () async {
        final speaker = _BlockingSpeaker();
        final queue = VietnameseTtsQueue(speaker: speaker);
        final pipeline = StreamingSpeechPipeline(queue: queue);
        final fragments = StreamController<String>();
        final speech = pipeline.speak(fragments.stream, priority: 3);

        fragments.add('Có một người đang đi bộ. ');
        await Future<void>.delayed(Duration.zero);
        expect(speaker.started, ['Có một người đang đi bộ.']);

        fragments.add('Phía trước bên phải.');
        await Future<void>.delayed(Duration.zero);
        expect(speaker.started, ['Có một người đang đi bộ.']);
        speaker.releaseCurrent();
        await Future<void>.delayed(Duration.zero);
        expect(speaker.started, [
          'Có một người đang đi bộ.',
          'Phía trước bên phải.',
        ]);

        speaker.releaseCurrent();
        await fragments.close();
        expect(await speech, 2);
        expect(speaker.maxConcurrent, 1);
      },
    );
  });
}

class _BlockingSpeaker implements TtsSpeaker {
  final List<String> started = [];
  Completer<void>? _current;
  int active = 0;
  int maxConcurrent = 0;
  int stopCount = 0;

  @override
  Future<void> speak(String text) async {
    active++;
    if (active > maxConcurrent) maxConcurrent = active;
    started.add(text);
    final completion = Completer<void>();
    _current = completion;
    await completion.future;
    active--;
    if (identical(_current, completion)) _current = null;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    releaseCurrent();
  }

  void releaseCurrent() {
    final completion = _current;
    if (completion != null && !completion.isCompleted) completion.complete();
  }
}
