class SlamPose {
  final double timestampSeconds;
  final double x;
  final double y;
  final double z;
  final double qx;
  final double qy;
  final double qz;
  final double qw;
  final bool valid;

  final int frameIndex;

  const SlamPose({
    double? timestampSeconds,
    double? datasetTimestampS,
    double? x,
    double? tx,
    double? y,
    double? ty,
    double? z,
    double? tz,
    required this.qx,
    required this.qy,
    required this.qz,
    required this.qw,
    bool? valid,
    bool? isValid,
    this.frameIndex = 0,
  })  : timestampSeconds = timestampSeconds ?? datasetTimestampS ?? 0.0,
        x = x ?? tx ?? 0.0,
        y = y ?? ty ?? 0.0,
        z = z ?? tz ?? 0.0,
        valid = valid ?? isValid ?? false;

  const SlamPose.empty()
      : timestampSeconds = 0.0,
        x = 0.0,
        y = 0.0,
        z = 0.0,
        qx = 0.0,
        qy = 0.0,
        qz = 0.0,
        qw = 1.0,
        valid = false,
        frameIndex = 0;

  factory SlamPose.identity() => const SlamPose(
        datasetTimestampS: 0.0,
        tx: 0.0,
        ty: 0.0,
        tz: 0.0,
        qx: 0.0,
        qy: 0.0,
        qz: 0.0,
        qw: 1.0,
        isValid: true,
      );

  double get tx => x;
  double get ty => y;
  double get tz => z;
  bool get isValid => valid;
  double get datasetTimestampS => timestampSeconds;

  @override
  String toString() {
    return 'SlamPose(t: ${timestampSeconds.toStringAsFixed(3)}, '
        'pos: [${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)}], '
        'valid: $valid)';
  }
}
