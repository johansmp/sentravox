import 'package:flutter_test/flutter_test.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/caller_facts.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/dialogue_engine.dart';
import 'package:sentravox/features/call_agent/domain/dialogue/intent_labels.dart';
import 'package:sentravox/shared/services/nlp/nlp_service.dart';

/// Ejecuta una conversación completa con el clasificador de reglas, igual que
/// la simulación de la app.
Future<List<DialogueReply>> _converse(
  DialogueEngine engine,
  List<String> utterances, {
  NlpService? nlp,
}) async {
  final classifier = nlp ?? NlpService();
  final replies = <DialogueReply>[];

  for (final text in utterances) {
    final intent = await classifier.classify(text);
    replies.add(engine.generate(intent: intent, risk: 0.1, transcript: text));
    if (replies.last.endCall) break;
  }

  return replies;
}

void main() {
  group('IntentLabels', () {
    test('traduce los dos vocabularios de clasificador', () {
      // Español (NlpService) e inglés (ONNX) caen en la misma intención.
      expect(IntentLabels.canonical('facturacion'), CallerIntent.billing);
      expect(IntentLabels.canonical('billing'), CallerIntent.billing);
      expect(IntentLabels.canonical('fraude'), CallerIntent.fraud);
      expect(IntentLabels.canonical('spam'), CallerIntent.fraud);
    });

    test('una etiqueta desconocida no bloquea el guion', () {
      // `other`, no `unclear`: el guion debe seguir avanzando.
      expect(IntentLabels.canonical('etiqueta_nueva'), CallerIntent.other);
      expect(IntentLabels.canonical(''), CallerIntent.unclear);
      expect(IntentLabels.canonical(null), CallerIntent.unclear);
    });
  });

  group('FactExtractor', () {
    test('extrae el nombre de las formas habituales de presentarse', () {
      expect(FactExtractor.extract('Me llamo Ana María').name, 'Ana María');
      expect(FactExtractor.extract('mi nombre es Carlos').name, 'Carlos');
      expect(FactExtractor.extract('Le habla Pedro Gómez').name, 'Pedro Gómez');
      expect(FactExtractor.extract('Soy Juan, buenas tardes').name, 'Juan');
    });

    test('reconoce «me llamó» y no toma el apellido Mora como cobranza', () {
      final facts = FactExtractor.extract('me llamó Edward Mora');
      expect(facts.name, 'Edward Mora');

      final long = FactExtractor.extract(
        'me llamo Eduard Mora y lo estoy contactando',
      );
      expect(long.name, 'Eduard Mora');
    });

    test('reconoce «con Carlos Andrés Ramírez Gómez» sin verbo', () {
      expect(
        FactExtractor.extract('con Carlos Andrés Ramírez Gómez').name,
        'Carlos Andrés Ramírez Gómez',
      );
      expect(FactExtractor.nameCandidate('Carlos Andrés Ramírez Gómez'),
          'Carlos Andrés Ramírez Gómez');
      expect(FactExtractor.nameCandidate('Carlos'), 'Carlos');
      expect(FactExtractor.nameCandidate('Ya te lo dije'), isNull);
      expect(FactExtractor.nameCandidate('con el titular'), isNull);
      expect(FactExtractor.nameCandidate('con gusto'), isNull);
      expect(FactExtractor.nameCandidate('mmm'), isNull);
    });

    test('«soy Juan de Bancolombia» separa nombre y empresa', () {
      final facts = FactExtractor.extract('Soy Juan de Bancolombia');
      expect(facts.name, 'Juan');
      expect(facts.company, 'Bancolombia');
    });

    test('no confunde un cargo con un nombre', () {
      expect(FactExtractor.extract('soy el técnico').name, isNull);
      expect(FactExtractor.extract('soy de la empresa Claro').name, isNull);
      expect(FactExtractor.extract('soy de la empresa Claro').company, 'Claro');
    });

    test('reconoce un teléfono de devolución', () {
      expect(
        FactExtractor.extract('mi número es 300 123 4567').callback,
        '3001234567',
      );
      // Una referencia de factura corta no es un teléfono.
      expect(FactExtractor.extract('la factura 12345').callback, isNull);
    });

    test('no confunde una cuenta o factura con un teléfono', () {
      expect(
        FactExtractor.extract('mi factura es 3001234567').callback,
        isNull,
      );
      expect(
        FactExtractor.extract('mi cuenta es 3001234567').callback,
        isNull,
      );
      expect(
        FactExtractor.extract('mi número de contacto es 3001234567').callback,
        '3001234567',
      );
    });

    test('el motivo empieza en la marca de motivo, no en el saludo', () {
      expect(
        FactExtractor.summarize('Hola, soy Ana y llamo por la factura de marzo'),
        'la factura de marzo',
      );
      expect(
        FactExtractor.summarize('necesito revisar el internet'),
        'necesito revisar el internet',
      );
    });

    test('merge conserva lo que ya se sabía', () {
      const known = CallerFacts(name: 'Ana');
      final merged = known.merge(const CallerFacts(name: 'Otro', company: 'X'));

      expect(merged.name, 'Ana');
      expect(merged.company, 'X');
    });

    test('entiende un teléfono dictado con palabras', () {
      expect(
        FactExtractor.extract(
          'mi número es tres cero cero uno dos tres cuatro cinco seis siete',
        ).callback,
        '3001234567',
      );
    });

    test('un «sí» aislado no se convierte en motivo de llamada', () {
      expect(FactExtractor.summarize('sí'), isNull);
      expect(FactExtractor.summarize('no'), isNull);
      expect(FactExtractor.summarize('claro'), isNull);
    });

    test('extrae empresa de «de parte de» sin confundirla con el nombre', () {
      final facts = FactExtractor.extract(
        'Buenas, le habla Pedro y llamo de parte de Bancolombia',
      );

      expect(facts.name, 'Pedro');
      expect(facts.company, 'Bancolombia');
    });

    test('«Soy de Banco de Bogotá» conserva la empresa', () {
      expect(
        FactExtractor.extract('Soy de Banco de Bogotá').company,
        'Banco',
      );
    });
  });

  group('DialogueEngine: el guion avanza', () {
    test('llamada normal: identifica, indaga, toma el mensaje y cierra', () async {
      final engine = DialogueEngine();

      expect(engine.opening(), contains('¿Con quién tengo el gusto'));

      final replies = await _converse(engine, [
        'Buenas tardes',
        'Me llamo Ana Ruiz',
        'Llamo por la factura de marzo que quedó pendiente',
        'Es la factura número 4471',
        'Mi número es 3001234567',
        'No, nada más',
      ]);

      // Ninguna respuesta se repite: eso era el bucle.
      final texts = replies.map((r) => r.text).toList();
      expect(texts.toSet().length, texts.length);

      // Ninguna respuesta recita la conversación previa.
      expect(texts.any((t) => t.contains('U:') || t.contains('A:')), isFalse);

      // La llamada termina por decisión del agente, con los datos recogidos.
      expect(replies.last.endCall, isTrue);
      expect(engine.facts.name, 'Ana Ruiz');
      expect(engine.facts.hasPurpose, isTrue);
      expect(engine.facts.callback, '3001234567');
      expect(replies.last.text, contains('Ana Ruiz'));
      expect(replies.last.text, contains('3001234567'));
      expect(engine.stage, ScreeningStage.finished);
    });

    test('no vuelve a pedir un dato que ya tiene', () async {
      final engine = DialogueEngine();

      final replies = await _converse(engine, [
        'Hola, soy Carlos de Claro y llamo por el pago de la factura',
        'Es sobre el recibo de este mes',
      ]);

      expect(engine.facts.name, 'Carlos');
      expect(engine.facts.company, 'Claro');
      expect(
        replies.first.text.contains('necesito su nombre'),
        isFalse,
        reason: 'ya se presentó en la primera frase',
      );
    });

    test('pregunta el nombre como máximo dos veces y sigue adelante', () async {
      final engine = DialogueEngine();

      final replies = await _converse(engine, [
        'Buenas',
        'Buenas',
        'Es por un tema de soporte con el internet',
      ]);

      expect(replies[0].stage, ScreeningStage.identifying);
      expect(replies[1].stage, ScreeningStage.identifying);
      // Tras dos intentos deja de insistir con el nombre.
      expect(replies[2].stage, isNot(ScreeningStage.identifying));
    });

    test('se rinde tras tres intervenciones ininteligibles', () async {
      final engine = DialogueEngine();

      final replies = await _converse(engine, ['eh', 'mmm', 'ah']);

      expect(replies.length, 3);
      expect(replies.last.endCall, isTrue);
      expect(replies.last.notice, contains('no se entendió'));
    });

    test('la aclaración siempre repite la pregunta pendiente', () async {
      final engine = DialogueEngine();
      final replies = await _converse(engine, ['mmm']);

      expect(replies.single.text, contains('¿Con quién tengo el gusto'));
    });

    test('responde quién es y retoma la pregunta pendiente', () async {
      final engine = DialogueEngine();
      final replies = await _converse(engine, ['¿con quién hablo?']);

      expect(replies.single.text, contains('asistente virtual'));
      expect(replies.single.text, contains('¿Con quién tengo el gusto'));
      expect(replies.single.endCall, isFalse);
    });

    test('nunca se repite literalmente dos veces seguidas', () async {
      final engine = DialogueEngine();

      final replies = await _converse(engine, [
        '¿quién habla?',
        '¿quién eres?',
      ]);

      expect(replies[0].text, isNot(replies[1].text));
      expect(replies[1].text, startsWith('Disculpe que insista'));
    });

    test('cierra cuando el interlocutor se despide', () async {
      final engine = DialogueEngine();
      final replies = await _converse(engine, ['Me llamo Ana', 'hasta luego']);

      expect(replies.last.endCall, isTrue);
      expect(replies.last.text, contains('Hasta luego'));
    });

    test('rechaza las llamadas comerciales en el momento', () async {
      final engine = DialogueEngine();
      final replies = await _converse(engine, [
        'Buenas, le llamo para ofrecerle una promoción de nuestro plan',
      ]);

      expect(replies.single.endCall, isTrue);
      expect(replies.single.notice, contains('comercial'));
    });

    test('no colabora con temas bancarios y corta al insistir', () async {
      final engine = DialogueEngine();

      final replies = await _converse(engine, [
        'Necesito confirmar los datos de su cuenta bancaria',
        'Solo dígame el número de la tarjeta',
      ]);

      expect(replies[0].endCall, isFalse);
      expect(replies[0].text, contains('no confirmo ni entrego datos'));
      expect(replies[1].endCall, isTrue);
      expect(replies[1].notice, contains('tema sensible'));
    });

    test('el riesgo alto corta sin conversación', () {
      final engine = DialogueEngine();

      final reply = engine.generate(
        intent: 'fraude',
        risk: 0.95,
        transcript: 'dame tu clave para liberar el premio',
      );

      expect(reply.endCall, isTrue);
      expect(reply.notice, contains('riesgo alto'));
    });

    test('cierra por longitud si la conversación no llega a nada', () async {
      final engine = DialogueEngine();

      // Frases con contenido pero sin datos útiles: el guion no puede avanzar.
      final replies = await _converse(
        engine,
        List.filled(12, 'pues mire yo le comento otra cosa distinta'),
      );

      expect(replies.last.endCall, isTrue);
      expect(replies.length, lessThanOrEqualTo(12));
    });

    test('reset deja el motor listo para otra llamada', () async {
      final engine = DialogueEngine();
      await _converse(engine, ['Me llamo Ana Ruiz']);

      expect(engine.facts.name, 'Ana Ruiz');

      engine.reset();

      expect(engine.facts.isEmpty, isTrue);
      expect(engine.stage, ScreeningStage.identifying);
      expect(engine.opening(), contains('¿Con quién tengo el gusto'));
    });

    test('un número conocido se saluda por su nombre', () {
      final engine = DialogueEngine()..seed(const CallerFacts(name: 'Ana'));

      expect(engine.opening(), contains('¿Hablo con Ana?'));
    });

    test('«me llamó Edward Mora» no vuelve a pedir el nombre', () async {
      final engine = DialogueEngine();
      final replies = await _converse(engine, [
        'me llamó Edward Mora',
        'llamo por la factura de marzo',
      ]);

      expect(engine.facts.name, 'Edward Mora');
      expect(replies.first.text, isNot(contains('¿Me regala su nombre?')));
      expect(replies.first.text, contains('motivo'));
      expect(engine.facts.purpose, contains('factura'));
    });

    test('«con Carlos Andrés Ramírez Gómez» no vuelve a pedir el nombre',
        () async {
      final engine = DialogueEngine();
      final replies = await _converse(engine, [
        'Buenas tardes',
        'con Carlos Andrés Ramírez Gómez',
        'llamo por la factura de marzo',
      ]);

      expect(engine.facts.name, 'Carlos Andrés Ramírez Gómez');
      expect(replies[1].text, isNot(contains('¿Me regala su nombre?')));
      expect(replies[1].text, contains('motivo'));
    });

    test('entiende «el mismo número» como teléfono de devolución', () {
      final engine = DialogueEngine(callerNumber: '3001234567');

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
        transcript: 'Llámeme al mismo número',
      );

      expect(engine.facts.callback, '3001234567');
    });

    test('un «sí» no se anota como motivo y se repite la pregunta', () {
      final engine = DialogueEngine();

      engine.generate(
        intent: 'presentacion',
        risk: 0.1,
        transcript: 'Me llamo Ana',
      );
      final reply = engine.generate(
        intent: 'consulta',
        risk: 0.1,
        transcript: 'sí',
      );

      expect(engine.facts.hasPurpose, isFalse);
      expect(reply.stage, ScreeningStage.purpose);
      expect(reply.text, contains('motivo'));
    });
  });

  group('NlpService', () {
    final nlp = NlpService();

    test('clasifica las intenciones del guion', () async {
      expect(await nlp.classify('hola buenas tardes'), 'saludo');
      expect(await nlp.classify('me llamo Ana'), 'presentacion');
      expect(await nlp.classify('llamo de Claro'), 'empresa');
      expect(await nlp.classify('quiero hablar con el titular'), 'buscar_persona');
      expect(await nlp.classify('es por la factura de marzo'), 'facturacion');
      expect(await nlp.classify('el internet no funciona'), 'soporte');
      expect(await nlp.classify('traigo un paquete'), 'mensajeria');
      expect(await nlp.classify('le ofrezco una promoción'), 'venta');
      expect(await nlp.classify('deme la clave de su cuenta'), 'bancario');
      expect(await nlp.classify('ganó un premio del sorteo'), 'fraude');
      expect(await nlp.classify('hasta luego'), 'despedida');
      expect(await nlp.classify('¿con quién hablo?'), 'identidad');
    });

    test('un texto vacío no se clasifica como consulta', () async {
      expect(await nlp.classify('   '), 'sin_intencion');
    });

    test('«tengo un problema con la factura» no es una amenaza', () async {
      // La regla anterior marcaba «problema» como amenaza: riesgo 0.85 y
      // llamada cortada por hablar de una factura.
      expect(
        await nlp.classify('tengo un problema con la factura'),
        'facturacion',
      );
      expect(await nlp.classify('tengo un problema con el internet'), 'soporte');
    });

    test('una oferta explícita gana a la palabra «crédito»', () async {
      expect(
        await nlp.classify('le ofrezco un crédito preaprobado'),
        'venta',
      );
    });

    test('la clave del wifi no se trata como tema bancario', () async {
      expect(
        await nlp.classify('no recuerdo la clave del wifi'),
        isNot('bancario'),
      );
    });

    test('una negación no dispara la categoría negada', () async {
      expect(await nlp.classify('no tengo ningún problema'), 'consulta');
      expect(
        await nlp.classify('no es una estafa, llamo por la factura'),
        'facturacion',
      );
    });

    test('una presentación no se confunde con facturación por el apellido', () async {
      expect(await nlp.classify('me llamó Edward Mora'), 'presentacion');
      expect(
        await nlp.classify('me llamo Eduard Mora y lo estoy contactando'),
        'presentacion',
      );
      expect(await nlp.classify('estoy en mora con la factura'), 'facturacion');
    });
  });

  group('DialogueEngine con perfil de agente', () {
    test('abre con el nombre y la empresa configurados', () {
      final engine =
          DialogueEngine(agentName: 'Alejandro', agentCompany: 'Innovatech SAS');

      expect(engine.opening(), contains('Alejandro'));
      expect(engine.opening(), contains('Innovatech'));
      expect(engine.opening(), contains('atendiendo esta llamada'));
    });

    test('abre con el nombre conocido sin empresa nueva', () {
      final engine = DialogueEngine(agentName: 'Ana', agentCompany: '');
      engine.seed(const CallerFacts(name: 'Ana'));

      expect(engine.opening(), contains('Hablo con Ana'));
    });
  });
}
