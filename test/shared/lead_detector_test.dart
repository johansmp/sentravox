import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/shared/analysis/lead_detector.dart';

void main() {
  group('LeadDetector', () {
    test('sin señales basicas no se considera lead', () {
      final score = LeadDetector.score(
        dominantIntent: 'saludo',
        hasName: false,
        hasCompany: false,
        hasCallback: false,
        hasPurpose: false,
        sentiment: 0.0,
        risk: 0.1,
      );

      expect(score, lessThan(0.5));
      expect(LeadDetector.isLead(score), isFalse);
    });

    test('soporte con nombre, proposito y contacto es lead', () {
      final score = LeadDetector.score(
        dominantIntent: 'soporte',
        hasName: true,
        hasCompany: false,
        hasCallback: true,
        hasPurpose: true,
        sentiment: 0.2,
        risk: 0.15,
      );

      expect(LeadDetector.isLead(score), isTrue);
    });

    test('riesgo alto penaliza la puntuacion de lead', () {
      final score = LeadDetector.score(
        dominantIntent: 'venta',
        hasName: true,
        hasCompany: true,
        hasCallback: true,
        hasPurpose: true,
        sentiment: 0.3,
        risk: 0.9,
      );

      expect(score, lessThan(0.8));
    });
  });
}
