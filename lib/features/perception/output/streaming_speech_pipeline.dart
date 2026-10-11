import 'dart:async';

import '../../assistant/streaming_text_segmenter.dart';
import 'vietnamese_tts_queue.dart';

class StreamingSpeechPipeline {
  StreamingSpeechPipeline({required this._queue});

  final VietnameseTtsQueue _queue;

  Future<int> speak(Stream<String> fragments, {required int priority}) async {
    final segmenter = StreamingTextSegmenter();
    var segmentCount = 0;
    final subscription = segmenter.completedSegments.listen((segment) {
      segmentCount++;
      unawaited(_queue.enqueue(segment, priority: priority));
    });
    try {
      await for (final fragment in fragments) {
        segmenter.pushToken(fragment);
      }
    } finally {
      segmenter.finish();
      await subscription.cancel();
      await segmenter.close();
      if (segmentCount > 0) await _queue.waitUntilIdle();
    }
    return segmentCount;
  }
}
