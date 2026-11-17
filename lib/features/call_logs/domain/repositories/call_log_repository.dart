import '../entities/call_log.dart';

abstract class CallLogRepository {
  Future<void> save(CallLogEntry entry);
  Future<List<CallLogEntry>> getAll();
}
