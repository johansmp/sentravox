import 'package:flutter/material.dart';

import '../../features/call_logs/domain/entities/call_log.dart';
import '../../features/call_screening/domain/entities/screening_diagnostics.dart';
import '../../features/call_screening/platform/call_control_bridge.dart';

/// Por qué el agente no contesta.
///
/// Una llamada tiene que atravesar varias puertas —rol de filtrado, permiso
/// para descolgar, micrófono, aviso a pantalla completa— y si falla cualquiera
/// el síntoma es siempre el mismo: el teléfono suena y nadie contesta. Esta
/// pantalla las separa, en orden de dependencia: arreglar una de abajo sin
/// tener las de arriba no cambia nada.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage>
    with WidgetsBindingObserver {
  static const CallControlBridge _callControl = CallControlBridge();

  ScreeningDiagnostics? _diagnostics;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Los permisos se conceden en pantallas del sistema: al volver, revisar.
    if (state == AppLifecycleState.resumed) _refresh();
    super.didChangeAppLifecycleState(state);
  }

  Future<void> _refresh() async {
    final result = await _callControl.diagnostics();
    if (!mounted) return;
    setState(() => _diagnostics = result);
  }

  Future<void> _act(Future<void> Function() action) async {
    await action();
    await _refresh();
  }

  /// El rol puede no estar disponible en el dispositivo: en ese caso el botón
  /// no abre nada y hay que decir por qué.
  Future<void> _requestRole() async {
    final result = await _callControl.requestScreeningRole();
    await _refresh();

    final explanation = result.explanation;
    if (explanation == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(explanation),
        duration: const Duration(seconds: 6),
        action: result == ScreeningRoleRequest.roleUnavailable ||
                result == ScreeningRoleRequest.legacyDialer
            ? SnackBarAction(
                label: 'Configurar',
                onPressed: () => _act(_callControl.requestDefaultDialer),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final diagnostics = _diagnostics;

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico')),
      body: diagnostics == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Headline(diagnostics: diagnostics),
                  const SizedBox(height: 20),

                  Text(
                    'Requisitos, en orden',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),

                  _Check(
                    ok: diagnostics.screeningRole,
                    title: 'Filtrar llamadas',
                    okText: 'Android avisa a SentraVox de cada llamada.',
                    failText: diagnostics.roleAvailable
                        ? 'Sin esto no ocurre nada más: SentraVox ni se entera '
                            'de que entró una llamada.'
                        : 'Este Android no ofrece el rol de filtrado. Hace '
                            'falta ser la app de teléfono predeterminada.',
                    actionLabel: 'Conceder',
                    onAction: _requestRole,
                    secondaryLabel: 'App de teléfono',
                    onSecondary: () => _act(_callControl.requestDefaultDialer),
                  ),
                  _Check(
                    ok: diagnostics.answerCalls,
                    title: 'Responder llamadas',
                    okText: 'El agente puede descolgar y colgar.',
                    failText: 'El agente ve la llamada pero no puede '
                        'contestarla: seguirá sonando.',
                    actionLabel: 'Conceder',
                    onAction: () => _act(_callControl.requestPermissions),
                    secondaryLabel: 'Ajustes de la app',
                    onSecondary: () => _act(_callControl.openAppSettings),
                  ),
                  _Check(
                    ok: diagnostics.recordAudio,
                    title: 'Micrófono',
                    okText: 'El agente puede escuchar al interlocutor.',
                    failText: 'Sin micrófono el agente habla pero no entiende '
                        'nada de lo que le dicen.',
                    actionLabel: 'Conceder',
                    onAction: () => _act(_callControl.requestPermissions),
                  ),
                  _Check(
                    ok: diagnostics.readContacts,
                    title: 'Contactos',
                    okText: 'Se distingue un desconocido de un contacto.',
                    failText: 'Sin contactos, casi cualquier llamada se toma '
                        'por desconocida.',
                    actionLabel: 'Conceder',
                    onAction: () => _act(_callControl.requestPermissions),
                  ),
                  _Check(
                    ok: diagnostics.notifications,
                    title: 'Notificaciones',
                    okText: 'Se puede avisar de la llamada en curso.',
                    failText: 'Sin aviso, la pantalla del agente puede no '
                        'abrirse con la app en segundo plano.',
                    actionLabel: 'Conceder',
                    onAction: () => _act(_callControl.requestPermissions),
                  ),
                  _Check(
                    ok: diagnostics.fullScreenIntent,
                    title: 'Pantalla completa en llamadas',
                    okText: 'La pantalla del agente puede abrirse sola.',
                    failText: 'La llamada se contesta igual, pero el agente '
                        'aparecerá como notificación en vez de a pantalla '
                        'completa.',
                    actionLabel: 'Conceder',
                    onAction: () => _act(_callControl.requestFullScreenIntent),
                    optional: true,
                  ),
                  _Check(
                    ok: diagnostics.defaultDialer,
                    title: 'App de teléfono predeterminada',
                    okText: 'SentraVox es la app de teléfono.',
                    failText: 'Opcional. No hace falta para contestar ni para '
                        'filtrar.',
                    actionLabel: null,
                    onAction: null,
                    optional: true,
                  ),

                  const SizedBox(height: 20),
                  Text(
                    'Última llamada filtrada',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _LastScreeningCard(last: diagnostics.lastScreening),

                  const SizedBox(height: 20),
                  Text(
                    'Android API ${diagnostics.sdkInt}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
    );
  }
}

class _Headline extends StatelessWidget {
  final ScreeningDiagnostics diagnostics;

  const _Headline({required this.diagnostics});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = diagnostics.canConverse;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ok ? scheme.secondaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.report_problem_outlined,
            color: ok ? scheme.onSecondaryContainer : scheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              diagnostics.headline,
              style: TextStyle(
                color:
                    ok ? scheme.onSecondaryContainer : scheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  final bool ok;
  final String title;
  final String okText;
  final String failText;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Su ausencia degrada la experiencia pero no impide contestar.
  final bool optional;

  const _Check({
    required this.ok,
    required this.title,
    required this.okText,
    required this.failText,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final color = ok
        ? Colors.green
        : (optional ? scheme.outline : scheme.error);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok
                ? Icons.check_circle
                : (optional ? Icons.remove_circle_outline : Icons.cancel),
            size: 20,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  ok ? okText : failText,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!ok && actionLabel != null)
                  Row(
                    children: [
                      TextButton(
                        onPressed: onAction,
                        child: Text(actionLabel!),
                      ),
                      if (secondaryLabel != null)
                        TextButton(
                          onPressed: onSecondary,
                          child: Text(secondaryLabel!),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LastScreeningCard extends StatelessWidget {
  final LastScreening? last;

  const _LastScreeningCard({required this.last});

  @override
  Widget build(BuildContext context) {
    final entry = last;

    if (entry == null) {
      return Text(
        'Ninguna todavía. Si ya recibiste una llamada y aquí no aparece nada, '
        'Android no está invocando el filtrado: revisa el primer requisito.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final time = entry.at;
    final stamp = '${time.day.toString().padLeft(2, '0')}/'
        '${time.month.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${entry.number} · $stamp'),
        const SizedBox(height: 2),
        Text(
          'Decisión: ${CallOutcome.label(entry.outcome)} · '
          'riesgo ${(entry.risk * 100).toStringAsFixed(0)}%',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
