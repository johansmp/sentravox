import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/features/call_agent/data/llm/llm_responder.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/agent_persona.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/caller_facts.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/dialogue_engine.dart';
import 'package:sentravox/shared/services/llm/llm_service.dart';

void main() {
  group('LlmService', () {
    test('sin clave no está disponible', () {
      const config = LlmConfig(enabled: true);
      expect(config.usable, isFalse);
    });

    test('sanitize quita prefijos, markdown y comillas', () {
      expect(
        LlmService.sanitize('Asistente: **Hola**, ¿en qué le ayudo?'),
        'Hola, ¿en qué le ayudo?',
      );
      expect(LlmService.sanitize('"Hola"'), 'Hola');
      expect(LlmService.sanitize('   '), isNull);
    });

    test('sanitize recorta a dos frases para que se pueda hablar', () {
      expect(
        LlmService.sanitize('Frase uno. Frase dos. Frase tres.'),
        'Frase uno. Frase dos.',
      );
    });
  });

  group('LlmPromptBuilder', () {
    test('incluye datos, etapa, riesgo y la respuesta local', () {
      final prompt = LlmPromptBuilder.build(
        facts: const CallerFacts(
          name: 'Ana',
          company: 'Claro',
          purpose: 'la factura de marzo',
          callback: '3001234567',
        ),
        stage: ScreeningStage.contact,
        transcript: 'Llámeme al mismo número',
        localDraft: '¿A qué número puede devolverle la llamada?',
        risk: 0.2,
      );

      expect(prompt, contains('Ana'));
      expect(prompt, contains('Claro'));
      expect(prompt, contains('la factura de marzo'));
      expect(prompt, contains('3001234567'));
      expect(prompt, contains('contact'));
      expect(prompt, contains('20%'));
      expect(prompt, contains('¿A qué número puede devolverle la llamada?'));
      expect(prompt, contains('Conserva exactamente la misma intención'));
    });

    test('rechaza una reescritura que pierde la pregunta', () {
      expect(
        LlmPromptBuilder.isUsableRewrite(
          '¿Cuál es el motivo de su llamada?',
          'Entiendo, quedo atento.',
        ),
        isFalse,
      );
      expect(
        LlmPromptBuilder.isUsableRewrite(
          '¿Cuál es el motivo de su llamada?',
          'Claro, ¿me cuenta el motivo?',
        ),
        isTrue,
      );
    });

    test('rechaza evasivas de chatbot y respuestas demasiado largas', () {
      expect(
        LlmPromptBuilder.isUsableRewrite(
          '¿Me dice su nombre?',
          'Como modelo de lenguaje no puedo ayudar con eso.',
        ),
        isFalse,
      );
      expect(
        LlmPromptBuilder.isUsableRewrite(
          '¿Me dice su nombre?',
          '${'a' * 400}?',
        ),
        isFalse,
      );
    });

    test('rechaza datos sensibles o teléfonos inventados', () {
      expect(
        LlmPromptBuilder.isUsableRewrite(
          '¿Cuál es el motivo de su llamada?',
          '¿Me confirma su clave y el 3001234567?',
        ),
        isFalse,
      );
      expect(
        LlmPromptBuilder.isUsableRewrite(
          '¿Cuál es el motivo de su llamada?',
          '¿Me confirma el 3001234567?',
        ),
        isFalse,
      );
    });

    test('el prompt local es corto y conserva la sugerencia', () {
      const persona = AgentPersona(name: 'Ana');
      final system = LlmPromptBuilder.localSystemPrompt(persona);
      final user = LlmPromptBuilder.buildLocal(
        transcript: 'Llamo por la factura de marzo',
        localDraft: '¿Sobre qué factura me habla?',
      );

      expect(system, contains('Ana'));
      expect(system.length, lessThan(400));
      expect(user, contains('factura de marzo'));
      expect(user, contains('¿Sobre qué factura me habla?'));
      expect(user, contains('sin cambiar la intención'));
    });
  });
}
