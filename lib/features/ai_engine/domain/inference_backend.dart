enum InferenceBackend {
  auto(2, 'AUTO'),
  vulkan(1, 'Vulkan GPU'),
  cpu(0, 'CPU');

  final int nativeMode;
  final String displayName;

  const InferenceBackend(this.nativeMode, this.displayName);

  static InferenceBackend fromNative(int code) {
    return switch (code) {
      1 => InferenceBackend.vulkan,
      0 => InferenceBackend.cpu,
      _ => InferenceBackend.auto,
    };
  }
}
