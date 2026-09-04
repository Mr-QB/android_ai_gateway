# Third-party notices

## YOLO26 (Ultralytics)

- Source: [Ultralytics YOLO26](https://github.com/ultralytics/ultralytics)
- License: AGPL-3.0 License
- Model: YOLO26n Nano object detector (COCO 80 classes, 640x640 input resolution)
- Export format: NCNN FP16 (`yolo26n.param`, `yolo26n.bin`)

## NCNN Framework & JNI Integration

- Framework: Tencent NCNN (https://github.com/Tencent/ncnn)
- License: BSD 3-Clause
- Mobile deployment design adapted for Flutter on Android:
  - Input preprocessing: Letterbox aspect-ratio preserving padding, RGB normalization.
  - Native engine: `android/app/src/main/cpp/yolo26_engine.cpp`
  - Flutter owns camera capture, thread dispatch, and bounding-box rendering.
