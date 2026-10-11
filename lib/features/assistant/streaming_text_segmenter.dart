import 'dart:async';

/// Groups streamed text fragments into phrases suitable for speech output.
class StreamingTextSegmenter {
  StreamingTextSegmenter({this.minChars = 24, this.maxChars = 96})
    : assert(minChars > 0),
      assert(maxChars >= minChars);

  final int minChars;
  final int maxChars;
  final StreamController<String> _segments = StreamController<String>.broadcast(
    sync: true,
  );
  String _pending = '';
  bool _closed = false;

  Stream<String> get completedSegments => _segments.stream;

  void pushToken(String text) {
    if (_closed || text.isEmpty) return;
    _pending += text;
    _emitReadySegments();
  }

  void finish() {
    if (_closed) return;
    final remaining = _pending.trim();
    if (remaining.isNotEmpty) _segments.add(remaining);
    _pending = '';
  }

  void reset() {
    _pending = '';
  }

  Future<void> close() async {
    if (_closed) return;
    finish();
    _closed = true;
    await _segments.close();
  }

  void _emitReadySegments() {
    while (_pending.isNotEmpty) {
      final boundary = _findPunctuationBoundary();
      if (boundary > 0) {
        _emit(boundary);
        continue;
      }

      if (_pending.length < maxChars) return;
      var splitAt = _pending.lastIndexOf(' ', maxChars);
      if (splitAt < minChars) {
        splitAt = _pending.indexOf(' ', maxChars);
      }
      if (splitAt < 1) return;
      _emit(splitAt);
    }
  }

  int _findPunctuationBoundary() {
    final sentenceEnd = RegExp(r'[.!?;:\n]').firstMatch(_pending);
    if (sentenceEnd != null) return sentenceEnd.end;

    final comma = _pending.indexOf(',');
    if (comma >= minChars - 1) return comma + 1;
    return 0;
  }

  void _emit(int boundary) {
    final segment = _pending.substring(0, boundary).trim();
    _pending = _pending.substring(boundary).trimLeft();
    if (segment.isNotEmpty) _segments.add(segment);
  }
}
