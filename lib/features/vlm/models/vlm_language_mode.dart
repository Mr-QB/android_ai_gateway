enum VlmLanguageMode { englishStructured, vietnameseNative }

class VlmLanguageProfile {
  const VlmLanguageProfile({required this.mode, required this.modelKey});

  final VlmLanguageMode mode;
  final String modelKey;

  static const englishStructured = VlmLanguageProfile(
    mode: VlmLanguageMode.englishStructured,
    modelKey: 'smolvlm2_500m',
  );
  static const vietnameseNative = VlmLanguageProfile(
    mode: VlmLanguageMode.vietnameseNative,
    modelKey: 'smolvlm2_500m_vi_lora',
  );

  static VlmLanguageProfile forMode(VlmLanguageMode mode) => switch (mode) {
    VlmLanguageMode.englishStructured => englishStructured,
    VlmLanguageMode.vietnameseNative => vietnameseNative,
  };

  /// Resolves the optional full LiteRT-LM checkpoint to the structured fallback.
  static VlmLanguageProfile resolve(
    VlmLanguageMode requestedMode, {
    bool vietnameseModelAvailable = false,
  }) {
    if (requestedMode == VlmLanguageMode.vietnameseNative &&
        !vietnameseModelAvailable) {
      return englishStructured;
    }
    return forMode(requestedMode);
  }
}
