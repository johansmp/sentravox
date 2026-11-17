enum Speaker { caller, agent }

/// Una intervención de la conversación.
///
/// `intent` y `risk` solo aplican a los turnos del interlocutor: son el
/// resultado de analizar lo que dijo. Los turnos del agente los dejan en null.
class ConversationTurn {
  final Speaker speaker;
  final String text;
  final String? intent;
  final double? risk;
  final DateTime at;

  const ConversationTurn({
    required this.speaker,
    required this.text,
    required this.at,
    this.intent,
    this.risk,
  });

  factory ConversationTurn.caller(
    String text, {
    required String intent,
    required double risk,
    required DateTime at,
  }) {
    return ConversationTurn(
      speaker: Speaker.caller,
      text: text,
      intent: intent,
      risk: risk,
      at: at,
    );
  }

  factory ConversationTurn.agent(String text, {required DateTime at}) {
    return ConversationTurn(
      speaker: Speaker.agent,
      text: text,
      at: at,
    );
  }

  bool get isCaller => speaker == Speaker.caller;

  @override
  String toString() =>
      'ConversationTurn(${speaker.name}: "$text", intent: $intent, risk: $risk)';
}
