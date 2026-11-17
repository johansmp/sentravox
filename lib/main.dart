import 'dart:async';

import 'package:flutter/material.dart';

import 'features/call_logs/data/datasources/call_log_local_datasource.dart';
import 'features/call_logs/data/repositories_impl/call_log_repository_impl.dart';
import 'features/call_logs/domain/repositories/call_log_repository.dart';
import 'features/call_logs/domain/usecases/save_call_log.dart';
import 'features/call_screening/domain/usecases/import_screening_events.dart';
import 'features/call_screening/platform/call_screening_bridge.dart';
import 'features/settings/data/datasources/settings_datasource.dart';
import 'features/settings/data/repositories_impl/settings_repository_impl.dart';
import 'features/settings/presentation/controllers/settings_controller.dart';
import 'features/settings/presentation/settings_scope.dart';
import 'shared/navigation/route_observer.dart';
import 'shared/services/llm/local_llm_service.dart';
import 'shared/services/tts/neural_tts_service.dart';
import 'ui/agent/agent_page.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

void main() {
  runApp(const SentraVoxApp());
}

class SentraVoxApp extends StatefulWidget {
  const SentraVoxApp({super.key});

  @override
  State<SentraVoxApp> createState() => _SentraVoxAppState();
}

class _SentraVoxAppState extends State<SentraVoxApp>
    with WidgetsBindingObserver {
  /// Necesario para poder navegar desde un callback nativo: cuando entra una
  /// llamada, quien decide abrir el agente es el servicio de screening, no un
  /// widget con BuildContext.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  final CallScreeningBridge _screeningBridge = const CallScreeningBridge();

  late final CallLogRepository _callLogRepository;
  late final SettingsController _settingsController;
  late final ImportScreeningEvents _importScreeningEvents;

  /// Evita apilar varias pantallas de agente si llegan avisos repetidos.
  bool _agentPageOpen = false;

  /// Los ajustes se cargan de forma asíncrona y el navegador tarda un frame en
  /// existir. Si la activación llega antes, se guarda aquí en lugar de
  /// descartarse: era una de las formas de perder la llamada.
  ({String number, double risk})? _deferredActivation;

  bool _settingsReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _callLogRepository = CallLogRepositoryImpl(CallLogLocalDatasource());

    _settingsController = SettingsController(
      SettingsRepositoryImpl(const SettingsDatasource()),
    );

    _importScreeningEvents = ImportScreeningEvents(
      bridge: _screeningBridge,
      saveCallLog: SaveCallLog(_callLogRepository),
    );

    _screeningBridge.attach(onActivateAgent: _onActivateAgent);

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _settingsController.load();
    _settingsReady = true;

    // Prepara la voz neuronal en segundo plano: copia los modelos Piper y
    // extrae espeak-ng. Si falla, el TTS del sistema sigue disponible.
    unawaited(
      NeuralTtsService.shared.ensureReady().catchError((Object _) {}),
    );

    // Una llamada pudo entrar con la app cerrada: el servicio nativo dejó la
    // activación anotada y este es el primer momento en que se puede atender.
    // Se recoge **antes** de importar: al recogerla, el nativo retira de la
    // cola el evento de esa llamada para que no aparezca dos veces en el
    // historial (el agente escribirá su propio registro al colgar).
    final pending = await _screeningBridge.consumePendingActivation();

    // Llamadas filtradas mientras la app estaba cerrada: el servicio nativo las
    // encoló y aquí pasan al historial.
    await _importScreeningEvents();

    if (pending != null && pending.isFresh(DateTime.now())) {
      _onActivateAgent(pending.number, pending.risk);
    }

    _flushDeferredActivation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver al frente —por ejemplo tocando el aviso de llamada entrante—
    // se comprueba si hay una llamada esperando al agente.
    if (state == AppLifecycleState.resumed) {
      _resumePendingActivation();
    }
    super.didChangeAppLifecycleState(state);
  }

  /// Recoge del lado nativo la llamada que debía atender el agente.
  Future<void> _resumePendingActivation() async {
    if (_agentPageOpen) return;

    final pending = await _screeningBridge.consumePendingActivation();
    if (pending == null) return;

    // Una activación vieja corresponde a una llamada que ya terminó: abrir el
    // agente ahí solo confundiría.
    if (!pending.isFresh(DateTime.now())) return;

    _onActivateAgent(pending.number, pending.risk);
  }

  void _onActivateAgent(String number, double risk) {
    // El interruptor de seguridad manda también aquí: el nativo ya lo consulta,
    // pero puede haber cambiado entre el screening y la activación.
    if (_settingsReady && !_settingsController.agentActivationEnabled) return;
    if (_agentPageOpen) return;

    final navigator = _navigatorKey.currentState;

    // Aún no hay navegador o ajustes: la llamada espera en vez de perderse.
    // La reintenta tanto el siguiente frame (navegador) como el final del
    // arranque (ajustes); lo que llegue primero.
    if (navigator == null || !_settingsReady) {
      _deferredActivation = (number: number, risk: risk);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _flushDeferredActivation());
      return;
    }

    // El nativo también anota la activación en SharedPreferences; si se atiende
    // por el canal, se descarta la anotación para no reabrir el agente al
    // volver al primer plano.
    _screeningBridge.consumePendingActivation();

    _agentPageOpen = true;
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (_) => AgentPage(
              number: number,
              callLogRepository: _callLogRepository,
              autoAnswer: _settingsController.settings.autoAnswerEnabled,
            ),
          ),
        )
        .whenComplete(() => _agentPageOpen = false);
  }

  void _flushDeferredActivation() {
    final pending = _deferredActivation;
    if (pending == null || !_settingsReady) return;
    if (_navigatorKey.currentState == null) return;

    _deferredActivation = null;
    _onActivateAgent(pending.number, pending.risk);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _screeningBridge.detach();
    _settingsController.dispose();
    unawaited(LocalLlmService.shared.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SettingsScope va por encima del MaterialApp para que las rutas empujadas
    // con el navigatorKey también lo vean.
    return SettingsScope(
      controller: _settingsController,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        navigatorObservers: [appRouteObserver],
        title: 'SentraVox',
        debugShowCheckedModeBanner: false,
        theme: SentraVoxTheme.light,
        darkTheme: SentraVoxTheme.dark,
        themeMode: ThemeMode.system,
        home: HomePage(callLogRepository: _callLogRepository),
      ),
    );
  }
}
