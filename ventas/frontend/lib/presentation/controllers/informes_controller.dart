import 'package:flutter/foundation.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/reporte.dart';
import '../../domain/usecases/reporte_usecases.dart';
import 'load_state.dart';

/// Atajos de rango de la barra de filtros de «Reportes».
enum AtajoRango { hoy, ayer, semana, mes, anio }

/// Etiqueta del atajo para los botones.
extension AtajoRangoTexto on AtajoRango {
  String get etiqueta => switch (this) {
    AtajoRango.hoy => 'Hoy',
    AtajoRango.ayer => 'Ayer',
    AtajoRango.semana => 'Esta semana',
    AtajoRango.mes => 'Este mes',
    AtajoRango.anio => 'Este año',
  };
}

/// Controlador (ChangeNotifier) de la pantalla «Reportes».
///
/// Los **filtros viven aquí** y no en la página: es lo que permite que al
/// cambiar de módulo y volver se conserve el informe, y que el
/// pull-to-refresh repita la consulta con el mismo rango.
///
/// Estado:
///
/// * `initial` → la página pide cargar en su `initState` (nunca se carga dos
///   veces por entrar);
/// * `loading` → solo posible **sin datos**: muestra `VistaCargando`;
/// * `error`  → no había datos que enseñar: `VistaError` + «Reintentar»;
/// * `loaded` → hay informe. Si una **actualización** falla con datos
///   previos **no se vacía nada**: se publica [avisoRefresco] para el
///   banner naranja.
///
/// Cada cambio de filtro dispara **una sola** consulta (los dos endpoints se
/// lanzan en paralelo dentro de esa consulta).
class InformesController extends ChangeNotifier {
  InformesController(this._reportes, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now {
    // Rango por defecto: el mes en curso (el informe se pide en cuanto la
    // página entra; aquí solo se siembra el estado del filtro).
    final rango = rangoAtajo(AtajoRango.mes);
    desde = rango.desde;
    hasta = rango.hasta;
  }

  final Reportes _reportes;
  final DateTime Function() _ahora;

  // --- Filtros (se conservan al volver a la pantalla) ---------------------
  DateTime desde = DateTime(2000);
  DateTime hasta = DateTime(2000);

  /// `'dia'`, `'mes'` o `'anio'` (el `SegmentedButton` Día|Mes|Año).
  String agrupacion = 'dia';

  // --- Datos y estados ----------------------------------------------------
  LoadState state = LoadState.initial;
  InformeVentas? informe;
  InformeProductos? productos;

  /// Motivo del último fallo cuando **no** hay datos previos.
  String? errorMessage;

  /// Motivo del fallo de una actualización con datos previos (banner
  /// naranja): `No se pudo actualizar: <motivo>`.
  String? avisoRefresco;

  /// Petición en curso (sirve para desactivar botones y girar el indicador).
  bool cargando = false;

  bool _activo = true;

  /// Hay informe en pantalla: define si un fallo es «banner» o «VistaError».
  bool get hayDatos => informe != null;

  /// Hay algo que exportar: informe cargado y con ventas. Un rango sin
  /// ventas no tiene nada que llevarse a un CSV ni a un PDF.
  bool get puedeExportar => hayDatos && informe!.resumen.ordenes > 0;

  /// Rango `[desde, hasta]` de un atajo, calculado sobre el reloj actual.
  ({DateTime desde, DateTime hasta}) rangoAtajo(AtajoRango atajo) {
    final hoy = _soloDia(_ahora());
    DateTime menos(int dias) => DateTime(hoy.year, hoy.month, hoy.day - dias);
    return switch (atajo) {
      AtajoRango.hoy => (desde: hoy, hasta: hoy),
      AtajoRango.ayer => (desde: menos(1), hasta: menos(1)),
      // Semana natural: lunes → hoy.
      AtajoRango.semana => (
        desde: DateTime(hoy.year, hoy.month, hoy.day - (hoy.weekday - 1)),
        hasta: hoy,
      ),
      AtajoRango.mes => (desde: DateTime(hoy.year, hoy.month, 1), hasta: hoy),
      AtajoRango.anio => (desde: DateTime(hoy.year, 1, 1), hasta: hoy),
    };
  }

  /// El atajo cuyo rango coincide con el filtro actual, o `null` si el rango
  /// fue elegido a mano (para resaltar el botón activo).
  AtajoRango? get atajoActivo {
    for (final atajo in AtajoRango.values) {
      final rango = rangoAtajo(atajo);
      if (_mismoDia(rango.desde, desde) && _mismoDia(rango.hasta, hasta)) {
        return atajo;
      }
    }
    return null;
  }

  /// Aplica un atajo y pide el informe (una sola consulta).
  void aplicarAtajo(AtajoRango atajo) {
    final rango = rangoAtajo(atajo);
    desde = rango.desde;
    hasta = rango.hasta;
    cargar();
  }

  /// Cambia el extremo «Desde»: como solo se mueve un extremo, se pide el
  /// informe **una sola vez**. Si el nuevo desde quedara por detrás de
  /// `hasta`, el otro extremo se acerca (el rango nunca queda invertido).
  void cambiarDesde(DateTime fecha) {
    desde = _soloDia(fecha);
    if (hasta.isBefore(desde)) hasta = desde;
    cargar();
  }

  /// Cambia el extremo «Hasta» (mismas reglas que [cambiarDesde]).
  void cambiarHasta(DateTime fecha) {
    hasta = _soloDia(fecha);
    if (desde.isAfter(hasta)) desde = hasta;
    cargar();
  }

  /// Cambia la agrupación (`dia|mes|anio`) y vuelve a pedir el informe.
  void cambiarAgrupacion(String valor) {
    if (valor == agrupacion) return;
    agrupacion = valor;
    cargar();
  }

  /// Consulta el informe con los filtros actuales.
  ///
  /// No vacía los datos que ya haya: solo se muestra `VistaCargando` cuando
  /// todavía no hay nada que enseñar.
  Future<void> cargar() async {
    cargando = true;
    if (!hayDatos) state = LoadState.loading;
    errorMessage = null;
    _emit();

    try {
      final respuestas = await Future.wait<Object>([
        _reportes.ventasPorRango(
          desde: desde,
          hasta: hasta,
          agrupacion: agrupacion,
        ),
        _reportes.productosPorRango(desde: desde, hasta: hasta),
      ]);
      // El servidor solo manda los periodos con ventas: los huecos del
      // rango se rellenan aquí, con la misma convención de fechas.
      final completo = (respuestas[0] as InformeVentas).conHuecos(
        desde: desde,
        hasta: hasta,
        agrupacion: agrupacion,
      );
      informe = completo;
      productos = respuestas[1] as InformeProductos;
      state = LoadState.loaded;
      avisoRefresco = null;
    } on Failure catch (failure) {
      _fallar(failure.message);
    } catch (_) {
      _fallar('Error inesperado al consultar el servidor');
    }

    cargando = false;
    _emit();
  }

  /// Fallo de consulta: banner si hay datos previos, `VistaError` si no.
  void _fallar(String motivo) {
    if (hayDatos) {
      avisoRefresco = 'No se pudo actualizar: $motivo';
      state = LoadState.loaded;
    } else {
      errorMessage = motivo;
      state = LoadState.error;
    }
  }

  /// Descarta el aviso de fallo de actualización (lo cierra el usuario o lo
  /// limpia la siguiente consulta correcta).
  void cerrarAviso() {
    avisoRefresco = null;
    _emit();
  }

  void _emit() {
    if (_activo) notifyListeners();
  }

  @override
  void dispose() {
    _activo = false;
    super.dispose();
  }

  static DateTime _soloDia(DateTime fecha) =>
      DateTime(fecha.year, fecha.month, fecha.day);

  static bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
