class CanonicalVocabulary {
  static const objects = {
    'person': 'một người',
    'pedestrian': 'một người đi bộ',
    'car': 'một ô tô',
    'motorcycle': 'một xe máy',
    'bicycle': 'một xe đạp',
    'bus': 'một xe buýt',
    'truck': 'một xe tải',
    'dog': 'một con chó',
    'stairs': 'cầu thang',
    'door': 'cánh cửa',
    'obstacle': 'vật cản',
    'sign': 'biển báo',
  };

  static const directions = {
    'front': 'phía trước',
    'center': 'phía trước',
    'left': 'bên trái',
    'right': 'bên phải',
    'front_left': 'phía trước bên trái',
    'front_right': 'phía trước bên phải',
    'behind': 'phía sau',
  };

  static const actions = {
    'approaching': 'đang tiến lại gần',
    'walking': 'đang đi bộ',
    'crossing': 'đang băng qua',
    'stopped': 'đang đứng yên',
    'moving': 'đang di chuyển',
  };

  static const distances = {
    'near': 'ở gần',
    'medium': 'cách một đoạn',
    'far': 'ở xa',
  };
}
