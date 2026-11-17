import 'package:flutter/material.dart';

import '../features/call_logs/domain/entities/call_log_stats.dart';
import '../features/call_logs/domain/repositories/call_log_repository.dart';
import '../features/call_logs/domain/usecases/get_call_log_stats.dart';
import '../features/call_logs/domain/usecases/get_call_logs.dart';
import '../features/call_screening/domain/entities/screening_diagnostics.dart';
import '../features/call_screening/platform/call_control_bridge.dart';
import '../features/settings/presentation/settings_scope.dart';
import '../shared/navigation/route_observer.dart';
import 'agent/agent_test_page.dart';
import 'call_logs/call_logs_page.dart';
import 'diagnostics/diagnostics_page.dart';
import 'settings/settings_page.dart';
import 'widgets/sentravox_card.dart';

class HomePage extends StatefulWidget {
  final CallLogRepository callLogRepository;

  const HomePage({super.key, required this.callLogRepository});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver, RouteAware {
  static const CallControlBridge _callControl = CallControlBridge();

  late final GetCallLogs _getCallLogs;
  late final GetCallLogStats _getStats;

  CallLogStats _stats = const CallLogStats();
  ScreeningDiagnostics? _diagnostics;
  PageRoute<dynamic>? _subscribedRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _getCallLogs = GetCallLogs(widget.callLogRepository);
    _getStats = GetCallLogStats(widget.callLogRepository);
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _subscribedRoute) {
      if (_subscribedRoute != null) {
        appRouteObserver.unsubscribe(this);
      }
      _subscribedRoute = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al cerrar una ruta apilada (llamada, ajustes, historial…) hay que releer
  /// los contadores: una llamada pudo terminar y guardarse durante ese tiempo.
  @override
  void didPopNext() {
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Los permisos se conceden en pantallas del sistema: al volver, revisar.
    if (state == AppLifecycleState.resumed) _loadDiagnostics();
    super.didChangeAppLifecycleState(state);
  }

  Future<void> _refresh() async {
    await Future.wait([_loadStats(), _loadDiagnostics()]);
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _getStats();
      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (_) {
      // Sin historial todavía: se quedan los contadores en cero.
    }
  }

  Future<void> _loadDiagnostics() async {
    final diagnostics = await _callControl.diagnostics();
    if (!mounted) return;
    setState(() => _diagnostics = diagnostics);
  }

  Future<void> _openDiagnostics() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const DiagnosticsPage()),
    );
    // Los permisos pudieron cambiar mientras estaba abierto.
    await _loadDiagnostics();
  }

  Future<void> _openLogs() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CallLogsPage(getCallLogs: _getCallLogs),
      ),
    );
    // El historial pudo cambiar mientras estaba abierto.
    await _loadStats();
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final securityEnabled = settings.securityEnabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SentraVox'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Si falta un permiso, el agente no contesta y el síntoma no dice
            // por qué. Se avisa aquí en vez de esperar a que el usuario lo
            // descubra recibiendo una llamada.
            if (_diagnostics?.canConverse == false) ...[
              _DiagnosticsWarning(
                message: _diagnostics!.headline,
                onTap: _openDiagnostics,
              ),
              const SizedBox(height: 16),
            ],

            SentraVoxCard(
              title: 'Estado del agente',
              subtitle: securityEnabled
                  ? 'Protección activa'
                  : 'Protección desactivada',
              icon: securityEnabled ? Icons.shield_moon : Icons.shield_outlined,
              color: securityEnabled ? Colors.blueAccent : Colors.grey,
              trailing: Switch(
                value: securityEnabled,
                onChanged: settings.isLoading
                    ? null
                    : (value) => settings.setSecurityEnabled(value),
              ),
            ),
            if (settings.error != null) ...[
              const SizedBox(height: 12),
              _SettingsError(message: settings.error!),
            ],
            const SizedBox(height: 16),

            SentraVoxCard(
              title: 'Últimas llamadas filtradas',
              subtitle: _stats.todayLabel,
              icon: Icons.call,
              color: Colors.green,
              onTap: _openLogs,
            ),
            const SizedBox(height: 16),

            SentraVoxCard(
              title: 'Estafas detectadas',
              subtitle: _stats.blockedLabel,
              icon: Icons.warning_amber_rounded,
              color: _stats.blocked > 0 ? Colors.redAccent : Colors.grey,
              onTap: _openLogs,
            ),
            const SizedBox(height: 16),

            SentraVoxCard(
              title: 'Configuración',
              subtitle: 'Preferencias del agente',
              icon: Icons.settings,
              color: Colors.grey,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
            ),
            const SizedBox(height: 16),

            SentraVoxCard(
              title: 'Probar IA del agente',
              subtitle: 'Simulación de conversación',
              icon: Icons.smart_toy_outlined,
              color: Colors.deepPurple,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const AgentTestPage()),
              ),
            ),
            const SizedBox(height: 16),

            SentraVoxCard(
              title: 'Diagnóstico',
              subtitle: _diagnostics == null
                  ? 'Comprobando permisos…'
                  : (_diagnostics!.canConverse
                      ? 'Todos los permisos concedidos'
                      : 'Falta algo para que el agente conteste'),
              icon: Icons.health_and_safety_outlined,
              color: switch (_diagnostics?.canConverse) {
                null => Colors.grey,
                true => Colors.teal,
                false => Colors.orange,
              },
              onTap: _openDiagnostics,
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsWarning extends StatelessWidget {
  final String message;
  final VoidCallback onTap;

  const _DiagnosticsWarning({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.report_problem_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Toca para ver qué falta.',
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onErrorContainer),
          ],
        ),
      ),
    );
  }
}

class _SettingsError extends StatelessWidget {
  final String message;

  const _SettingsError({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
