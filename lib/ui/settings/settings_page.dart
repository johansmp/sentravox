import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/call_agent/data/llm/llm_responder.dart';
import '../../features/call_agent/domain/dialogue/agent_persona.dart';
import '../../features/call_agent/domain/dialogue/dialogue_engine.dart';
import '../../features/call_screening/platform/call_control_bridge.dart';
import '../../features/settings/presentation/settings_scope.dart';
import '../../shared/services/llm/local_llm_service.dart';
import '../../shared/services/tts/neural_tts_service.dart';
import '../../shared/services/tts/tts_service.dart';
import '../../shared/voice/voice_profiles.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const CallControlBridge _callControl = CallControlBridge();

  final TextEditingController _numberController = TextEditingController();

  bool? _isDefaultDialer;
  bool? _hasScreeningRole;
  bool? _canAnswer;

  final LocalLlmService _localLlm = LocalLlmService.shared;
  bool _localLlmBusy = false;
  String? _localLlmStatus;
  String? _localLlmError;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final isDefault = await _callControl.isDefaultDialer();
    final hasRole = await _callControl.isScreeningRoleHeld();
    final canAnswer = await _callControl.canAnswerCalls();
    if (!mounted) return;

    setState(() {
      _isDefaultDialer = isDefault;
      _hasScreeningRole = hasRole;
      _canAnswer = canAnswer;
    });
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    final profile = SettingsScope.read(context).settings.voiceProfile;
    final ok = await HybridTtsService(voiceProfile: profile).speak(text);

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Voz reproducida. La primera vez puede tardar en preparar la '
                  'voz neuronal; si falla, se usa la voz del sistema.'
              : 'No se pudo reproducir la voz. Revisa el motor TTS del sistema.',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _testVoice() async {
    final current = SettingsScope.read(context).settings;
    final agentName = current.agentName.trim().isEmpty
        ? 'SentraVox'
        : current.agentName.trim();
    final role = current.agentRole.trim().isEmpty
        ? ''
        : ', ${current.agentRole.trim()}';
    final owner = current.ownerName.trim().isEmpty
        ? ''
        : '. Atiendo las llamadas de ${current.ownerName.trim()}';

    await _speak(
      'Hola, soy $agentName$role$owner. '
      'Esta es una prueba de voz del agente.',
    );
  }

  Future<void> _prepareLocalLlm() async {
    if (_localLlmBusy) return;

    setState(() {
      _localLlmBusy = true;
      _localLlmError = null;
      _localLlmStatus = 'Copiando y cargando el modelo local…';
    });

    try {
      await _localLlm.ensureLoaded();
      if (!mounted) return;
      setState(() {
        _localLlmBusy = false;
        _localLlmStatus = 'Modelo local listo. Funciona sin Wi-Fi ni datos.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _localLlmBusy = false;
        _localLlmStatus = null;
        _localLlmError = 'No se pudo cargar el modelo local: $e';
      });
    }
  }

  Future<void> _testLocalLlm() async {
    final current = SettingsScope.read(context).settings;
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _localLlmBusy = true;
      _localLlmError = null;
      _localLlmStatus = 'Generando una respuesta con el modelo local…';
    });

    final persona = AgentPersona(
      name: current.agentName,
      company: current.agentCompany,
      role: current.agentRole,
      personality: current.agentPersonality,
      ownerName: current.ownerName,
      ownerTitle: current.ownerTitle,
      formality: AgentFormality.parse(current.formality),
    );

    final reply = await _localLlm.complete(
      systemPrompt: LlmPromptBuilder.localSystemPrompt(persona),
      userPrompt: LlmPromptBuilder.buildLocal(
        transcript: 'Llamo por la factura de marzo',
        localDraft: 'Es un tema de facturación. ¿Sobre qué factura o número '
            'de referencia me habla?',
      ),
      // El emulador y los teléfonos lentos pueden tardar bastante más que una
      // llamada real; esta prueba es interactiva y puede esperar.
      timeout: const Duration(seconds: 60),
    );

    if (!mounted) return;
    setState(() {
      _localLlmBusy = false;
      _localLlmStatus = reply == null
          ? null
          : 'El modelo local respondió correctamente.';
      _localLlmError = reply == null
          ? (_localLlm.lastError ??
              'El modelo local no respondió. Revisa la preparación del modelo.')
          : null;
    });

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          reply == null
              ? 'El modelo local no respondió. El agente seguirá usando el '
                  'guion local.'
              : 'IA local: $reply',
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  Future<void> _showAudioDiagnostics() async {
    final route = await _callControl.audioDiagnostics();
    final tts = await TtsService().audioDiagnostics();
    if (!mounted) return;

    String render(Map<String, Object?> map) {
      if (map.isEmpty) return 'Sin datos (¿plataforma sin soporte?)';
      return map.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ruta de audio'),
        content: SingleChildScrollView(
          child: Text(
            'Llamada:\n${render(route)}\n\n'
            'Motor de voz:\n${render(tts)}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final current = settings.settings;
    final enabled = current.securityEnabled;

    final previewPersona = AgentPersona(
      name: current.agentName,
      company: current.agentCompany,
      role: current.agentRole,
      personality: current.agentPersonality,
      ownerName: current.ownerName,
      ownerTitle: current.ownerTitle,
      formality: AgentFormality.parse(current.formality),
    );
    final openingPreview = DialogueEngine(persona: previewPersona).opening();

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SwitchListTile(
            value: current.securityEnabled,
            onChanged: settings.isLoading ? null : settings.setSecurityEnabled,
            title: const Text('Protección activa'),
            subtitle: const Text(
              'Filtra las llamadas entrantes y permite que el agente responda.',
            ),
          ),
          const Divider(),

          // El resto de ajustes no tiene efecto con la protección apagada, así
          // que se deshabilitan para no dar una impresión falsa.
          SwitchListTile(
            value: current.autoActivateAgent,
            onChanged: enabled ? settings.setAutoActivateAgent : null,
            title: const Text('Activar agente automáticamente'),
            subtitle: const Text(
              'Atiende las llamadas de números desconocidos.',
            ),
          ),
          SwitchListTile(
            value: current.agentAllCalls,
            onChanged: enabled && current.autoActivateAgent
                ? settings.setAgentAllCalls
                : null,
            title: const Text('Atender también contactos conocidos'),
            subtitle: const Text(
              'El agente responde cualquier llamada que pase el filtro de '
              'riesgo; tú no hablas. Los números bloqueados siguen bloqueados.',
            ),
          ),
          // Filtrar una llamada y descolgarla son dos permisos distintos: sin
          // esto el agente se abre pero el teléfono sigue sonando.
          SwitchListTile(
            value: current.autoAnswer,
            onChanged: enabled && current.autoActivateAgent
                ? settings.setAutoAnswer
                : null,
            title: const Text('Contestar automáticamente'),
            subtitle: Text(
              _canAnswer == false
                  ? 'Falta el permiso «Responder llamadas»: el agente no puede '
                      'descolgar solo.'
                  : 'El agente descuelga, habla con voz sintética y nunca usa '
                      'la voz del usuario.',
            ),
          ),
          SwitchListTile(
            value: current.blockUnknown,
            onChanged: enabled ? settings.setBlockUnknown : null,
            title: const Text('Bloquear todos los desconocidos'),
            subtitle: Text(
              current.agentAllCalls
                  ? 'Los desconocidos se bloquean; el agente solo atenderá '
                      'contactos conocidos.'
                  : 'Rechaza cualquier número sin identificar, sin analizarlo.',
            ),
          ),

          ListTile(
            enabled: enabled,
            title: const Text('Umbral de bloqueo'),
            subtitle: Text(
              'Se bloquea a partir de '
              '${(current.blockThreshold * 100).toStringAsFixed(0)}% de riesgo. '
              '${current.autoActivateAgent ? 'Los desconocidos con riesgo bajo '
                  'los atiende el agente en vez de bloquearlos.' : ''}',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              value: current.blockThreshold,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              label: '${(current.blockThreshold * 100).toStringAsFixed(0)}%',
              onChanged: enabled ? settings.setBlockThreshold : null,
            ),
          ),
          const Divider(),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Perfil del agente (prompt engine)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          _SettingsTextField(
            label: 'Nombre del agente',
            value: current.agentName,
            onChanged: settings.setAgentName,
          ),
          _SettingsTextField(
            label: 'Empresa que representa',
            value: current.agentCompany,
            onChanged: settings.setAgentCompany,
          ),
          _SettingsTextField(
            label: 'Rol',
            value: current.agentRole,
            onChanged: settings.setAgentRole,
          ),
          _SettingsTextField(
            label: 'Personalidad',
            value: current.agentPersonality,
            onChanged: settings.setAgentPersonality,
          ),
          _SettingsTextField(
            label: 'Nombre del propietario',
            value: current.ownerName,
            onChanged: settings.setOwnerName,
          ),
          _SettingsTextField(
            label: 'Cargo del propietario',
            value: current.ownerTitle,
            onChanged: settings.setOwnerTitle,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DropdownButtonFormField<String>(
              key: ValueKey('formality-${current.formality}'),
              initialValue: current.formality,
              decoration: const InputDecoration(
                labelText: 'Formalidad del trato',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'profesional', child: Text('Profesional')),
                DropdownMenuItem(value: 'corporativo', child: Text('Corporativo')),
                DropdownMenuItem(value: 'amable', child: Text('Amable')),
              ],
              onChanged: (v) {
                if (v != null) settings.setFormality(v);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Estos datos cambian el saludo, las preguntas y el cierre. El '
              'rol y la personalidad también forman el prompt de la IA local.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vista previa del saludo',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    openingPreview,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _speak(openingPreview),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Escuchar saludo'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Voz del agente',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DropdownButtonFormField<String>(
              key: ValueKey('voice-profile-${current.voiceProfile}'),
              initialValue: current.voiceProfile,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Perfil de voz (5 opciones)',
                isDense: true,
              ),
              items: voiceProfiles
                  .map(
                    (profile) => DropdownMenuItem(
                      value: profile.id,
                      child: Text(profile.label),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) settings.setVoiceProfile(v);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Voces neuronales Piper offline: suenan naturales y no necesitan '
              'red. La primera vez se prepara el modelo; si no está listo, el '
              'agente usa la voz del sistema como respaldo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Ruta de audio en llamada',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DropdownButtonFormField<String>(
              key: ValueKey('audio-mode-${current.inCallAudioMode}'),
              initialValue: current.inCallAudioMode,
              decoration: const InputDecoration(
                labelText: 'Cómo llega la voz al interlocutor',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'acoustic',
                  child: Text('Altavoz (compatible)'),
                ),
                DropdownMenuItem(
                  value: 'direct',
                  child: Text('Inyección directa (experimental)'),
                ),
                DropdownMenuItem(
                  value: 'auto',
                  child: Text('Automática (directa con respaldo)'),
                ),
              ],
              onChanged: (v) {
                if (v != null) settings.setInCallAudioMode(v);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Android no permite a una app normal escribir en el canal de '
              'subida de una llamada PSTN. «Altavoz» usa el micrófono del '
              'teléfono para transmitir la voz sintética; «directa» intenta '
              'enviarla por AudioTrack y depende del fabricante. Si falla, se '
              'cae al altavoz. El agente nunca usa la voz del usuario.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _testVoice,
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Probar voz'),
                ),
                OutlinedButton.icon(
                  onPressed: _showAudioDiagnostics,
                  icon: const Icon(Icons.graphic_eq),
                  label: const Text('Ver ruta de audio'),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_voice_outlined),
            title: const Text('Voz sin conexión'),
            subtitle: const Text(
              'Descarga el paquete de español del reconocimiento para que el '
              'agente entienda al interlocutor sin Wi-Fi. Sin ese paquete, el '
              'sistema intenta usar la red.',
            ),
            trailing: TextButton(
              onPressed: _callControl.openVoiceInputSettings,
              child: const Text('Abrir'),
            ),
          ),
          const Divider(),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'IA local (sin internet)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          SwitchListTile(
            value: current.llmEnabled,
            onChanged: (value) {
              settings.setLlmEnabled(value);
              if (value) {
                _prepareLocalLlm();
              } else {
                // Liberar la memoria del modelo si el usuario lo desactiva.
                unawaited(_localLlm.dispose());
              }
            },
            title: const Text('Usar modelo de lenguaje local'),
            subtitle: const Text(
              'Qwen3.5 0.8B incluido en la app. Todo se ejecuta en el teléfono: '
              'no se envía audio ni texto a internet y funciona en modo avión.',
            ),
          ),
          if (current.llmEnabled) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'El modelo se copia una vez al almacenamiento interno '
                '(≈508 MB). La primera carga puede tardar; después solo '
                'reescribe la respuesta del guion. Si falla o tarda, el agente '
                'sigue con el guion local sin cortar la llamada.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (_localLlmBusy)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: LinearProgressIndicator(),
              ),
            if (_localLlmStatus != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _localLlmStatus!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_localLlmError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _localLlmError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _localLlmBusy ? null : _prepareLocalLlm,
                    icon: const Icon(Icons.download_done),
                    label: const Text('Preparar modelo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _localLlmBusy ? null : _testLocalLlm,
                    icon: const Icon(Icons.memory),
                    label: const Text('Probar IA local'),
                  ),
                ],
              ),
            ),
          ],
          const Divider(),

          // Sin este permiso Android nunca invoca el servicio de filtrado:
          // ninguna llamada llega al agente, por muchos ajustes que se
          // enciendan. Va primero porque es el requisito de todo lo demás.
          ListTile(
            leading: Icon(
              _hasScreeningRole == true
                  ? Icons.verified_user
                  : Icons.gpp_maybe_outlined,
              color: _hasScreeningRole == false
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
            title: const Text('Permiso para filtrar llamadas'),
            subtitle: Text(
              switch (_hasScreeningRole) {
                null => 'Comprobando…',
                true => 'Concedido: SentraVox analiza las llamadas entrantes.',
                false => 'Sin este permiso Android no avisa a SentraVox y '
                    'ninguna llamada llega al agente.',
              },
            ),
            trailing: _hasScreeningRole == false
                ? TextButton(
                    onPressed: () async {
                      final result = await _callControl.requestScreeningRole();
                      await _checkPermissions();

                      final explanation = result.explanation;
                      if (explanation == null || !context.mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(explanation)),
                      );
                    },
                    child: const Text('Conceder'),
                  )
                : null,
          ),

          ListTile(
            title: const Text('App de teléfono predeterminada'),
            subtitle: Text(
              switch (_isDefaultDialer) {
                null => 'Comprobando…',
                true => 'SentraVox es la app predeterminada.',
                false =>
                  'Opcional: solo hace falta para que el agente pueda colgar '
                      'llamadas de riesgo.',
              },
            ),
            trailing: _isDefaultDialer == false
                ? TextButton(
                    onPressed: () async {
                      await _callControl.requestDefaultDialer();
                      await _checkPermissions();
                    },
                    child: const Text('Configurar'),
                  )
                : null,
          ),
          const Divider(),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Lista de bloqueo',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _numberController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: 'Número a bloquear',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () async {
                    await settings.addToBlocklist(_numberController.text);
                    _numberController.clear();
                  },
                ),
              ],
            ),
          ),
          if (settings.blocklist.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('No hay números bloqueados.'),
            )
          else
            ...settings.blocklist.map(
              (number) => ListTile(
                dense: true,
                leading: const Icon(Icons.block, size: 20),
                title: Text(number),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => settings.removeFromBlocklist(number),
                ),
              ),
            ),

          if (settings.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                settings.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

/// Campo de texto controlado que no pierde el cursor.
///
/// Antes cada reconstrucción creaba un `TextEditingController` nuevo dentro de
/// `build`: el cursor saltaba y, al escribir, el texto podía revertirse. Aquí
/// el controlador vive en el estado y solo se sincroniza cuando el campo no
/// tiene el foco.
class _SettingsTextField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _SettingsTextField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_SettingsTextField> createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<_SettingsTextField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    // Al salir del campo, si el guardado falló y el ajuste se revirtió, se
    // muestra el valor persistido en vez de dejar un texto que no se guardó.
    if (!_focusNode.hasFocus &&
        mounted &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void didUpdateWidget(covariant _SettingsTextField oldWidget) {
    super.didUpdateWidget(oldWidget);

    // No pisar lo que el usuario está escribiendo. Si el cambio viene de otro
    // lado (o de una reversión por error de guardado), sí se refleja.
    if (!_focusNode.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}
