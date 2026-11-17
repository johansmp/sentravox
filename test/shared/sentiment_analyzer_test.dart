import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/shared/analysis/sentiment_analyzer.dart';

void main() {
  group('SentimentAnalyzer', () {
    test('texto neutro tiene score 0', () {
      expect(SentimentAnalyzer.score('Hola, ¿con quién hablo?'), 0.0);
    });

    test('texto con agradecimiento y bueno se considera positivo', () {
      expect(SentimentAnalyzer.score('Gracias, perfecto. Todo bien.'), greaterThan(0));
      expect(SentimentAnalyzer.label(SentimentAnalyzer.score('Gracias, perfecto. Todo bien.')), 'positivo');
    });

    test('texto con problema y urgencia se considera negativo', () {
      final value = SentimentAnalyzer.score('Muy molesto, es un problema urgente.');
      expect(value, lessThan(0));
      expect(SentimentAnalyzer.label(value), 'negativo');
    });
  });
}
