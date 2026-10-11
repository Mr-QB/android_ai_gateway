import 'package:android_ai_gateway/features/vlm/models/vlm_language_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('language profiles keep checkpoint choice separate from mode', () {
    expect(
      VlmLanguageProfile.forMode(VlmLanguageMode.englishStructured).modelKey,
      'smolvlm2_500m',
    );
    expect(
      VlmLanguageProfile.forMode(VlmLanguageMode.vietnameseNative).modelKey,
      'smolvlm2_500m_vi_lora',
    );
  });

  test('missing Vietnamese checkpoint resolves to English structured mode', () {
    expect(
      VlmLanguageProfile.resolve(VlmLanguageMode.vietnameseNative).mode,
      VlmLanguageMode.englishStructured,
    );
  });

  test('installed Vietnamese checkpoint is selected when available', () {
    final profile = VlmLanguageProfile.resolve(
      VlmLanguageMode.vietnameseNative,
      vietnameseModelAvailable: true,
    );
    expect(profile.mode, VlmLanguageMode.vietnameseNative);
    expect(profile.modelKey, 'smolvlm2_500m_vi_lora');
  });
}
