import 'package:flutter/foundation.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/reporte.dart';
import '../../domain/usecases/reporte_usecases.dart';
import 'load_state.dart';

/// Controlador (ChangeNotifier) de la pantalla «Reportes».
///
/// Capa `presentation`: consume el caso de uso [Reportes] y expone el
/// informe de periodos (serie + resumen) y el de productos/categorías,
/// además de los **filtros activos** (rango y agrupación), que son los que
/// la página pinta en la barra de herramientas.
///
/// Los filtros viven aquí y no en la página para que `MainScreen` pueda
/// refrescar el módulo al volver a él sin perder el rango elegido.
class InformeController extends ChangeNotifier {
  InformeController(Reportes reportes) : this._(reportes, _diaDeHoy());

  InformeController._(this._reportes, this.hasta)
    : desde = DateTime(hasta.year, hasta.month, 1);

  final Reportes _reportes;

  LoadState state = LoadState.initial;
  String? errorMessage;

  /// Informe de periodos (serie + resumen); `null` mientras no se cargue.
  InformeVentas? ventas;

  /// Productos y categorías del mismo rango; `null` mientras no se cargue.
  InformeProductos? detalle;

  List<VentaProducto> get productos => detalle?.productos ?? const [];

  List<VentaCategoria> get categorias => detalle?.categorias ?? const [];

  /// Primer día del rango (inclusive).
  DateTime desde;

  /// Último día del rango (inclusive).
  DateTime hasta;

  /// `dia`, `mes` o `anio`.
  String agrupacion = 'dia';

  /// Carga (o recarga) el informe con los filtros actuales.
  ///
  /// Los dos pedidos salen en paralelo y **solo se publican juntos**: si uno
  /// falla, se conserva la pantalla anterior en vez de dejarla a medias.
  Future<void> cargar() async {
    state = LoadState.loading;
    errorMessage = null;
    _emit();

    try {
      final periodo = _reportes.ventasPorPeriodo(
        desde: desde,
        hasta: hasta,
        agrupacion: agrupacion,
      );
      final productosFuturo = _reportes.ventasPorProductoYCategoria(
        desde: desde,
        hasta: hasta,
      );
      // `Future.wait` engancha los dos errores (si solo se esperara el
      // primero, el segundo quedaría sin escuchar).
      final datos = await Future.wait<Object>([
        periodo,
        productosFuturo,
      ]);
      final informe = datos[0] as InformeVentas;
      final productosCategorias = datos[1] as InformeProductos;

      ventas = informe;
      detalle = productosCategorias;
      state = LoadState.loaded;
    } on Failure catch (failure) {
      errorMessage = failure.message;
      state = LoadState.error;
    } catch (_) {
      errorMessage = 'Error inesperado al consultar el servidor';
      state = LoadState.error;
    }
    _emit();
  }

  /// Alias para el refresco de `MainScreen` (recarga con los filtros que ya
  /// tiene puestos).
  Future<void> recargar() => cargar();

  /// Cambia el rango y/o la agrupación y vuelve a pedir el informe.
  Future<void> aplicar({
    DateTime? desde,
    DateTime? hasta,
    String? agrupacion,
  }) {
    if (desde != null) this.desde = desde;
    if (hasta != null) this.hasta = hasta;
    if (agrupacion != null) this.agrupacion = agrupacion;
    return cargar();
  }

  /// Día de hoy normalizado (sin hora): fecha de una sola lectura para que
  /// `desde` y `hasta` no acaben en días distintos si el reloj cruza la
  /// medianoche justo entre las dos llamadas.
  static DateTime _diaDeHoy() {
    final hoy = DateTime.now();
    return DateTime(hoy.year, hoy.month, hoy.day);
  }

  void _emit() {
    if (_activo) notifyListeners();
  }

  bool _activo = true;

  @override
  void dispose() {
    _activo = false;
    super.dispose();
  }
}
