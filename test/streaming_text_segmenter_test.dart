import 'package:android_ai_gateway/features/assistant/streaming_text_segmenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamingTextSegmenter', () {
    test('holds short fragments and emits a complete sentence', () async {
      final segmenter = StreamingTextSegmenter();
      final segments = <String>[];
      final subscription = segmenter.completedSegments.listen(segments.add);

      segmenter.pushToken('Có ');
      segmenter.pushToken('một người ');
      segmenter.pushToken('đang đi bộ.');

      expect(segments, ['Có một người đang đi bộ.']);
      await subscription.cancel();
      await segmenter.close();
    });

    test('uses a long comma clause as a phrase boundary', () async {
      final segmenter = StreamingTextSegmenter(minChars: 20);
      final segments = <String>[];
      final subscription = segmenter.completedSegments.listen(segments.add);

      segmenter.pushToken('Có một người mặc áo sáng màu, đang đi bộ');
      segmenter.finish();

      expect(segments, ['Có một người mặc áo sáng màu,', 'đang đi bộ']);
      await subscription.cancel();
      await segmenter.close();
    });

    test(
      'splits long output at word boundaries and flushes the remainder',
      () async {
        final segmenter = StreamingTextSegmenter(minChars: 10, maxChars: 20);
        final segments = <String>[];
        final subscription = segmenter.completedSegments.listen(segments.add);

        segmenter.pushToken('một hai ba bốn năm sáu bảy');
        segmenter.finish();

        expect(segments, ['một hai ba bốn năm', 'sáu bảy']);
        expect(segments.every((segment) => segment.length <= 20), isTrue);
        await subscription.cancel();
        await segmenter.close();
      },
    );

    test('flushes remaining text once on close', () async {
      final segmenter = StreamingTextSegmenter();
      final segments = <String>[];
      final subscription = segmenter.completedSegments.listen(segments.add);

      segmenter.pushToken('Một câu còn dang dở');
      await segmenter.close();

      expect(segments, ['Một câu còn dang dở']);
      await subscription.cancel();
    });
  });
}
