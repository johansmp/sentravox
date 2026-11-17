import 'agent_persona.dart';
import 'caller_facts.dart';
import 'intent_labels.dart';

/// Todo lo que el agente puede decir, en español y sin lógica.
///
/// Reglas de la casa:
/// - Nunca se le repite al interlocutor la transcripción de la conversación:
///   el agente resume con los datos que extrajo ([CallerFacts]), no con el
///   historial en bruto. Ese volcado era justamente lo que hacía que la
///   simulación pareciera un loro en vez de un agente.
/// - Cada línea termina en una pregunta concreta o cierra la llamada. Nunca en
///   un «cuéntame más» que no lleva a ninguna parte.
/// - Las variantes se eligen por índice, no al azar: el diálogo es
///   reproducible en las pruebas.
/// - El tono y el perfil vienen de [AgentPersona]. Los valores por defecto
///   conservan el guion profesional de siempre.
class DialogueTemplates {
  const DialogueTemplates._();

  static AgentPersona _persona(
    AgentPersona? persona, {
    String agentName = 'SentraVox',
    String company = '',
  }) {
    return persona ?? AgentPersona(name: agentName, company: company);
  }

  /// Lo primero que se oye al descolgar. Ya deja claro qué es esto y pide el
  /// primer dato, así el agente lleva la conversación desde el turno uno.
  static String opening({
    AgentPersona? persona,
    String agentName = 'SentraVox',
    String company = '',
  }) {
    final p = _persona(persona, agentName: agentName, company: company);
    final greeting =
        p.isFriendly ? 'Hola' : (p.isCorporate ? 'Buenos días' : 'Buenas');
    final role = p.hasRole ? ' Me desempeño como ${p.role.trim()}.' : '';
    final owner =
        p.hasOwner ? ' Atiendo las llamadas de ${p.ownerWithTitle}.' : '';
    final warm = p.isFriendly ? ' Con gusto le ayudo.' : '';
    final question = p.isFriendly
        ? '¿Me regala su nombre?'
        : '¿Con quién tengo el gusto de hablar?';

    return '$greeting, soy el asistente virtual de ${p.displayName}'
        '${p.companySuffix} y estoy atendiendo esta llamada.$role$owner$warm '
        '$question';
  }

  /// Saludo cuando ya se recuerda quién llama desde ese número.
  static String openingKnown(
    String name, {
    AgentPersona? persona,
    String agentName = 'SentraVox',
    String company = '',
  }) {
    final p = _persona(persona, agentName: agentName, company: company);
    final greeting =
        p.isFriendly ? 'Hola' : (p.isCorporate ? 'Buenos días' : 'Buenas');
    final role = p.hasRole ? ' Me desempeño como ${p.role.trim()}.' : '';
    final owner =
        p.hasOwner ? ' Atiendo las llamadas de ${p.ownerWithTitle}.' : '';
    final warm = p.isFriendly ? ' Con gusto le ayudo.' : '';

    return '$greeting, soy el asistente virtual de ${p.displayName}'
        '${p.companySuffix} y estoy atendiendo esta llamada.$role$owner$warm '
        '¿Hablo con $name?';
  }

  static String identity({AgentPersona? persona}) {
    final p = _persona(persona);
    return 'Soy un asistente virtual: atiendo y filtro las llamadas '
        '${p.ofOwner}.';
  }

  // ---------------------------------------------------------------------------
  // Relleno de datos
  // ---------------------------------------------------------------------------

  static String askName(int attempt, {AgentPersona? persona}) {
    final p = _persona(persona);

    if (attempt > 1) {
      if (p.isFriendly) {
        return 'Perdone, no le escuché bien. ¿Me repite su nombre, por favor?';
      }
      if (p.isCorporate) {
        return 'Disculpe, no logré escuchar su nombre. '
            '¿Podría repetírmelo, por favor?';
      }
      return 'No alcancé a escuchar su nombre. ¿Me lo repite, por favor?';
    }

    if (p.isFriendly) {
      return '¿Me regala su nombre, por favor?';
    }
    if (p.isCorporate) {
      return 'Para poder atenderle correctamente, '
          '¿me permite su nombre, por favor?';
    }
    return 'Para poder ayudarle necesito su nombre. ¿Me lo dice, por favor?';
  }

  static String askPurpose(
    int attempt,
    CallerFacts facts, {
    AgentPersona? persona,
  }) {
    final p = _persona(persona);
    final greeting = facts.hasName ? 'Gracias, ${facts.name}. ' : 'Gracias. ';

    if (attempt > 1) {
      if (p.isFriendly) {
        return 'Para poder ayudarle necesito saber de qué se trata. '
            '¿Me cuenta, por favor?';
      }
      if (p.isCorporate) {
        return 'Disculpe, necesito el motivo de la llamada para trasladar el '
            'mensaje. ¿Podría indicármelo?';
      }
      return 'Necesito el motivo para pasarle el mensaje al titular. '
          '¿De qué se trata exactamente?';
    }

    if (p.isFriendly) {
      return '$greeting¿En qué le puedo ayudar?';
    }
    if (p.isCorporate) {
      return '$greeting¿Cuál es el motivo de su llamada?';
    }
    return '$greeting¿Cuál es el motivo de su llamada?';
  }

  /// Una pregunta de seguimiento propia del asunto: es lo que hace que suene a
  /// agente y no a formulario.
  static String probe(
    CallerIntent intent,
    CallerFacts facts, {
    AgentPersona? persona,
  }) {
    final p = _persona(persona);
    final noted = facts.hasPurpose ? 'Anoto: ${facts.purpose}. ' : '';

    if (p.isFriendly) {
      return switch (intent) {
        CallerIntent.support =>
          'Entiendo, es un tema de soporte. $noted¿Qué le gustaría que '
              'revisáramos?',
        CallerIntent.billing =>
          'Entiendo, es un tema de facturación. $noted¿Me cuenta qué pasa con '
              'la factura?',
        CallerIntent.delivery =>
          'Es una entrega. $noted¿A qué dirección y en qué horario la trae?',
        CallerIntent.askForPerson =>
          'El titular no puede atender ahora, pero yo tomo el mensaje. '
              '$noted¿Qué le digo?',
        _ => '$noted¿Hay algún detalle más que quiera dejarle al titular?',
      };
    }

    if (p.isCorporate) {
      return switch (intent) {
        CallerIntent.support =>
          'Entiendo, es un asunto de soporte. $noted¿Qué requiere revisar el '
              'titular concretamente?',
        CallerIntent.billing =>
          'Es un asunto de facturación. $noted¿Sobre qué factura o número de '
              'referencia me informa?',
        CallerIntent.delivery =>
          'Es una entrega. $noted¿A qué dirección y en qué horario se realiza?',
        CallerIntent.askForPerson =>
          'El titular no puede atender en este momento; yo tomo el mensaje. '
              '$noted¿Qué le comunico exactamente?',
        _ => '$noted¿Hay algún detalle adicional que deba registrarle al '
            'titular?',
      };
    }

    return switch (intent) {
      CallerIntent.support =>
        'Entiendo, es un tema de soporte. $noted¿Qué debería revisar el '
            'titular concretamente?',
      CallerIntent.billing =>
        'Es un tema de facturación. $noted¿Sobre qué factura o número de '
            'referencia me habla?',
      CallerIntent.delivery =>
        'Es una entrega. $noted¿A qué dirección y en qué horario la trae?',
      CallerIntent.askForPerson =>
        'El titular no puede atender en este momento, así que yo tomo el '
            'mensaje. $noted¿Qué le digo exactamente?',
      _ => '$noted¿Hay algún detalle más que deba anotarle al titular?',
    };
  }

  static String askCallback(CallerFacts facts, {AgentPersona? persona}) {
    final p = _persona(persona);
    final name = facts.hasName ? '${facts.name}, ' : '';

    if (p.isFriendly) {
      return 'Perfecto, $name¿me regala un número para devolverle la llamada '
          'al titular?';
    }
    if (p.isCorporate) {
      return 'Muchas gracias, $name¿a qué número podemos devolverle la llamada '
          'al titular?';
    }
    return 'Perfecto, $name¿a qué número puede devolverle la llamada el '
        'titular?';
  }

  // ---------------------------------------------------------------------------
  // Cierres
  // ---------------------------------------------------------------------------

  /// Recapitulación final: solo datos, nunca la transcripción.
  static String wrapUp(CallerFacts facts, {AgentPersona? persona}) {
    final p = _persona(persona);
    final who = <String>[
      if (facts.hasName) facts.name!,
      if (facts.hasCompany) 'de ${facts.company}',
    ].join(', ');

    final notes = <String>[
      if (who.isNotEmpty) 'quien llama, $who',
      if (facts.hasPurpose) 'motivo, ${facts.purpose}',
      if (facts.hasCallback) 'teléfono de contacto, ${facts.callback}',
    ];

    final detail = notes.isEmpty
        ? 'Le aviso que entró esta llamada.'
        : 'Le anoto ${notes.join('; ')}.';

    final closing = p.isFriendly
        ? '¡Gracias por su tiempo, que tenga un buen día!'
        : (p.isCorporate
            ? 'Gracias por su tiempo.'
            : 'Gracias por su tiempo, que tenga buen día.');

    return 'Listo, ya tengo lo necesario. $detail Le paso el mensaje '
        '${p.toOwner}. $closing';
  }

  static String farewell(CallerFacts facts, {AgentPersona? persona}) {
    final p = _persona(persona);
    if (facts.hasPurpose) {
      final name = facts.hasName ? ', ${facts.name}' : '';
      final closing = p.isFriendly ? '¡Hasta luego!' : 'Hasta luego.';
      return 'Gracias por llamar$name. Le paso el mensaje '
          '${p.toOwner}. $closing';
    }
    return 'Gracias por llamar. Hasta luego.';
  }

  static String rejectSales(CallerFacts facts, {AgentPersona? persona}) {
    final p = _persona(persona);
    final name = facts.hasName ? ', ${facts.name}' : '';
    return 'Gracias$name, pero ${p.owner} no atiende ofertas comerciales por '
        'teléfono. Le pido retirar este número de su base de datos. '
        'Hasta luego.';
  }

  static String giveUp({AgentPersona? persona}) =>
      'No logro entender el motivo de la llamada. Voy a cerrar aquí; si es '
      'algo importante, vuelva a llamar y háblelo despacio. Hasta luego.';

  static String tooLong(CallerFacts facts, {AgentPersona? persona}) =>
      'Llevamos ya varios minutos y no puedo alargar más la llamada. '
      '${wrapUp(facts, persona: persona)}';

  // ---------------------------------------------------------------------------
  // Riesgo
  // ---------------------------------------------------------------------------

  static String spamWarning({AgentPersona? persona}) =>
      'Esta llamada presenta señales claras de riesgo. Por seguridad, termino '
      'aquí la conversación.';

  static String riskChallenge(
    CallerIntent intent,
    CallerFacts facts, {
    AgentPersona? persona,
  }) {
    return switch (intent) {
      CallerIntent.banking =>
        'Por seguridad no confirmo ni entrego datos bancarios por teléfono. '
            'Si de verdad llama del banco, el titular se comunicará por la '
            'línea oficial. ¿Desea dejar un mensaje?',
      CallerIntent.threat =>
        'Voy a registrar esta llamada como intimidación. Le pido mantener el '
            'respeto o termino la conversación. ¿Cuál es el motivo real de su '
            'llamada?',
      _ =>
        'Lo que me pide se parece a un intento de fraude: no voy a entregar '
            'claves, códigos ni datos personales. ¿Me dice su nombre completo '
            'y desde qué empresa llama?',
    };
  }

  static String riskClosing({AgentPersona? persona}) =>
      'Esta llamada queda marcada como riesgosa en el historial. Doy por '
      'terminada la conversación. Hasta luego.';

  // ---------------------------------------------------------------------------
  // Aclaraciones
  // ---------------------------------------------------------------------------

  /// [pending] es la pregunta que sigue abierta: aclarar sin volver a
  /// preguntar sería el bucle otra vez.
  static String clarify(int streak, String pending, {AgentPersona? persona}) {
    return switch (streak) {
      1 => 'Perdone, no le escuché bien. $pending',
      _ => 'Sigo sin entenderle. Hable un poco más despacio, por favor. '
          '$pending',
    };
  }

  /// Cuando el agente tendría que repetirse literalmente.
  static String insist(String line) => 'Disculpe que insista: $line';
}
