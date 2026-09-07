import '../vlm_engine_manager.dart';

abstract class BasePerceptionAgent {
  final String name;
  final VlmEngineManager engineManager;

  const BasePerceptionAgent({
    required this.name,
    required this.engineManager,
  });
}
