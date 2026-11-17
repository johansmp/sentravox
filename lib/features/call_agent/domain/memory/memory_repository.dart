import 'memory_entry.dart';

abstract class MemoryRepository {
  Future<void> save(MemoryEntry entry);
  Future<List<MemoryEntry>> getByNumber(String number);
}
