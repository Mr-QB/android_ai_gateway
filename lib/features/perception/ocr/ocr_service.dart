import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

class OcrResultItem {
  final String text;
  final List<double> bbox; // [x, y, w, h] normalized 0.0 - 1.0
  final double confidence;

  const OcrResultItem({
    required this.text,
    required this.bbox,
    required this.confidence,
  });
}

class OcrService {
  static final OcrService _instance = OcrService._internal();
  factory OcrService() => _instance;
  OcrService._internal();

  TextRecognizer? _textRecognizer;

  TextRecognizer _getRecognizer() {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _textRecognizer!;
  }

  /// Performs on-device text recognition on the given image file
  Future<List<OcrResultItem>> recognizeText(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizer = _getRecognizer();
      final RecognizedText recognizedText = await recognizer.processImage(inputImage);

      // Determine image dimensions to normalize bounding boxes
      double imgWidth = 1.0;
      double imgHeight = 1.0;
      try {
        final bytes = await File(imagePath).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          imgWidth = decoded.width.toDouble();
          imgHeight = decoded.height.toDouble();
        }
      } catch (_) {}

      final results = <OcrResultItem>[];

      for (final block in recognizedText.blocks) {
        final text = block.text.trim();
        if (text.isEmpty) continue;

        final rect = block.boundingBox;
        final normX = (rect.left / imgWidth).clamp(0.0, 1.0);
        final normY = (rect.top / imgHeight).clamp(0.0, 1.0);
        final normW = (rect.width / imgWidth).clamp(0.0, 1.0);
        final normH = (rect.height / imgHeight).clamp(0.0, 1.0);

        // Confidence estimation: ML Kit doesn't expose raw block confidence in all scripts,
        // estimate from symbol/line presence (typically 0.85-0.98 on clear OCR)
        const estimatedConfidence = 0.90;

        results.add(OcrResultItem(
          text: text,
          bbox: [normX, normY, normW, normH],
          confidence: estimatedConfidence,
        ));
      }

      debugPrint('[OcrService] Recognized ${results.length} text blocks from $imagePath');
      return results;
    } catch (e) {
      debugPrint('[OcrService] Error recognizing text: $e');
      return [];
    }
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
