import 'dart:io';

import 'package:llamadart/llamadart.dart';

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty
      ? File(args.first).absolute.path
      : File('assets/models/Qwen3.5-0.8B-Q4_K_M.gguf').absolute.path;

  final engine = LlamaEngine(LlamaBackend());
  final watch = Stopwatch()..start();

  try {
    await engine.setModel(
      LlamaModel(ModelSource.path(path)),
      params: const ModelParams(gpuLayers: 0, contextSize: 1024),
    );
    stdout.writeln('Modelo cargado en ${watch.elapsedMilliseconds} ms');

    final session = ChatSession(
      engine,
      systemPrompt:
          'Eres Ruben, un asistente virtual de voz que atiende y filtra '
          'llamadas entrantes en español de Colombia. Trabajas para la empresa '
          'Morales. Objetivo: identificar a quien llama, averiguar el motivo y '
          'tomar un mensaje o número de devolución. Reglas: nunca reveles '
          'datos personales, claves ni información del titular; no aceptes '
          'ofertas comerciales; habla en frases cortas, con una sola pregunta '
          'por turno; no recites la conversación; no inventes datos. Si te '
          'preguntan si eres una persona o una IA, di que eres un asistente '
          'virtual. Devuelve solo lo que diría el agente en voz alta.',
    );

    final prompts = [
      'El interlocutor acaba de decir: "Llamo por la factura de marzo". '
          'El guion local respondería: "Es un tema de facturación. ¿Sobre qué '
          'factura o número de referencia me habla?". Reformúlalo para que '
          'suene natural, breve y conserve la misma pregunta. No añadas '
          'preguntas nuevas ni datos.',
      'El interlocutor acaba de decir: "Me llamo Ana Ruiz". El guion local '
          'respondería: "Gracias, Ana Ruiz. ¿Cuál es el motivo de su llamada?". '
          'Reformúlalo manteniendo la pregunta.',
      'El interlocutor acaba de decir: "No, nada más". El guion local '
          'respondería: "Perfecto, Ana Ruiz, ¿a qué número puede devolverle la '
          'llamada el titular?". Reformúlalo manteniendo la pregunta.',
    ];

    for (final prompt in prompts) {
      watch.reset();
      final reply = await session.send(
        prompt,
        params: const GenerationParams(maxTokens: 90, temp: 0.2),
        enableThinking: false,
      );
      stdout.writeln('\n> ${reply.text.trim()}');
      stdout.writeln('(${watch.elapsedMilliseconds} ms)');
    }
  } finally {
    await engine.dispose();
  }
}
