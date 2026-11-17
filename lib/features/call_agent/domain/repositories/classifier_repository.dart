import 'package:sentravox/features/call_agent/domain/entities/intent.dart';

abstract class ClassifierRepository {
  Future<IntentResult> classify(String text);
}