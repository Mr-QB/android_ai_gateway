import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../assistant/visual_observation.dart';
import '../../../assistant/structured_vlm_speech_adapter.dart';
import '../../../vlm/models/vlm_language_mode.dart';
import '../../../vlm/models/vlm_result.dart';
import '../../../vlm/models/vlm_stream_event.dart';
import '../../../assistant/vietnamese_response_builder.dart';
import '../../utils/performance_logger.dart';
import '../../output/assistive_output_manager.dart';
import '../../../sense_graph/sense_graph_manager.dart';
import '../base_agent.dart';

class SceneAgentResult {
  final String sceneType;
  final String summary;
  final List<String> importantObjects;
  final double confidence;
  final bool needEscalation;
  final String rawResponse;
  final double latencyMs;
  final VisualObservation? observation;

  const SceneAgentResult({
    required this.sceneType,
    required this.summary,
    required this.importantObjects,
    required this.confidence,
    required this.needEscalation,
    required this.rawResponse,
    required this.latencyMs,
    required this.observation,
  });
}

class SceneAgent extends BasePerceptionAgent {
  SceneAgent({required super.engineManager}) : super(name: 'SceneAgent');

  Future<SceneAgentResult> execute({
    required String imagePath,
    String? userQuery,
    String? viewId,
    List<String>? detectedObjects,
    List<String>? ocrTexts,
    VlmLanguageMode languageMode = VlmLanguageMode.englishStructured,
    bool speakStreaming = true,
  }) async {
    final viAvailable =
        languageMode != VlmLanguageMode.vietnameseNative ||
        await engineManager.isModelAvailable(
          VlmLanguageProfile.vietnameseNative.modelKey,
        );
    final profile = VlmLanguageProfile.resolve(
      languageMode,
      vietnameseModelAvailable: viAvailable,
    );
    final effectiveMode = profile.mode;
    if (effectiveMode != languageMode) {
      debugPrint(
        '[VLM] requested=${languageMode.name} unavailable; '
        'fallback=${effectiveMode.name}',
      );
    }
    final contextInfo = StringBuffer();
    if (detectedObjects != null && detectedObjects.isNotEmpty) {
      contextInfo.writeln(
        'Objects detected: ${detectedObjects.take(8).join(", ")}',
      );
    }
    if (ocrTexts != null && ocrTexts.isNotEmpty) {
      contextInfo.writeln('Visible text: ${ocrTexts.take(4).join(", ")}');
    }

    final prompt = effectiveMode == VlmLanguageMode.englishStructured
        ? '''
Analyze this scene for a visually impaired user.
$contextInfo
${userQuery == null ? '' : 'User question: $userQuery\nAnswer that question briefly.'}
Return one compact JSON object with exactly these six canonical fields; no prose.
Use short English labels. TEXT is exact visible text or "none".
'''
        : '''
Mô tả ngắn gọn bằng tiếng Việt những gì quan trọng cho người khiếm thị.
$contextInfo
${userQuery == null ? '' : 'Câu hỏi: $userQuery\nTrả lời ngắn gọn.'}
Nêu vật thể, hướng, khoảng cách và nguy hiểm nếu có. Không suy đoán.
''';

    final startTime = DateTime.now().millisecondsSinceEpoch;
    final response = StringBuffer();
    final adapter = StructuredVlmSpeechAdapter();
    final output = AssistiveOutputManager();
    VlmResult? vlmResult;
    var firstSegmentLogged = false;
    StreamController<String>? nativeSpeech;
    Future<void>? nativeSpeechTask;
    if (speakStreaming && effectiveMode == VlmLanguageMode.vietnameseNative) {
      nativeSpeech = StreamController<String>();
      nativeSpeechTask = output.speakStream(
        nativeSpeech.stream,
        priority: userQuery == null
            ? AlertPriority.normalDescription
            : AlertPriority.userQuery,
        sourceAgent: name,
      );
    }

    void speakStructuredUpdate(VisualSpeechUpdate update) {
      if (!speakStreaming) return;
      if (!firstSegmentLogged) {
        firstSegmentLogged = true;
        debugPrint(
          '[TTS] first_segment_ms=${DateTime.now().millisecondsSinceEpoch - startTime}',
        );
      }
      final priority = update.isSafetyWarning
          ? AlertPriority.criticalHazard
          : userQuery == null
          ? AlertPriority.normalDescription
          : AlertPriority.userQuery;
      unawaited(
        output
            .speakStream(
              Stream<String>.value(update.text),
              priority: priority,
              sourceAgent: name,
            )
            .catchError((Object error) {
              debugPrint('[TTS] stream failed: $error');
            }),
      );
    }

    try {
      await for (final event in engineManager.streamSmolInference(
        imagePath: imagePath,
        prompt: prompt,
        maxTokens: 64,
        targetResolution: 384,
        structuredOutputFormat:
            effectiveMode == VlmLanguageMode.englishStructured ? 'scene' : null,
        modelKey: profile.modelKey,
      )) {
        switch (event) {
          case VlmToken(:final text):
            response.write(text);
            if (effectiveMode == VlmLanguageMode.vietnameseNative) {
              nativeSpeech?.add(text);
            } else {
              final update = adapter.push(text);
              if (update != null) speakStructuredUpdate(update);
            }
          case VlmStreamCompleted(:final result):
            vlmResult = result;
          case VlmStreamCancelled():
            throw const VlmInferenceCancelled();
          case VlmStreamFailed(:final message):
            throw StateError(message);
        }
      }
      final finalUpdate = adapter.finish();
      if (finalUpdate != null) speakStructuredUpdate(finalUpdate);
    } on StateError catch (error) {
      if (effectiveMode == VlmLanguageMode.vietnameseNative &&
          response.isEmpty) {
        debugPrint(
          '[VLM] Vietnamese model failed before output; retrying English structured mode: $error',
        );
        return execute(
          imagePath: imagePath,
          userQuery: userQuery,
          viewId: viewId,
          detectedObjects: detectedObjects,
          ocrTexts: ocrTexts,
          languageMode: VlmLanguageMode.englishStructured,
          speakStreaming: speakStreaming,
        );
      }
      rethrow;
    } finally {
      if (nativeSpeech != null) {
        await nativeSpeech.close();
      }
      if (nativeSpeechTask != null) {
        unawaited(
          nativeSpeechTask.catchError((Object error) {
            debugPrint('[TTS] stream failed: $error');
          }),
        );
      }
    }
    final completed = vlmResult;
    if (completed == null) {
      throw StateError('VLM stream ended without a result');
    }
    final rawResponse = response.toString();
    if (effectiveMode == VlmLanguageMode.vietnameseNative &&
        rawResponse.trim().isEmpty) {
      debugPrint(
        '[VLM] Vietnamese model returned empty output; retrying English structured mode',
      );
      return execute(
        imagePath: imagePath,
        userQuery: userQuery,
        viewId: viewId,
        detectedObjects: detectedObjects,
        ocrTexts: ocrTexts,
        languageMode: VlmLanguageMode.englishStructured,
        speakStreaming: speakStreaming,
      );
    }
    final latency = (DateTime.now().millisecondsSinceEpoch - startTime)
        .toDouble();

    VisualObservation? observation;
    if (effectiveMode == VlmLanguageMode.englishStructured) {
      try {
        observation = StructuredVlmParser.parse(rawResponse);
      } on FormatException catch (error) {
        debugPrint('[VLM] structured output parse failed: $error');
      }
    }
    final summary = effectiveMode == VlmLanguageMode.vietnameseNative
        ? rawResponse.trim()
        : observation == null
        ? 'Tôi chưa xác định rõ thông tin trước mặt.'
        : (VietnameseResponseBuilder.build(observation) ??
              'Tôi chưa nhận diện được vật thể đáng chú ý.');
    if (speakStreaming &&
        effectiveMode == VlmLanguageMode.englishStructured &&
        !adapter.hasEmitted &&
        summary.isNotEmpty) {
      final priority = userQuery == null
          ? AlertPriority.normalDescription
          : AlertPriority.userQuery;
      unawaited(
        output
            .speakStream(
              Stream<String>.value(summary),
              priority: priority,
              sourceAgent: name,
            )
            .catchError((Object error) {
              debugPrint('[TTS] stream failed: $error');
            }),
      );
    }
    final sceneType = observation?.object ?? 'Không gian trước mặt';
    final importantObjects = observation?.object == null
        ? <String>[]
        : [observation!.object!];
    final confidence = observation == null || observation.isEmpty ? 0.0 : 0.75;
    final needEscalation = effectiveMode == VlmLanguageMode.vietnameseNative
        ? summary.isEmpty
        : observation == null || observation.isEmpty;

    // Update SenseGraph ViewNode if viewId was provided
    if (viewId != null) {
      SenseGraphManager().updateSceneType(viewId, sceneType);
    }

    // Log benchmark
    await PerformanceLogger.logRecord(
      agent: name,
      model: profile.modelKey,
      backend: completed.backend,
      ttftMs: completed.timeToFirstTokenMs,
      generationMs: completed.generationMs,
      totalMs: completed.totalInferenceMs,
      nativeHeapMb: completed.nativeHeapMb,
      javaHeapMb: completed.javaHeapMb,
      triggerReason: 'scene_description',
    );

    return SceneAgentResult(
      sceneType: sceneType,
      summary: summary,
      importantObjects: importantObjects,
      confidence: confidence,
      needEscalation: needEscalation,
      rawResponse: rawResponse,
      latencyMs: latency,
      observation: observation,
    );
  }
}
