import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/features/settings/domain/entities/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('por defecto la protección está activada', () {
      const settings = AppSettings();

      expect(settings.securityEnabled, isTrue);
      expect(settings.autoActivateAgent, isTrue);
      expect(settings.blockUnknown, isFalse);
      expect(settings.blockThreshold, 0.6);
      expect(settings.agentActivationEnabled, isTrue);
    });

    test('el interruptor maestro desactiva la activación del agente', () {
      const settings = AppSettings(
        securityEnabled: false,
        autoActivateAgent: true,
      );

      // Aunque autoActivateAgent siga en true.
      expect(settings.agentActivationEnabled, isFalse);
    });

    test('fromMap lee las claves compartidas con Kotlin', () {
      final settings = AppSettings.fromMap({
        AppSettings.keySecurityEnabled: false,
        AppSettings.keyAutoActivateAgent: false,
        AppSettings.keyBlockUnknown: true,
        AppSettings.keyBlockThreshold: 0.85,
      });

      expect(settings.securityEnabled, isFalse);
      expect(settings.autoActivateAgent, isFalse);
      expect(settings.blockUnknown, isTrue);
      expect(settings.blockThreshold, closeTo(0.85, 0.0001));
    });

    test('fromMap cae a los valores seguros si faltan claves', () {
      final settings = AppSettings.fromMap(const {});

      expect(settings.securityEnabled, isTrue);
      expect(settings.blockThreshold, 0.6);
    });

    test('fromMap acepta un umbral entero del codec de plataforma', () {
      final settings = AppSettings.fromMap({AppSettings.keyBlockThreshold: 1});
      expect(settings.blockThreshold, 1.0);
    });

    test('fromMap acota el umbral a un rango usable', () {
      expect(
        AppSettings.fromMap({AppSettings.keyBlockThreshold: 0.0}).blockThreshold,
        0.1,
      );
      expect(
        AppSettings.fromMap({AppSettings.keyBlockThreshold: 5.0}).blockThreshold,
        1.0,
      );
    });

    test('copyWith solo cambia lo indicado', () {
      const original = AppSettings();
      final updated = original.copyWith(securityEnabled: false);

      expect(updated.securityEnabled, isFalse);
      expect(updated.autoActivateAgent, original.autoActivateAgent);
      expect(updated.blockThreshold, original.blockThreshold);
      expect(updated, isNot(original));
      expect(original.copyWith(), original);
    });

    test('fromMap lee el perfil del agente', () {
      final settings = AppSettings.fromMap({
        AppSettings.keyAgentName: 'Alejandro',
        AppSettings.keyAgentCompany: 'Innovatech',
        AppSettings.keyAgentRole: 'recepcionista corporativo',
      });

      expect(settings.agentName, 'Alejandro');
      expect(settings.agentCompany, 'Innovatech');
      expect(settings.agentRole, 'recepcionista corporativo');
      expect(settings.agentActivationEnabled, isTrue);
    });

    test('fromMap lee la voz configurada', () {
      final settings = AppSettings.fromMap({
        AppSettings.keyVoiceGender: 'masculina',
        AppSettings.keySpeechRate: 1.2,
        AppSettings.keyPitch: 1.0,
        AppSettings.keyFormality: 'corporativo',
      });

      expect(settings.voiceGender, 'masculina');
      expect(settings.speechRate, 1.2);
      expect(settings.pitch, 1.0);
      expect(settings.formality, 'corporativo');
    });

    test('copyWith cambia solo el perfil del agente indicado', () {
      const settings = AppSettings();
      final updated = settings.copyWith(agentName: 'Ana');

      expect(updated.agentName, 'Ana');
      expect(updated.agentCompany, settings.agentCompany);
      expect(updated.voiceGender, settings.voiceGender);
    });

    test('fromMap lee voz, ruta de audio e IA avanzada', () {
      final settings = AppSettings.fromMap({
        AppSettings.keyVoiceId: 'es-co-x-ela-local',
        AppSettings.keyInCallAudioMode: 'direct',
        AppSettings.keyLlmEnabled: true,
        AppSettings.keyLlmEndpoint: 'https://example.test/v1/chat',
        AppSettings.keyLlmModel: 'modelo-x',
        AppSettings.keyLlmApiKey: 'clave',
      });

      expect(settings.voiceId, 'es-co-x-ela-local');
      expect(settings.inCallAudioMode, 'direct');
      expect(settings.directAudioInjection, isTrue);
      expect(settings.llmEnabled, isTrue);
      expect(settings.llmEndpoint, 'https://example.test/v1/chat');
      expect(settings.llmModel, 'modelo-x');
      expect(settings.llmUsable, isTrue);
    });

    test('fromMap lee si el agente atiende también contactos', () {
      expect(
        AppSettings.fromMap({AppSettings.keyAgentAllCalls: true}).agentAllCalls,
        isTrue,
      );
      expect(const AppSettings().agentAllCalls, isFalse);
    });

    test('la IA local está activada por defecto', () {
      expect(const AppSettings().llmEnabled, isTrue);
      expect(
        AppSettings.fromMap(const {}).llmEnabled,
        isTrue,
        reason: 'una instalación nueva usa el modelo local empaquetado',
      );
    });

    test('el cliente remoto heredado no se usa sin clave', () {
      const settings = AppSettings(llmEnabled: true);
      expect(settings.llmUsable, isFalse);
    });
  });
}
