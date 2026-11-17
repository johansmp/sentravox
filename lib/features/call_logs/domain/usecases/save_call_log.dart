import '../entities/call_log.dart';
import '../repositories/call_log_repository.dart';

class SaveCallLog {
  final CallLogRepository repository;

  SaveCallLog(this.repository);

  Future<void> call(CallLogEntry entry) {
    return repository.save(entry);
  }
}
