import 'intent_labels.dart';

/// Lo que el agente ha conseguido averiguar de quien llama.
///
/// Son los «huecos» que el guion de filtrado intenta rellenar. Inmutable: cada
/// turno produce unos datos nuevos y [merge] los combina sin sobrescribir lo ya
/// confirmado.
class CallerFacts {
  final String? name;
  final String? company;
  final String? purpose;
  final String? callback;

  const CallerFacts({this.name, this.company, this.purpose, this.callback});

  bool get hasName => (name ?? '').isNotEmpty;
  bool get hasCompany => (company ?? '').isNotEmpty;
  bool get hasPurpose => (purpose ?? '').isNotEmpty;
  bool get hasCallback => (callback ?? '').isNotEmpty;

  bool get isEmpty => !hasName && !hasCompany && !hasPurpose && !hasCallback;

  /// Combina dos conjuntos de datos. Lo primero que se averigua manda: si el
  /// interlocutor ya dio su nombre, una frase posterior no lo reescribe.
  CallerFacts merge(CallerFacts other) {
    return CallerFacts(
      name: hasName ? name : other.name,
      company: hasCompany ? company : other.company,
      purpose: hasPurpose ? purpose : other.purpose,
      callback: hasCallback ? callback : other.callback,
    );
  }

  CallerFacts copyWith({
    String? name,
    String? company,
    String? purpose,
    String? callback,
  }) {
    return CallerFacts(
      name: name ?? this.name,
      company: company ?? this.company,
      purpose: purpose ?? this.purpose,
      callback: callback ?? this.callback,
    );
  }

  /// Solo lo que vale la pena recordar entre llamadas del mismo número.
  Map<String, String> toMemoryMap() => {
        if (hasName) 'name': name!,
        if (hasCompany) 'company': company!,
        if (hasCallback) 'callback': callback!,
      };

  @override
  String toString() =>
      'CallerFacts(name: $name, company: $company, purpose: $purpose, '
      'callback: $callback)';
}

/// Extrae datos concretos de lo que dice el interlocutor.
///
/// Puro y determinista: solo expresiones regulares sobre el texto en español.
/// No pretende ser un NER; pretende que el agente pueda decir «Le paso el
/// mensaje: Ana, de Claro, llama por una factura» en lugar de repetirle al
/// interlocutor el volcado de la conversación.
class FactExtractor {
  const FactExtractor._();

  /// Palabras que nunca forman parte de un nombre propio ni de una empresa.
  /// Cortan la captura: «soy Juan de Bancolombia» → nombre «Juan».
  static const Set<String> _stopWords = {
    'a', 'al', 'ante', 'aqui', 'aquí', 'buen', 'buena', 'buenas', 'bueno',
    'buenos', 'con', 'como', 'cual', 'cuál', 'de', 'del', 'desde', 'dias',
    'días', 'donde', 'dónde', 'el', 'ella', 'ellos', 'en', 'es', 'esta',
    'está', 'este', 'gracias', 'hola', 'la', 'las', 'le', 'lo', 'los', 'mas',
    'más', 'me', 'mi', 'muy', 'no', 'noches', 'nos', 'para', 'pero', 'por',
    'porque', 'que', 'qué', 'quien', 'quién', 'se', 'señor', 'señora', 'si',
    'sí', 'sobre', 'su', 'sus', 'tardes', 'te', 'tu', 'un', 'una', 'uno',
    'usted', 'y', 'ya', 'yo',
    // Frases de respuesta que no son un nombre.
    'gusto', 'favor', 'dije', 'dijo', 'digo', 'sabes', 'sabe', 'acuerdo',
    'recuerdo', 'contactando', 'comunicarme', 'comunico', 'hablando',
    'senor', 'senora', 'trabajo', 'vengo', 'quiero', 'necesito', 'tengo',
    'busco', 'requiero', 'estoy',
    // Muletillas: no son nombres.
    'aja', 'ajá', 'ah', 'eh', 'em', 'mmm', 'mm', 'hmm', 'uy', 'ok', 'okey',
    'listo', 'aló', 'alo', 'hey', 'mjm',
    // Cargos y genéricos: no son nombres de persona.
    'asesor', 'asesora', 'agente', 'atencion', 'atención', 'banco', 'cliente',
    'compania', 'compañia', 'compañía', 'ejecutiva', 'ejecutivo', 'empresa',
    'encargado', 'llamada', 'llamando', 'llamo', 'operador', 'operadora',
    'representante', 'servicio', 'soporte', 'tecnico', 'técnico', 'titular',
    'vendedor',
  };

  static const int _maxNameWords = 5;
  static const int _maxCompanyWords = 4;

  /// Palabras que cortan un nombre de empresa. Se parecen a [_stopWords] pero
  /// no incluyen «banco» ni «compañía»: «Soy de Banco de Bogotá» debe capturar
  /// «Banco», no descartarlo por ser un cargo genérico.
  static const Set<String> _companyStopWords = {
    'a', 'al', 'ante', 'aqui', 'aquí', 'buen', 'buena', 'buenas', 'bueno',
    'buenos', 'con', 'como', 'cual', 'cuál', 'de', 'del', 'desde', 'donde',
    'dónde', 'el', 'ella', 'ellos', 'en', 'es', 'esta', 'está', 'este',
    'gracias', 'hola', 'la', 'las', 'le', 'lo', 'los', 'mas', 'más', 'me',
    'mi', 'muy', 'no', 'noches', 'nos', 'para', 'parte', 'pero', 'por',
    'porque', 'que', 'qué', 'quien', 'quién', 'se', 'si', 'sí', 'sobre',
    'su', 'sus', 'tardes', 'te', 'tu', 'un', 'una', 'uno', 'usted', 'y',
    'ya', 'yo', 'empresa', 'compañía', 'compania', 'llamo', 'llamando',
    'llamamos', 'habla', 'hablo', 'hablamos', 'trabajo', 'soy',
  };

  static final RegExp _wordChars = RegExp(r"[a-záéíóúüñ']+", caseSensitive: false);

  static final List<RegExp> _namePatterns = [
    RegExp(r'\bme\s+llam[oó]\s+(.{2,60})', caseSensitive: false),
    RegExp(r'\bmi\s+nombre\s+es\s+(.{2,60})', caseSensitive: false),
    RegExp(r'\b(?:le\s+)?habla\s+(.{2,60})', caseSensitive: false),
    RegExp(r'\b(?:le\s+)?saluda\s+(.{2,60})', caseSensitive: false),
    // «con Carlos Steven Morales»: respuesta directa a «¿con quién hablo?».
    // Los artículos y «gusto» los descarta _titleCase.
    RegExp(
      r'\bcon\s+(?!el\b|la\b|los\b|las\b|un\b|una\b|mi\b|su\b)(.{2,60})',
      caseSensitive: false,
    ),
    // «soy Ana», pero no «soy de Claro» ni «soy el técnico».
    RegExp(
      r'\bsoy\s+(?!de\b|el\b|la\b|un\b|una\b|su\b|del\b)(.{2,60})',
      caseSensitive: false,
    ),
  ];

  static final List<RegExp> _companyPatterns = [
    RegExp(r'\bde\s+(?:la\s+)?(?:empresa|compañía|compania)\s+(.{2,60})',
        caseSensitive: false),
    // «soy Juan de Bancolombia»: la empresa va detrás del nombre.
    RegExp(
      r"\b(?:me\s+llamo|mi\s+nombre\s+es|soy|(?:le\s+)?habla)\s+"
      r"(?!de\b)[a-záéíóúüñ']+(?:\s+[a-záéíóúüñ']+)?\s+de\s+(?:la\s+)?(.{2,60})",
      caseSensitive: false,
    ),
    RegExp(r'\btrabajo\s+en\s+(.{2,60})', caseSensitive: false),
    RegExp(
      r'\b(?:le\s+)?(?:llamo|llamamos|hablo|escribo|contacto)\s+'
      r'(?:desde|de)\s+(?:parte\s+de\s+)?(?:la\s+)?(.{2,60})',
      caseSensitive: false,
    ),
    RegExp(r'\bde\s+parte\s+de\s+(?:la\s+)?(.{2,60})', caseSensitive: false),
    RegExp(r'\bhablo\s+desde\s+(?:la\s+)?(.{2,60})', caseSensitive: false),
    RegExp(r'\bsoy\s+de\s+(?:la\s+)?(.{2,60})', caseSensitive: false),
    RegExp(r'\bme\s+comunico\s+de\s+(?:la\s+)?(.{2,60})', caseSensitive: false),
  ];

  /// Un teléfono colombiano tiene 7 (fijo antiguo), 10 (móvil o fijo nuevo) o
  /// 12–13 dígitos con indicativo. Menos de 7 suele ser un número de factura.
  static final RegExp _phonePattern =
      RegExp(r'(?:\+?\d[\d\s\-().]{5,17}\d)');

  /// Palabras que delatan que se está dictando un teléfono, no otra cifra.
  static const List<String> _phoneHints = [
    'numero', 'número', 'celular', 'telefono', 'teléfono', 'movil', 'móvil',
    'whatsapp', 'contacto', 'llamar al', 'devolver la llamada', 'marque',
    'marcar', 'digite', 'dictar', 'comunicarse al',
  ];

  /// Dígitos dictados de uno en uno («tres cero cero...»).
  static const Map<String, int> _spokenDigits = {
    'cero': 0,
    'uno': 1,
    'una': 1,
    'dos': 2,
    'tres': 3,
    'cuatro': 4,
    'cinco': 5,
    'seis': 6,
    'siete': 7,
    'ocho': 8,
    'nueve': 9,
  };

  /// Palabras que por sí solas no son un motivo de llamada.
  static const Set<String> _nonPurposeWords = {
    'si', 'sí', 'no', 'claro', 'correcto', 'exacto', 'bueno', 'listo', 'ok',
    'okey', 'nada', 'gracias', 'hola', 'buenas', 'buenos', 'alo', 'aló',
    'aja', 'ajá', 'mmm', 'mm', 'eh', 'ah', 'ya', 'dale',
  };

  /// Datos deducibles de una intervención.
  static CallerFacts extract(String text, {CallerIntent? intent}) {
    final normalized = text.trim();
    if (normalized.isEmpty) return const CallerFacts();

    final company = _firstMatch(_companyPatterns, normalized, company: true);
    var name = _firstMatch(_namePatterns, normalized);

    // «soy de Claro» captura la empresa por el patrón de nombre también; si el
    // texto sí menciona empresa y el nombre coincide, se descarta el nombre.
    if (name != null && company != null && name.toLowerCase() == company.toLowerCase()) {
      name = null;
    }

    final hasPurposeMarker = _hasPurposeMarker(normalized);
    final carriesPurpose =
        intent != null && IntentLabels.carriesPurpose(intent);

    return CallerFacts(
      name: name,
      company: company,
      callback: _extractPhone(normalized),
      purpose: hasPurposeMarker || carriesPurpose
          ? summarize(normalized)
          : null,
    );
  }

  static bool _hasPurposeMarker(String text) {
    final lower = text.toLowerCase();
    return _purposeMarkers.any(lower.contains);
  }

  /// Marcas que anuncian el motivo de la llamada. El resumen empieza ahí, así
  /// la presentación («hola, soy Ana de Claro») no se cuela en el motivo.
  static const List<String> _purposeMarkers = [
    'llamo por', 'llamo para', 'llamando por', 'llamando para',
    'le llamo por', 'le llamo para', 'vengo por', 'vengo a',
    'me comunico por', 'le contacto por', 'contacto por',
    'el motivo es', 'el motivo de mi llamada es', 'por el tema de',
    'es por', 'es sobre', 'es acerca de', 'es para',
    'necesito', 'necesitamos', 'quiero', 'quisiera', 'requiero', 'busco',
    'tengo un problema', 'tengo una queja', 'tengo una consulta',
    'quería saber', 'queria saber', 'solicitar', 'reportar',
    'para avisar', 'para informar', 'para confirmar', 'para cancelar',
    'para renovar', 'para agendar', 'para programar', 'traigo',
  ];

  static final RegExp _greetingPrefix = RegExp(
    r'^(?:hola|buenas|buenos(?:\s+d[íi]as)?|muy\s+buenos(?:\s+d[íi]as)?)'
    r'\b[^,.]{0,20}[,.\s]+',
    caseSensitive: false,
  );

  static final RegExp _leadingFiller = RegExp(
    r'^(?:le\s+)?(?:llamo|llamando|estoy\s+llamando|el\s+motivo\s+es|es|por|'
    r'para|sobre|acerca\s+de|que|vengo|solo|solamente|quería|queria)\s+',
    caseSensitive: false,
  );

  /// Palabras que, al abrir el motivo, van en minúscula: el motivo se dice
  /// dentro de una frase del agente («Anoto: la factura de marzo»).
  static final Set<String> _lowercaseStarters = {
    ..._stopWords,
    'estamos', 'estoy', 'había', 'habia', 'hay', 'llamo', 'necesitamos',
    'necesito', 'podria', 'podría', 'puede', 'queria', 'quería', 'quiero',
    'quisiera', 'requiero', 'seria', 'sería', 'somos', 'soy', 'tengo',
    'traigo', 'vengo', 'vamos', 'busco',
  };

  /// El motivo de la llamada, recortado a algo que se pueda decir en voz alta.
  static String? summarize(String text, {int maxWords = 16}) {
    var cleaned = text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceFirst(_greetingPrefix, '')
        .replaceAll(RegExp(r'^[¿¡"\s]+'), '')
        .trim();

    if (cleaned.isEmpty) return null;

    // Cortar por la primera marca de motivo que aparezca.
    final lower = cleaned.toLowerCase();
    var cut = -1;
    for (final marker in _purposeMarkers) {
      final index = lower.indexOf(marker);
      if (index >= 0 && (cut < 0 || index < cut)) cut = index;
    }
    if (cut > 0) cleaned = cleaned.substring(cut);

    // «llamo por su factura» → «su factura». Se repite porque las marcas se
    // encadenan («llamo» + «por»).
    for (var i = 0; i < 3; i++) {
      final stripped = cleaned.replaceFirst(_leadingFiller, '').trim();
      if (stripped == cleaned) break;
      cleaned = stripped;
    }
    if (cleaned.isEmpty) return null;

    final words = cleaned.split(' ');
    final kept = words.take(maxWords).join(' ');
    var trimmed = kept.replaceAll(RegExp(r'[.,;:!?]+$'), '');

    if (trimmed.isEmpty) return null;

    // Un «sí» o un «no» no es un motivo de llamada, aunque tenga contenido
    // conversacional. Antes el agente anotaba «motivo: sí».
    final trimmedWords = trimmed.split(' ');
    if (trimmedWords.length == 1 &&
        _nonPurposeWords.contains(trimmedWords.first.toLowerCase())) {
      return null;
    }

    if (_lowercaseStarters.contains(words.first.toLowerCase())) {
      trimmed = trimmed[0].toLowerCase() + trimmed.substring(1);
    }

    return words.length > maxWords ? '$trimmed…' : trimmed;
  }

  static String? _firstMatch(
    List<RegExp> patterns,
    String text, {
    bool company = false,
  }) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      final candidate = _titleCase(match.group(1) ?? '', company: company);
      if (candidate != null) return candidate;
    }
    return null;
  }

  /// Toma hasta [_maxNameWords] palabras útiles y las capitaliza.
  static String? _titleCase(String raw, {bool company = false}) {
    final words = <String>[];
    final stops = company ? _companyStopWords : _stopWords;
    final limit = company ? _maxCompanyWords : _maxNameWords;

    for (final match in _wordChars.allMatches(raw)) {
      final word = match.group(0)!.toLowerCase();
      if (stops.contains(word)) break;
      if (word.length < 2) break;

      words.add(word[0].toUpperCase() + word.substring(1));
      if (words.length == limit) break;
    }

    if (words.isEmpty) return null;
    return words.join(' ');
  }

  /// Fallback para cuando el interlocutor responde al nombre sin verbo.
  ///
  /// La pregunta «¿Con quién tengo el gusto de hablar?» se responde a menudo
  /// con «con Carlos Andrés Ramírez Gómez» o simplemente «Carlos». Si no hay un
  /// patrón explícito, se valida que el texto parezca un nombre (1–5 palabras,
  /// sin verbos, artículos ni cifras) y se devuelve capitalizado.
  static String? nameCandidate(String text) {
    var candidate = text.trim();
    if (candidate.isEmpty || RegExp(r'\d').hasMatch(candidate)) return null;

    const prefixes = [
      'habla con ',
      'le habla ',
      'le saluda ',
      'me llamo ',
      'me llamó ',
      'mi nombre es ',
      'con ',
      'soy ',
    ];

    final lower = candidate.toLowerCase();
    for (final prefix in prefixes) {
      if (lower.startsWith(prefix)) {
        candidate = candidate.substring(prefix.length).trim();
        break;
      }
    }

    candidate = candidate.replaceAll(RegExp(r'[.,;:!?]+$'), '').trim();
    if (candidate.isEmpty) return null;

    final words = candidate.split(RegExp(r'\s+'));
    if (words.length > _maxNameWords) return null;

    for (final word in words) {
      final clean = word.toLowerCase().replaceAll(RegExp(r"[^a-záéíóúüñ']"), '');
      if (clean.isEmpty) return null;
      if (_stopWords.contains(clean)) return null;
      if (!RegExp(r"^[a-záéíóúüñ']+$", caseSensitive: false).hasMatch(word)) {
        return null;
      }
    }

    return _titleCase(candidate);
  }

  static String? _extractPhone(String text) {    final lower = text.toLowerCase();

    // «mi número de factura» o «mi cuenta es ...» no son teléfonos. Se exige
    // una palabra claramente telefónica en esos contextos para no guardar una
    // referencia bancaria como número de devolución.
    final nonPhoneContext = const [
      'factura', 'cuenta', 'pedido', 'guia', 'guía', 'referencia', 'orden',
    ].any(lower.contains);
    final clearPhone = const [
      'celular', 'telefono', 'teléfono', 'movil', 'móvil', 'whatsapp',
      'contacto', 'devolver', 'llamar', 'marque', 'digite', 'dictar',
    ].any(lower.contains);

    if (nonPhoneContext && !clearPhone) return null;

    final hinted = _phoneHints.any(lower.contains);
    final match = _phonePattern.firstMatch(text);

    if (match != null) {
      final digits = match.group(0)!.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 7 && digits.length <= 13) {
        // Un número de 7 dígitos puede ser cualquier cosa; se exige una pista.
        if (digits.length >= 10 || hinted) return digits;
      }
    }

    // Sin cifras escritas: «tres, cero, cero, uno...». Solo se intenta si el
    // interlocutor dijo claramente que está dictando un teléfono, para no
    // confundir «uno, dos, tres» con una cuenta.
    if (!hinted) return null;
    final spoken = _spokenPhone(text);
    if (spoken == null) return null;

    if (spoken.length >= 10) return spoken;
    return null;
  }

  /// Convierte una secuencia de dígitos dictados en palabras a un número.
  static String? _spokenPhone(String text) {
    final tokens = RegExp(r"[a-záéíóúüñ]+", caseSensitive: false)
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();

    final digits = StringBuffer();
    for (final token in tokens) {
      final digit = _spokenDigits[token];
      if (digit != null) {
        digits.write(digit);
        continue;
      }

      // Cualquier palabra que no sea un dígito corta la secuencia. Si ya hay
      // un número plausible, se devuelve; si no, se sigue buscando.
      if (digits.length >= 7) return digits.toString();
      digits.clear();
    }

    return digits.length >= 7 ? digits.toString() : null;
  }
}
