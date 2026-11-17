import 'memory_entry.dart';
import 'memory_repository.dart';

class MemoryManager {
  final MemoryRepository repository;

  // Memoria temporal
  final Map<String, String> _sessionMemory = {};

  MemoryManager(this.repository);

  // Guardar memoria temporal
  void rememberInSession(String key, String value) {
    _sessionMemory[key] = value;
  }

  // Obtener memoria temporal
  String? recallFromSession(String key) {
    return _sessionMemory[key];
  }

  // Guardar memoria persistente
  Future<void> rememberPermanently(String number, String key, String value) async {
    await repository.save(
      MemoryEntry(number: number, key: key, value: value),
    );
  }

  // Obtener memoria persistente
  Future<Map<String, String>> recallPermanent(String number) async {
    final entries = await repository.getByNumber(number);
    return {for (var e in entries) e.key: e.value};
  }

  // Limpiar memoria temporal al terminar la llamada
  void clearSession() {
    _sessionMemory.clear();
  }
}
