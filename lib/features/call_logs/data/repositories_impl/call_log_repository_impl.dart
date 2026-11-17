import '../../domain/entities/call_log.dart';
import '../../domain/repositories/call_log_repository.dart';
import '../datasources/call_log_local_datasource.dart';

class CallLogRepositoryImpl implements CallLogRepository {
  final CallLogLocalDatasource datasource;

  CallLogRepositoryImpl(this.datasource);

  @override
  Future<void> save(CallLogEntry entry) {
    return datasource.insertLog(entry);
  }

  @override
  Future<List<CallLogEntry>> getAll() {
    return datasource.getLogs();
  }
}
