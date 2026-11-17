/// Clasificador de intención por reglas, en español.
///
/// Es el clasificador del camino de simulación («Probar IA del agente»): el
/// modelo ONNX todavía depende de un vocabulario de marcador de posición, así
/// que las pruebas de conversación se hacen con estas reglas.
///
/// **Solo clasifica.** Antes también generaba las respuestas del agente
/// arrastrando un historial que terminaba recitado en voz alta («según lo que
/// hemos hablado: U: … | A: …») y desembocaba siempre en «¿puedes darme más
/// detalles?». Esa parte vive ahora en `DialogueEngine`, que sí lleva el guion
/// de la llamada; aquí solo se devuelve una etiqueta.
///
/// Las etiquetas son las del vocabulario español que entiende
/// `IntentLabels.canonical` y para las que `SimulatedRiskModel` tiene riesgo
/// base.
class NlpService {
  /// Reglas en orden de prioridad: la seguridad manda, y lo específico gana a
  /// lo genérico. La primera que casa decide.
  static const List<(String, List<String>)> _rules = [
    ('fraude', [
      'fraude', 'estafa', 'scam', 'timo', 'premio', 'ganó un', 'ganaste',
      'ha ganado', 'usted ganó', 'lotería', 'loteria', 'sorteo', 'beneficiario',
      'reclamar el premio', 'código de verificación', 'codigo de verificacion',
      'código que le llegó', 'codigo que le llego', 'clave dinámica',
      'clave dinamica', 'no cuelgue', 'no le diga a nadie', 'herencia',
      'último aviso', 'ultimo aviso', 'suspenderemos', 'bloquearán',
      'bloquearan', 'actualizar sus datos',
      'validar sus datos', 'confirmar sus datos', 'cuenta bloqueada',
    ]),
    ('amenaza', [
      'amenaza', 'te voy a', 'lo voy a', 'matar', 'golpear', 'embargo',
      'demanda penal', 'denuncia penal', 'le va a pesar', 'se va a arrepentir',
      'atenerse a las consecuencias', 'orden de captura', 'extorsión',
      'extorsion',
    ]),
    ('bancario', [
      'banco', 'bancolombia', 'davivienda', 'bbva', 'nequi', 'daviplata',
      'cuenta bancaria', 'número de cuenta', 'numero de cuenta', 'tarjeta',
      'número de tarjeta', 'numero de tarjeta', 'transferencia', 'consignar',
      'consignación', 'consignacion', 'clave de su cuenta', 'clave bancaria',
      'clave de seguridad', 'contraseña bancaria', 'contrasena bancaria', 'pin',
      'token', 'cvv', 'código de seguridad', 'codigo de seguridad', 'saldo',
      'desembolso', 'préstamo', 'prestamo', 'crédito', 'credito',
      'cuenta de ahorros', 'cuenta corriente', 'datos bancarios',
      'datos de la tarjeta', 'fecha de vencimiento', 'su cuenta',
    ]),
    // Facturación va antes que venta: «plan de pagos» es un cobro, no una
    // oferta comercial, y el orden decide la etiqueta.
    ('facturacion', [
      'factura', 'facturación', 'facturacion', 'pago', 'pagar', 'cobro',
      'cobrar', 'deuda', 'en mora', 'estado de mora', 'pago en mora',
      'intereses de mora', 'recibo', 'cartera vencida', 'saldo pendiente',
      'cuota', 'mensualidad', 'plan de pagos', 'intereses', 'cobranza',
      'estado de cuenta',
    ]),
    ('venta', [
      'promoción', 'promocion', 'oferta', 'descuento', 'encuesta',
      'le ofrezco', 'le ofrecemos', 'ofrecerle', 'portabilidad', 'publicidad',
      'comercial', 'vender', 'venta de', 'plan preaprobado', 'preaprobado',
      'afiliar', 'afiliación', 'afiliacion', 'seguro de vida',
      'seguro médico', 'seguro medico', 'inversión', 'inversion',
      'bitcoin', 'criptomoneda', 'trading', 'forex', 'producto financiero',
      'tarjeta de crédito', 'tarjeta de credito', 'nuevo plan',
    ]),
    ('mensajeria', [
      'domicilio', 'paquete', 'encomienda', 'mensajería', 'mensajeria',
      'entrega', 'entregar', 'pedido', 'envío', 'envio', 'transportadora',
      'guía', 'guia', 'rappi', 'rastreo', 'courier', 'correspondencia',
    ]),
    ('soporte', [
      'soporte', 'ayuda', 'ayudar', 'problema', 'falla', 'no funciona',
      'no me funciona', 'no sirve', 'servicio técnico', 'servicio tecnico',
      'instalación', 'instalacion', 'reparar', 'revisar', 'internet', 'señal',
      'senal', 'daño', 'dano', 'configurar', 'configuración', 'configuracion',
      'lento', 'se cayó', 'se cayo', 'error', 'avería', 'averia',
    ]),
    ('buscar_persona', [
      'se encuentra', 'me comunica', 'comunicarme con', 'hablar con',
      'pasarme con', 'está el señor', 'esta el señor', 'está la señora',
      'esta la señora', 'busco a', 'con el titular', 'con el dueño',
      'está ahí', 'esta ahi', 'está en casa', 'esta en casa',
      'puedo hablar con', 'me pasa con', 'me regala una llamada con',
    ]),
    ('identidad', [
      'quién habla', 'quien habla', 'con quién hablo', 'con quien hablo',
      'quién eres', 'quien eres', 'quién es usted', 'quien es usted',
      'eres un robot', 'es un robot', 'es una grabación', 'es una grabacion',
      'es un contestador', 'con quién tengo', 'con quien tengo',
      'es una persona', 'es un humano', 'inteligencia artificial',
      'asistente virtual',
    ]),
    ('empresa', [
      'llamo de', 'llamamos de', 'le llamo de', 'de la empresa', 'soy de',
      'trabajo en', 'me comunico de', 'de parte de la empresa',
      'hablo desde', 'le contacto de', 'contacto de',
    ]),
    ('presentacion', [
      'me llamo', 'me llamó', 'mi nombre es', 'le habla',
      'habla ', 'soy ', 'de parte de', 'le saluda',
    ]),
    ('despedida', [
      'adiós', 'adios', 'hasta luego', 'chao', 'nos vemos', 'que esté bien',
      'que este bien', 'buen día entonces', 'voy a colgar', 'cuelgo',
      'muchas gracias por su tiempo',
    ]),
    ('saludo', [
      'hola', 'buenas', 'buenos días', 'buenos dias', 'buen día', 'buen dia',
      'aló', 'alo', 'qué más', 'que mas',
    ]),
  ];

  /// «¿está Carlos?», «¿se encuentra Ana?»: la forma más común de abrir una
  /// llamada preguntando por alguien, y la que ninguna palabra clave sola
  /// detecta.
  static final RegExp _askForPerson = RegExp(
    r"^(?:hola|buenas(?:\s+tardes|\s+noches)?|buenos\s+d[íi]as)?[,.\s]*[¿?\s]*"
    r"(?:est[áa]|se\s+encuentra|me\s+comunica\s+con|puedo\s+hablar\s+con)"
    r"\s+[a-záéíóúüñ']{3,}\s*[?.]?$",
    caseSensitive: false,
  );

  /// Ofertas explícitas: se comprueban antes que «bancario» porque «le ofrezco
  /// un crédito» es una venta, no una gestión del banco. Sin esto, la palabra
  /// «crédito» secuestraba la clasificación y el agente respondía con el aviso
  /// de seguridad en vez de rechazar la venta.
  static const List<String> _explicitSales = [
    'le ofrezco', 'le ofrecemos', 'ofrecerle', 'promoción', 'promocion',
    'descuento', 'portabilidad', 'publicidad', 'encuesta', 'vender',
    'venta de', 'afiliar', 'afiliación', 'afiliacion', 'preaprobado',
    'plan preaprobado',
  ];

  /// Frases que niegan una categoría y no deben dispararla. Sin esto, «no
  /// tengo ningún problema» se clasificaba como soporte y el agente preguntaba
  /// por un problema que el interlocutor acababa de negar.
  static final List<RegExp> _negatedBenign = [
    RegExp(r'\bno\s+(?:tengo|tiene|tenemos)\s+(?:ning[uú]n\s+)?problema\b',
        caseSensitive: false),
    RegExp(r'\bsin\s+(?:ning[uú]n\s+)?problema\b', caseSensitive: false),
    RegExp(r'\bno\s+(?:es|era)\s+(?:un|una)\s+problema\b',
        caseSensitive: false),
    RegExp(r'\bno\s+(?:es|era)\s+(?:una\s+)?estafa\b', caseSensitive: false),
    RegExp(r'\bno\s+necesito\s+ayuda\b', caseSensitive: false),
  ];

  static String _withoutNegations(String text) {
    var cleaned = text;
    for (final pattern in _negatedBenign) {
      cleaned = cleaned.replaceAll(pattern, ' ');
    }
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Verbos con los que alguien se presenta. Se usa para quitar el nombre del
  /// texto antes de clasificar: «me llamó Edward Mora» no debe parecer una
  /// llamada de facturación solo porque «Mora» también sea una palabra de
  /// cobranza.
  static final List<RegExp> _selfIntroPatterns = [
    RegExp(r'\bme\s+llam[oó]\s+', caseSensitive: false),
    RegExp(r'\bmi\s+nombre\s+es\s+', caseSensitive: false),
    RegExp(r'\ble\s+habla\s+', caseSensitive: false),
    RegExp(r'\ble\s+saluda\s+', caseSensitive: false),
    RegExp(
      r'\bsoy\s+(?!de\b|el\b|la\b|un\b|una\b|su\b|del\b)',
      caseSensitive: false,
    ),
  ];

  /// Palabras que cortan el nombre en una presentación.
  static const Set<String> _nameStopWords = {
    'a', 'al', 'con', 'de', 'del', 'e', 'el', 'en', 'es', 'esta', 'está',
    'estoy', 'gracias', 'hola', 'la', 'las', 'le', 'lo', 'los', 'me', 'mi',
    'nos', 'para', 'pero', 'por', 'que', 'se', 'senor', 'señor', 'senora',
    'señora', 'soy', 'su', 'te', 'tengo', 'un', 'una', 'vengo', 'y', 'ya',
    'necesito', 'quiero', 'llamo', 'llamando', 'contactando',
  };

  /// Quita «me llamo Ana» del texto para que el nombre no dispare reglas.
  static String _stripSelfIntroduction(String text) {
    for (final pattern in _selfIntroPatterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      final tail = text.substring(match.end);
      final tokens = RegExp(r"[a-záéíóúüñ']+", caseSensitive: false)
          .allMatches(tail)
          .toList();

      var end = match.end;
      var count = 0;
      for (final token in tokens) {
        final word = token.group(0)!.toLowerCase();
        if (_nameStopWords.contains(word)) break;

        end = match.end + token.end;
        count++;
        if (count == 3) break;
      }

      if (count == 0) continue;

      final before = text.substring(0, match.start).trim();
      final after = text.substring(end).trim();
      return [before, after].where((part) => part.isNotEmpty).join(' ');
    }

    return text;
  }

  /// Coincidencia por palabra completa, no por subcadena: «pin» no debe casar
  /// dentro de «pintura».
  static bool _hasKeyword(String text, String keyword) {
    final cleaned = keyword.toLowerCase().trim();
    if (cleaned.isEmpty) return false;

    final escaped = RegExp.escape(cleaned);
    return RegExp(
      '(?<![a-záéíóúüñ])$escaped(?![a-záéíóúüñ])',
      caseSensitive: false,
    ).hasMatch(text);
  }

  /// Etiqueta de la intervención. Devuelve `sin_intencion` cuando no hay nada
  /// que clasificar, para que el motor de diálogo pida una aclaración en lugar
  /// de tratarlo como una consulta.
  Future<String> classify(String text) async {
    final original = text.toLowerCase().trim();
    if (original.isEmpty) return 'sin_intencion';

    // Se quitan las negaciones antes de buscar palabras clave.
    var t = _withoutNegations(original);
    if (t.isEmpty) return 'consulta';

    final beforeIntro = t;
    t = _stripSelfIntroduction(t);
    final introduced = t != beforeIntro;
    if (t.isEmpty) return introduced ? 'presentacion' : 'consulta';

    if (_askForPerson.hasMatch(t)) return 'buscar_persona';

    // Fraude primero: sus señales son inequívocas.
    final fraud = _rules.first;
    if (fraud.$2.any((keyword) => _hasKeyword(t, keyword))) return fraud.$1;

    if (_explicitSales.any((keyword) => _hasKeyword(t, keyword))) {
      return 'venta';
    }

    for (final (label, keywords) in _rules) {
      if (label == 'fraude') continue;
      if (keywords.any((keyword) => _hasKeyword(t, keyword))) return label;
    }

    // Si había una presentación («me llamó Edward Mora») y no quedó ninguna
    // intención, se trata como presentación para que el guion no vuelva a
    // preguntar el nombre.
    return introduced ? 'presentacion' : 'consulta';
  }
}
