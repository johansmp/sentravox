import 'intent_labels.dart';

/// Predicados del guion de filtrado. Sin estado y sin I/O: solo deciden.
///
/// Trabajan sobre [CallerIntent], no sobre las cadenas del clasificador, así
/// que valen igual para el clasificador de reglas en Dart y para el ONNX.
class DialogueRules {
  const DialogueRules._();

  /// Riesgo a partir del cual la llamada se corta sin más conversación.
  static const double spamThreshold = 0.7;

  /// Turnos del interlocutor que se aceptan antes de cerrar por longitud. Un
  /// filtro de llamadas resuelve en pocos turnos; si se pasa de aquí es que la
  /// conversación no avanza.
  static const int maxCallerTurns = 10;

  /// Intervenciones seguidas sin entender antes de rendirse.
  static const int maxUnclearStreak = 3;

  /// Veces que se insiste en un dato antes de seguir sin él.
  static const int maxSlotAttempts = 2;

  /// Avisos por tema sensible antes de cortar.
  static const int maxRiskWarnings = 2;

  static bool isSpam(double risk) => risk > spamThreshold;

  static bool isGreeting(CallerIntent intent) => intent == CallerIntent.greeting;

  static bool isIdentityQuestion(CallerIntent intent) =>
      intent == CallerIntent.identityQuestion;

  static bool isFarewell(CallerIntent intent) => intent == CallerIntent.farewell;

  static bool isSales(CallerIntent intent) => intent == CallerIntent.sales;

  static bool isBilling(CallerIntent intent) => intent == CallerIntent.billing;

  static bool isSupport(CallerIntent intent) => intent == CallerIntent.support;

  static bool isSensitive(CallerIntent intent) => IntentLabels.isSensitive(intent);

  static bool isUnclear(CallerIntent intent) => intent == CallerIntent.unclear;

  /// Una intervención que no aporta contenido: ruido, monosílabos, muletillas.
  ///
  /// «sí» y «no» son cortos pero sí significan algo: se excluyen a propósito,
  /// porque son la respuesta esperada a «¿algo más?».
  static bool isNoise(String text) {
    final cleaned = _clean(text);
    if (cleaned.isEmpty) return true;

    final words = cleaned.split(' ');
    if (words.length > 1) return false;

    final word = words.single;
    if (affirmatives.contains(word) || negatives.contains(word)) return false;

    return word.length <= 2 || _fillers.contains(word);
  }

  /// Confirmación breve («sí», «claro»).
  static bool isAffirmation(String text) {
    final word = _singleWord(text);
    return word != null && affirmatives.contains(word);
  }

  /// Negación breve («no», «nada más»): el interlocutor no tiene más que decir.
  static bool isDenial(String text) {
    final word = _singleWord(text);
    if (word != null) return negatives.contains(word);

    final cleaned = _clean(text);
    return cleaned == 'nada mas' ||
        cleaned == 'nada más' ||
        cleaned == 'no nada' ||
        cleaned == 'no gracias' ||
        cleaned == 'eso es todo' ||
        cleaned == 'no eso es todo' ||
        cleaned == 'no senor' ||
        cleaned == 'no señor' ||
        cleaned == 'no senora' ||
        cleaned == 'no señora';
  }

  /// ¿La intervención aporta contenido reutilizable?
  ///
  /// Un «sí» o un «no» aislado es una respuesta, no un motivo ni un nombre.
  /// Antes se tomaba como motivo y el agente terminaba anotando «motivo: sí».
  static bool hasContent(String text) {
    final cleaned = _clean(text);
    if (cleaned.isEmpty) return false;

    final word = _singleWord(text);
    if (word != null) {
      return !affirmatives.contains(word) &&
          !negatives.contains(word) &&
          !_fillers.contains(word) &&
          word.length > 2;
    }

    return true;
  }

  static const Set<String> affirmatives = {
    'si', 'sí', 'claro', 'correcto', 'exacto', 'afirmativo', 'dale', 'sip',
  };

  static const Set<String> negatives = {
    'no', 'ninguno', 'ninguna', 'nada', 'negativo', 'nop', 'tampoco',
  };

  static const Set<String> _fillers = {
    'aja', 'ajá', 'ah', 'eh', 'em', 'este', 'mmm', 'mm', 'hmm', 'uy', 'ok',
    'okey', 'bueno', 'listo', 'ya', 'aló', 'alo', 'hey', 'mjm',
  };

  static String _clean(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-záéíóúüñ\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// El texto reducido a una sola palabra, o null si tiene varias.
  static String? _singleWord(String text) {
    final cleaned = _clean(text);
    if (cleaned.isEmpty) return null;

    final words = cleaned.split(' ');
    return words.length == 1 ? words.single : null;
  }
}
