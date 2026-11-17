import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:piper_phonemize/piper_phonemize.dart' as piper;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../voice/voice_profiles.dart';
import 'tts_service.dart';

/// TTS neuronal offline con Piper/Sherpa-ONNX.
///
/// Dos voces Piper en español (femenina y masculina) y cinco perfiles de
/// velocidad. La síntesis se escribe a WAV y se reproduce por el mismo canal
/// nativo que usa la llamada, de modo que el interlocutor la oye con la ruta de
/// audio ya configurada.
class NeuralTtsService {
  static final NeuralTtsService shared = NeuralTtsService._();

  NeuralTtsService._();

  Future<void>? _initializing;
  sherpa.OfflineTts? _female;
  sherpa.OfflineTts? _male;
  bool _sherpaReady = false;
  bool _phonemizerReady = false;
  String? _lastError;

  String? get lastError => _lastError;
  bool get isReady => _female != null && _male != null;

  Future<void> ensureReady() {
    if (isReady) return Future.value();
    return _initializing ??= _initialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _initialize() async {
    _lastError = null;

    if (!_sherpaReady) {
      sherpa.initBindings();
      _sherpaReady = true;
    }

    if (!_phonemizerReady) {
      piper.initBindings();
      final dataDir = await piper.extractEspeakNgData();
      final rate = piper.PiperPhonemize.initialize(dataDir);
      if (rate < 0) {
        throw StateError('No se pudo inicializar espeak-ng para la voz.');
      }
      _phonemizerReady = true;
    }

    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/tts');
    await dir.create(recursive: true);

    Future<String> copyAsset(String asset, String name) async {
      final target = File('${dir.path}/$name');
      if (await target.exists() && await target.length() > 0) {
        return target.path;
      }
      final data = await rootBundle.load(asset);
      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return target.path;
    }

    final femaleModel =
        await copyAsset('assets/tts/es_female/model.onnx', 'es_female.onnx');
    final femaleTokens = await copyAsset(
      'assets/tts/es_female/tokens.txt',
      'es_female_tokens.txt',
    );
    final maleModel =
        await copyAsset('assets/tts/es_male/model.onnx', 'es_male.onnx');
    final maleTokens = await copyAsset(
      'assets/tts/es_male/tokens.txt',
      'es_male_tokens.txt',
    );

    _female = _buildEngine(femaleModel, femaleTokens);
    _male = _buildEngine(maleModel, maleTokens);

    debugPrint('NeuralTts: voces Piper listas');
  }

  sherpa.OfflineTts _buildEngine(String model, String tokens) {
    return sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: model,
            tokens: tokens,
          ),
          numThreads: 2,
        ),
        maxNumSentences: 4,
      ),
    );
  }

  /// Sintetiza y reproduce. Asume que [ensureReady] ya terminó.
  Future<bool> speakReady(
    String text, {
    required VoiceProfile profile,
  }) async {
    final engine = profile.male ? _male : _female;
    if (engine == null) return false;

    try {
      final phonemes = piper.PiperPhonemize.phonemize(
        text,
        voice: profile.espeakVoice,
      );
      if (phonemes.isEmpty) return false;

      debugPrint(
        'NeuralTts: generando ${text.length} caracteres, '
        '${phonemes.length} frases, perfil ${profile.id}',
      );

      final audio = engine.generateWithConfig(
        text: '',
        config: sherpa.OfflineTtsGenerationConfig(
          phonemeCodepoints: phonemes,
          speed: profile.speed,
          sid: 0,
        ),
      );
      if (audio.samples.isEmpty) return false;

      final temp = await getTemporaryDirectory();
      final wav = File(
        '${temp.path}/sentravox_tts_${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      sherpa.writeWave(
        filename: wav.path,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );

      debugPrint(
        'NeuralTts: wav listo (${audio.samples.length} muestras, '
        '${audio.sampleRate} Hz)',
      );

      final completed = await TtsService().speakWav(wav.path);
      debugPrint('NeuralTts: reproducción completada=$completed');
      if (!completed && await wav.exists()) {
        await wav.delete();
      }
      return completed;
    } catch (e) {
      _lastError = 'TTS neuronal: $e';
      debugPrint(_lastError);
      return false;
    }
  }

  Future<void> dispose() async {
    _female?.free();
    _male?.free();
    _female = null;
    _male = null;
  }
}

/// Usa la voz neuronal si está lista; si no, cae al TTS del sistema.
///
/// La primera inicialización puede tardar en copiar el modelo y extraer
/// espeak-ng. Para no alargar el saludo de una llamada, el primer turno usa el
/// sistema si la voz neuronal no está lista en 3 s; la carga sigue en segundo
/// plano para los siguientes turnos.
class HybridTtsService extends TtsService {
  final String voiceProfile;
  final bool useNeural;

  HybridTtsService({
    this.voiceProfile = 'femenina_natural',
    this.useNeural = true,
  });

  VoiceProfile get profile => voiceProfileFor(voiceProfile);

  @override
  Future<void> warmUp() async {
    if (!useNeural) return;
    try {
      await NeuralTtsService.shared.ensureReady().timeout(
        const Duration(seconds: 12),
      );
    } catch (_) {
      // El fallback al sistema sigue disponible.
    }
  }

  @override
  Future<bool> speak(String text, {Duration? timeout}) async {
    if (useNeural) {
      try {
        await NeuralTtsService.shared
            .ensureReady()
            .timeout(const Duration(seconds: 3));
        final completed = await NeuralTtsService.shared.speakReady(
          text,
          profile: profile,
        );
        if (completed) return true;
      } catch (e) {
        debugPrint('NeuralTts fallback al sistema: $e');
      }
    }

    return super.speak(
      text,
      timeout: timeout ?? const Duration(seconds: 45),
    );
  }
}
