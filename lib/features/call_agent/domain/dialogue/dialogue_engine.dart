import 'agent_persona.dart';
import 'caller_facts.dart';
import 'dialogue_rules.dart';
import 'dialogue_templates.dart';
import 'intent_labels.dart';

/// En qué punto del guion de filtrado va la llamada.
enum ScreeningStage {
  /// Averiguando con quién se habla.
  identifying,

  /// Averiguando para qué llama.
  purpose,

  /// Repreguntando sobre el motivo.
  probing,

  /// Pidiendo un número de devolución.
  contact,

  /// Cerrando: ya no se espera más información.
  closing,

  /// Terminado.
  finished,
}

/// Una respuesta del agente, con la decisión que la acompaña.
class DialogueReply {
  final String text;

  /// El agente considera terminada la llamada. El bucle de conversación cuelga
  /// tras hablar en lugar de volver a abrir el micrófono.
  final bool endCall;

  /// Motivo del cierre, para mostrarlo en pantalla y en el historial.
  final String? notice;

  /// Todo lo averiguado hasta ahora.
  final CallerFacts facts;

  final ScreeningStage stage;

  const DialogueReply({
    required this.text,
    required this.facts,
    required this.stage,
    this.endCall = false,
    this.notice,
  });
}

/// El guion que sigue el agente durante una llamada.
///
/// **Con estado y por llamada**: un motor por conversación (o `reset()` entre
/// llamadas). Eso es lo que le permite avanzar en vez de reaccionar suelto a
/// cada frase, que era el problema anterior: sin memoria de lo ya preguntado,
/// toda intervención que no casara con una regla producía la misma respuesta
/// genérica («¿podrías aclararme un poco más?») una y otra vez.
///
/// El guion rellena huecos —nombre, empresa, motivo, teléfono de contacto— y
/// cierra la llamada en cuanto tiene lo necesario, con un resumen construido a
/// partir de esos datos. Nunca le repite al interlocutor la transcripción.
///
/// Puro: no hace I/O y es determinista, así que se puede probar entero.
class DialogueEngine {
  /// Identidad completa del agente: nombre, empresa, rol, personalidad, dueño
  /// y formalidad. El guion la usa para redactar; antes solo se usaban nombre
  /// y empresa aunque el resto se pudiera configurar.
  final AgentPersona persona;

  /// Número desde el que llama el interlocutor, si se conoce. Sirve para
  /// entender «el mismo número» como número de devolución.
  String? callerNumber;

  DialogueEngine({
    String agentName = 'SentraVox',
    String agentCompany = '',
    String agentRole = '',
    String agentPersonality = '',
    String ownerName = '',
    String ownerTitle = '',
    String formality = 'profesional',
    AgentPersona? persona,
    this.callerNumber,
  }) : persona = persona ??
            AgentPersona(
              name: agentName,
              company: agentCompany,
              role: agentRole,
              personality: agentPersonality,
              ownerName: ownerName,
              ownerTitle: ownerTitle,
              formality: AgentFormality.parse(formality),
            );

  ScreeningStage _stage = ScreeningStage.identifying;
  CallerFacts _facts = const CallerFacts();

  int _turn = 0;
  int _nameAttempts = 0;
  int _purposeAttempts = 0;
  int _unclearStreak = 0;
  int _riskWarnings = 0;
  bool _probed = false;
  bool _callbackAsked = false;
  String? _lastLine;

  ScreeningStage get stage => _stage;
  CallerFacts get facts => _facts;
  int get callerTurns => _turn;

  /// El saludo con el que arranca la llamada. Si el número ya es conocido, se
  /// aprovecha lo que se recuerda de él.
  String opening() => _facts.hasName
      ? DialogueTemplates.openingKnown(
          _facts.name!,
          persona: persona,
        )
      : DialogueTemplates.opening(persona: persona);

  /// Deja el motor listo para otra llamada.
  void reset() {
    _stage = ScreeningStage.identifying;
    _facts = const CallerFacts();
    _turn = 0;
    _nameAttempts = 0;
    _purposeAttempts = 0;
    _unclearStreak = 0;
    _riskWarnings = 0;
    _probed = false;
    _callbackAsked = false;
    _lastLine = null;
  }

  /// Datos ya conocidos del número (memoria persistente entre llamadas).
  void seed(CallerFacts known) {
    _facts = _facts.merge(known);
  }

  /// Siguiente turno del agente.
  ///
  /// [intent] acepta las etiquetas de cualquiera de los dos clasificadores.
  DialogueReply generate({
    required String intent,
    required double risk,
    required String transcript,
  }) {
    final canonical = IntentLabels.canonical(intent);
    _turn++;

    _absorb(transcript, canonical);

    // 1. Riesgo por encima del umbral: no hay conversación que continuar.
    if (DialogueRules.isSpam(risk)) {
      return _close(
        DialogueTemplates.spamWarning(persona: persona),
        notice: 'Llamada cerrada por riesgo alto '
            '(${(risk * 100).toStringAsFixed(0)}%).',
      );
    }

    // 2. Temas sensibles: se avisa, no se colabora, y a la segunda se corta.
    if (DialogueRules.isSensitive(canonical)) {
      _riskWarnings++;

      if (_riskWarnings >= DialogueRules.maxRiskWarnings) {
        return _close(
          DialogueTemplates.riskClosing(persona: persona),
          notice: 'Llamada cerrada tras insistir en un tema sensible '
              '(${IntentLabels.spanishLabel(canonical)}).',
        );
      }

      _stage = ScreeningStage.probing;
      return _say(
        DialogueTemplates.riskChallenge(canonical, _facts, persona: persona),
      );
    }

    // 3. El interlocutor se despide.
    if (DialogueRules.isFarewell(canonical)) {
      return _close(DialogueTemplates.farewell(_facts, persona: persona));
    }

    // 4. Venta: el agente existe justamente para no pasar estas llamadas.
    if (DialogueRules.isSales(canonical)) {
      return _close(
        DialogueTemplates.rejectSales(_facts, persona: persona),
        notice: 'Llamada comercial rechazada por el agente.',
      );
    }

    // 5. «¿Con quién hablo?»: se responde y se retoma la pregunta pendiente.
    if (DialogueRules.isIdentityQuestion(canonical)) {
      return _say(
        '${DialogueTemplates.identity(persona: persona)} '
        '${_pendingQuestion()}',
      );
    }

    // 6. No se entendió. Se insiste sobre lo que falta, no en abstracto.
    if (DialogueRules.isUnclear(canonical) || DialogueRules.isNoise(transcript)) {
      _unclearStreak++;

      if (_unclearStreak >= DialogueRules.maxUnclearStreak) {
        return _close(
          DialogueTemplates.giveUp(persona: persona),
          notice: 'Llamada cerrada: no se entendió al interlocutor.',
        );
      }

      return _say(
        DialogueTemplates.clarify(
          _unclearStreak,
          _pendingQuestion(),
          persona: persona,
        ),
      );
    }

    _unclearStreak = 0;

    // 7. Conversación que no avanza: se cierra con lo que haya.
    if (_turn > DialogueRules.maxCallerTurns) {
      return _close(
        DialogueTemplates.tooLong(_facts, persona: persona),
        notice: 'Llamada cerrada por exceder los turnos previstos.',
      );
    }

    // 8. Guion por huecos. Cada rama pregunta una cosa concreta y avanza.
    if (!_facts.hasName && _nameAttempts < DialogueRules.maxSlotAttempts) {
      _nameAttempts++;
      _stage = ScreeningStage.identifying;
      return _say(
        DialogueTemplates.askName(_nameAttempts, persona: persona),
      );
    }

    if (!_facts.hasPurpose &&
        _purposeAttempts < DialogueRules.maxSlotAttempts) {
      _purposeAttempts++;
      _stage = ScreeningStage.purpose;
      return _say(
        DialogueTemplates.askPurpose(_purposeAttempts, _facts,
            persona: persona),
      );
    }

    if (!_probed &&
        _facts.hasPurpose &&
        !DialogueRules.isDenial(transcript) &&
        DialogueRules.hasContent(transcript)) {
      _probed = true;
      _stage = ScreeningStage.probing;
      return _say(DialogueTemplates.probe(canonical, _facts, persona: persona));
    }

    if (!_callbackAsked && !_facts.hasCallback) {
      _callbackAsked = true;
      _stage = ScreeningStage.contact;
      return _say(DialogueTemplates.askCallback(_facts, persona: persona));
    }

    // 9. Ya está todo: se resume y se cierra.
    return _close(
      DialogueTemplates.wrapUp(_facts, persona: persona),
      notice: 'El agente tomó el mensaje y cerró la llamada.',
    );
  }

  // ---------------------------------------------------------------------------
  // Interno
  // ---------------------------------------------------------------------------

  /// Actualiza los datos conocidos con lo que acaba de decir el interlocutor.
  void _absorb(String transcript, CallerIntent intent) {
    _facts = _facts.merge(FactExtractor.extract(transcript, intent: intent));

    // El saludo ya preguntó el nombre. Si el interlocutor contesta «con Carlos
    // Steven Morales Pinzón» sin un verbo, se toma como nombre mientras
    // sigamos en la etapa de identificación.
    if (!_facts.hasName && _stage == ScreeningStage.identifying) {
      final candidate = FactExtractor.nameCandidate(transcript);
      if (candidate != null) {
        _facts = _facts.copyWith(name: candidate);
      }
    }

    // «el mismo número», «a este número»: el interlocutor no quiere dictar el
    // teléfono porque es el de origen. Se toma el número entrante.
    if (!_facts.hasCallback &&
        callerNumber != null &&
        _mentionsSameNumber(transcript)) {
      _facts = _facts.copyWith(callback: callerNumber);
    }

    // Si ya se preguntó el motivo, la respuesta *es* el motivo aunque el
    // clasificador no sepa etiquetarla. Sin esto el guion se quedaba
    // preguntando lo mismo indefinidamente. Un «sí» aislado no es un motivo.
    if (!_facts.hasPurpose &&
        _purposeAttempts > 0 &&
        DialogueRules.hasContent(transcript) &&
        !DialogueRules.isDenial(transcript)) {
      final purpose = FactExtractor.summarize(transcript);
      if (purpose != null) _facts = _facts.copyWith(purpose: purpose);
    }
  }

  /// ¿El interlocutor se está refiriendo al número desde el que llama?
  static bool _mentionsSameNumber(String transcript) {
    final lower = transcript.toLowerCase();
    final mentionsPhone = lower.contains('numero') ||
        lower.contains('número') ||
        lower.contains('telefono') ||
        lower.contains('teléfono') ||
        lower.contains('contacto') ||
        lower.contains('devolver') ||
        lower.contains('llamar');
    final mentionsSame = lower.contains('mismo') ||
        lower.contains('este numero') ||
        lower.contains('este número') ||
        lower.contains('aqui') ||
        lower.contains('aquí');

    return mentionsPhone && mentionsSame;
  }

  /// La pregunta que sigue abierta, para no dejar el turno sin dirección.
  String _pendingQuestion() {
    if (!_facts.hasName) return '¿Con quién tengo el gusto de hablar?';
    if (!_facts.hasPurpose) return '¿Cuál es el motivo de su llamada?';
    if (!_facts.hasCallback) {
      return '¿A qué número puede devolverle la llamada el titular?';
    }
    return '¿Hay algo más que deba anotar?';
  }

  DialogueReply _say(String line) {
    final text = line == _lastLine ? DialogueTemplates.insist(line) : line;
    _lastLine = line;

    return DialogueReply(text: text, facts: _facts, stage: _stage);
  }

  DialogueReply _close(String line, {String? notice}) {
    _stage = ScreeningStage.finished;
    _lastLine = line;

    return DialogueReply(
      text: line,
      facts: _facts,
      stage: _stage,
      endCall: true,
      notice: notice,
    );
  }
}
