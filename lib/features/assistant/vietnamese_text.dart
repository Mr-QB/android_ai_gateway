class VietnameseText {
  static final Map<String, String> _foldMap = _buildFoldMap();

  static String normalize(String input) {
    final folded = input
        .toLowerCase()
        .split('')
        .map((character) => _foldMap[character] ?? character)
        .join();
    return folded
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Map<String, String> _buildFoldMap() {
    const groups = {
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    final replacements = <String, String>{};
    for (final entry in groups.entries) {
      for (final character in entry.value.split('')) {
        replacements[character] = entry.key;
      }
    }
    return replacements;
  }
}
