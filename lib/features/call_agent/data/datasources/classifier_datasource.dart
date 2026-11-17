import 'package:flutter/services.dart';
import '../../domain/entities/intent.dart';

class ClassifierDatasource {
  static const _channel = MethodChannel('sentravox/nlp');

  Future<IntentResult> classify(String text) async {
    final result = await _channel.invokeMethod('classify', {'text': text});

    return IntentResult(
      intent: result['intent'],
      confidence: result['confidence'],
      riskScore: result['riskScore'],
    );
  }
}
