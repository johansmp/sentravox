import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/agent_persona.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/dialogue_engine.dart';

void main() {
  group('AgentPersona', () {
    const persona = AgentPersona(
      name: 'Alejandro',
      company: 'Innovatech SAS',
      role: 'recepcionista corporativo',
      personality: 'cercano y eficiente',
      ownerName: 'Carlos Ruiz',
      ownerTitle: 'gerente de operaciones',
      formality: AgentFormality.friendly,
    );

    test('el prompt de sistema usa todos los ajustes del perfil', () {
      final prompt = persona.systemPrompt;

      expect(prompt, contains('Alejandro'));
      expect(prompt, contains('Innovatech SAS'));
      expect(prompt, contains('recepcionista corporativo'));
      expect(prompt, contains('cercano y eficiente'));
      expect(prompt, contains('Carlos Ruiz'));
      expect(prompt, contains('gerente de operaciones'));
      expect(prompt, contains('amable'));
      expect(prompt, contains('nunca reveles datos personales'));
    });

    test('sin propietario se refiere al titular de la línea', () {
      const sinDueno = AgentPersona(name: 'Ana');

      expect(sinDueno.owner, 'el titular');
      expect(sinDueno.systemPrompt, contains('el titular de la línea'));
    });

    test('un nombre vacío no deja el saludo roto', () {
      const sinNombre = AgentPersona(name: '   ');

      expect(sinNombre.displayName, 'SentraVox');
      expect(DialogueEngine(persona: sinNombre).opening(), contains('SentraVox'));
    });

    test('el saludo y el cierre reflejan rol, dueño y formalidad', () {
      final engine = DialogueEngine(persona: persona);
      final opening = engine.opening();

      expect(opening, startsWith('Hola'));
      expect(opening, contains('Alejandro'));
      expect(opening, contains('Innovatech SAS'));
      expect(opening, contains('recepcionista corporativo'));
      expect(opening, contains('Carlos Ruiz'));
      expect(opening, contains('Con gusto le ayudo'));

      final reply = engine.generate(
        intent: 'presentacion',
        risk: 0.1,
        transcript: 'Me llamo Ana',
      );
      expect(reply.text, contains('Gracias, Ana'));
    });

    test('el modo corporativo usa un saludo más formal', () {
      const corporate = AgentPersona(
        name: 'Ana',
        formality: AgentFormality.corporate,
      );

      expect(DialogueEngine(persona: corporate).opening(),
          startsWith('Buenos días'));
    });

    test('el cierre nombra al propietario configurado', () {
      final engine = DialogueEngine(persona: persona);

      engine.generate(
        intent: 'presentacion',
        risk: 0.1,
        transcript: 'Me llamo Ana',
      );
      engine.generate(
        intent: 'facturacion',
        risk: 0.1,
        transcript: 'Llamo por la factura',
      );
      engine.generate(
        intent: 'consulta',
        risk: 0.1,
        transcript: 'No, nada más',
      );

      final closing = engine.generate(
        intent: 'consulta',
        risk: 0.1,
        transcript: 'Listo, gracias',
      );

      expect(closing.endCall, isTrue);
      expect(closing.text, contains('Carlos Ruiz'));
      expect(closing.text, contains('¡Gracias por su tiempo'));
    });

    test('AgentFormality.parse acepta los valores de la UI y cae al seguro', () {
      expect(AgentFormality.parse('corporativo'), AgentFormality.corporate);
      expect(AgentFormality.parse('amable'), AgentFormality.friendly);
      expect(AgentFormality.parse('otra cosa'), AgentFormality.professional);
      expect(AgentFormality.parse(null), AgentFormality.professional);
    });

    test('la identidad usa «del titular», no «de el titular»', () {
      final sinDueno = DialogueEngine().generate(
        intent: 'identidad',
        risk: 0.1,
        transcript: '¿quién habla?',
      );

      expect(sinDueno.text, contains('del titular'));
      expect(sinDueno.text, isNot(contains('de el titular')));

      final conDueno = DialogueEngine(persona: persona).generate(
        intent: 'identidad',
        risk: 0.1,
        transcript: '¿quién habla?',
      );

      expect(conDueno.text, contains('de Carlos Ruiz'));
    });
  });
}
