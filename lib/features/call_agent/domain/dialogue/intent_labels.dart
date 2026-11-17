/// Vocabulario único de intenciones para el motor de diálogo.
///
/// El proyecto tiene dos clasificadores con etiquetas distintas: `NlpService`
/// (reglas en Dart) devuelve etiquetas en español y el modelo ONNX devuelve
/// etiquetas en inglés. Antes cada uno hablaba su idioma y el motor de diálogo
/// solo entendía el inglés, así que en la simulación **ninguna** regla casaba y
/// todo caía en el «fallback» genérico: de ahí el bucle de «cuéntame más».
///
/// [CallerIntent] es la forma canónica; [IntentLabels.canonical] traduce
/// cualquiera de los dos vocabularios a ella.
enum CallerIntent {
  /// «hola», «buenas tardes».
  greeting,

  /// «¿quién habla?», «¿eres un robot?».
  identityQuestion,

  /// El interlocutor se presenta.
  provideName,

  /// El interlocutor dice de qué empresa llama.
  provideCompany,

  /// Pide hablar con el titular.
  askForPerson,

  /// Soporte / problema técnico.
  support,

  /// Facturación, pagos, cobros.
  billing,

  /// Oferta comercial, promoción, encuesta.
  sales,

  /// Mensajería, domicilio, paquete.
  delivery,

  /// Tema bancario: sensible por definición.
  banking,

  /// Señales de estafa.
  fraud,

  /// Intimidación o lenguaje violento.
  threat,

  /// «adiós», «hasta luego».
  farewell,

  /// No se entendió nada útil.
  unclear,

  /// Se entendió, pero no encaja en ninguna categoría.
  other,
}

class IntentLabels {
  const IntentLabels._();

  /// Etiquetas de `NlpService` (español) → forma canónica.
  static const Map<String, CallerIntent> _spanish = {
    'saludo': CallerIntent.greeting,
    'identidad': CallerIntent.identityQuestion,
    'presentacion': CallerIntent.provideName,
    'empresa': CallerIntent.provideCompany,
    'buscar_persona': CallerIntent.askForPerson,
    'soporte': CallerIntent.support,
    'facturacion': CallerIntent.billing,
    'venta': CallerIntent.sales,
    'mensajeria': CallerIntent.delivery,
    'bancario': CallerIntent.banking,
    'fraude': CallerIntent.fraud,
    'amenaza': CallerIntent.threat,
    'despedida': CallerIntent.farewell,
    'consulta': CallerIntent.other,
    'sin_intencion': CallerIntent.unclear,
  };

  /// Etiquetas del clasificador ONNX (inglés) → forma canónica.
  static const Map<String, CallerIntent> _english = {
    'greeting': CallerIntent.greeting,
    'identity': CallerIntent.identityQuestion,
    'provide_name': CallerIntent.provideName,
    'provide_company': CallerIntent.provideCompany,
    'ask_for_person': CallerIntent.askForPerson,
    'support': CallerIntent.support,
    'billing': CallerIntent.billing,
    'sales': CallerIntent.sales,
    'delivery': CallerIntent.delivery,
    'banking': CallerIntent.banking,
    'spam': CallerIntent.fraud,
    'fraud': CallerIntent.fraud,
    'threat': CallerIntent.threat,
    'farewell': CallerIntent.farewell,
    'unknown': CallerIntent.other,
    '': CallerIntent.unclear,
  };

  /// Traduce una etiqueta de cualquiera de los dos clasificadores.
  ///
  /// Una etiqueta desconocida cae en [CallerIntent.other] —«se entendió pero no
  /// sé clasificarlo»— y no en `unclear`, para que el guion siga avanzando en
  /// lugar de pedir aclaraciones eternamente.
  static CallerIntent canonical(String? label) {
    final key = (label ?? '').trim().toLowerCase();
    if (key.isEmpty) return CallerIntent.unclear;
    return _spanish[key] ?? _english[key] ?? CallerIntent.other;
  }

  /// Etiqueta en español para mostrar y para guardar en el historial.
  static String spanishLabel(CallerIntent intent) {
    for (final entry in _spanish.entries) {
      if (entry.value == intent) return entry.key;
    }
    return 'consulta';
  }

  /// Intenciones que ya traen el motivo de la llamada consigo.
  ///
  /// `askForPerson` queda fuera a propósito: «¿está Carlos?» dice a quién busca,
  /// no para qué llama. `other` también queda fuera: una respuesta genérica
  /// como «con Carlos Steven Morales» no es un motivo; si de verdad trae un
  /// motivo, lo detecta una marca explícita («llamo por…»).
  static bool carriesPurpose(CallerIntent intent) {
    return const {
      CallerIntent.support,
      CallerIntent.billing,
      CallerIntent.sales,
      CallerIntent.delivery,
      CallerIntent.banking,
    }.contains(intent);
  }

  /// Temas que el agente nunca debe tratar como una consulta normal.
  static bool isSensitive(CallerIntent intent) {
    return const {
      CallerIntent.banking,
      CallerIntent.fraud,
      CallerIntent.threat,
    }.contains(intent);
  }
}
