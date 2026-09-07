import 'dart:convert';
import 'package:flutter/foundation.dart';

class JsonExtractor {
  /// Robustly extracts and parses a JSON map from model response text.
  /// Handles markdown code fences (```json ... ```), partial text prefix/suffix, or fallback.
  static Map<String, dynamic> extractJsonMap(String rawText) {
    if (rawText.trim().isEmpty) return {};

    // 1. Try direct jsonDecode
    try {
      final decoded = jsonDecode(rawText.trim());
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}

    // 2. Try extracting from ```json ... ``` or ``` ... ```
    final fenceRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', multiLine: true);
    final fenceMatch = fenceRegex.firstMatch(rawText);
    if (fenceMatch != null) {
      final inside = fenceMatch.group(1)?.trim();
      if (inside != null && inside.isNotEmpty) {
        try {
          final decoded = jsonDecode(inside);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {}
      }
    }

    // 3. Try finding the outer-most curly braces { ... }
    final firstBrace = rawText.indexOf('{');
    final lastBrace = rawText.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace > firstBrace) {
      final candidate = rawText.substring(firstBrace, lastBrace + 1).trim();
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {
        // Try sanitized version (removing trailing commas before closing braces)
        final sanitized = candidate
            .replaceAll(RegExp(r',\s*}'), '}')
            .replaceAll(RegExp(r',\s*]'), ']');
        try {
          final decoded = jsonDecode(sanitized);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } catch (_) {}
      }
    }

    debugPrint('[JsonExtractor] Could not parse structured JSON from text: "$rawText"');
    return {};
  }
}
