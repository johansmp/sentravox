import '../entities/call_log_stats.dart';
import '../repositories/call_log_repository.dart';

class GetCallLogStats {
  final CallLogRepository repository;

  GetCallLogStats(this.repository);

  Future<CallLogStats> call({DateTime? now}) async {
    final logs = await repository.getAll();
    return CallLogStats.from(logs, now: now ?? DateTime.now());
  }
}
