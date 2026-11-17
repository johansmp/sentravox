import '../entities/call_log.dart';
import '../repositories/call_log_repository.dart';

class GetCallLogs {
  final CallLogRepository repository;

  GetCallLogs(this.repository);

  Future<List<CallLogEntry>> call() {
    return repository.getAll();
  }
}
