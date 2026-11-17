import 'package:flutter/material.dart';

/// Observador global de rutas.
///
/// La pantalla de inicio lo usa para recargar estadísticas cuando una ruta
/// apilada encima suyo se cierra. Sin esto, al volver de una llamada la tarjeta
/// seguía diciendo «Sin llamadas analizadas hoy» aunque la llamada ya estuviera
/// guardada: los contadores solo se cargaban al arrancar y al abrir el
/// historial.
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
