import 'memory_entry.dart';
import 'memory_repository.dart';
import 'memory_local_datasource.dart';

class MemoryRepositoryImpl implements MemoryRepository {
  final MemoryLocalDatasource datasource;

  MemoryRepositoryImpl(this.datasource);

  @override
  Future<void> save(MemoryEntry entry) {
    return datasource.save(entry);
  }

  @override
  Future<List<MemoryEntry>> getByNumber(String number) {
    return datasource.getByNumber(number);
  }
}
