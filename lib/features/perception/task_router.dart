enum AgentTask {
  describeScene,
  detectHazard,
  extractRelations,
  readText,
  explainText,
  complexQuestion,
  graphReasoning,
  semanticMemoryEnrichment;

  /// Deterministic routing: returns the target engine type for each task
  TargetEngine get targetEngine {
    switch (this) {
      case AgentTask.describeScene:
      case AgentTask.detectHazard:
      case AgentTask.extractRelations:
        return TargetEngine.smol;

      case AgentTask.readText:
        return TargetEngine.ocr;

      case AgentTask.explainText:
      case AgentTask.complexQuestion:
      case AgentTask.graphReasoning:
      case AgentTask.semanticMemoryEnrichment:
        return TargetEngine.gemma;
    }
  }

  /// Human-friendly display label
  String get displayName {
    switch (this) {
      case AgentTask.describeScene:
        return 'Mô tả không gian (Scene)';
      case AgentTask.detectHazard:
        return 'Kiểm tra chướng ngại/nguy hiểm (Hazard)';
      case AgentTask.extractRelations:
        return 'Trích xuất quan hệ không gian (Relation)';
      case AgentTask.readText:
        return 'Nhận diện chữ (OCR on-device)';
      case AgentTask.explainText:
        return 'Giải thích ý nghĩa chữ/biển báo (Gemma Text)';
      case AgentTask.complexQuestion:
        return 'Hỏi đáp thị giác & ngữ cảnh (Gemma Reasoning)';
      case AgentTask.graphReasoning:
        return 'Lập luận trên đồ thị SenseGraph (Gemma Reasoning)';
      case AgentTask.semanticMemoryEnrichment:
        return 'Liên kết thực thể & bộ nhớ (Gemma Memory)';
    }
  }
}

enum TargetEngine {
  smol,
  gemma,
  ocr,
}

class TaskRouter {
  /// Deterministically resolves user query intent into an AgentTask without calling a VLM
  static AgentTask routeUserQuery(String query) {
    final lower = query.toLowerCase().trim();

    // Check hazard keywords
    if (lower.contains('nguy hiểm') ||
        lower.contains('vật cản') ||
        lower.contains('chướng ngại') ||
        lower.contains('tránh') ||
        lower.contains('hazard') ||
        lower.contains('obstacle') ||
        lower.contains('danger')) {
      return AgentTask.detectHazard;
    }

    // Check text/reading keywords
    if (lower.contains('đọc chữ') ||
        lower.contains('biển báo gì') ||
        lower.contains('chữ gì') ||
        lower.contains('viết gì') ||
        lower.contains('read text') ||
        lower.contains('ocr')) {
      return AgentTask.explainText;
    }

    // Check spatial relations
    if (lower.contains('nằm ở đâu') ||
        lower.contains('bên trái') ||
        lower.contains('bên phải') ||
        lower.contains('ở đâu') ||
        lower.contains('vị trí tương quan')) {
      return AgentTask.extractRelations;
    }

    // Check memory / place / history query
    if (lower.contains('trước đó') ||
        lower.contains('vừa nãy') ||
        lower.contains('lúc nãy') ||
        lower.contains('bao nhiêu phòng') ||
        lower.contains('lịch sử') ||
        lower.contains('history')) {
      return AgentTask.graphReasoning;
    }

    // Simple description
    if (lower.contains('mô tả') ||
        lower.contains('có gì') ||
        lower.contains('xung quanh') ||
        lower.contains('describe') ||
        lower.length < 15) {
      return AgentTask.describeScene;
    }

    // Default to complex visual reasoning on Gemma
    return AgentTask.complexQuestion;
  }
}
