import 'package:flutter/foundation.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/reporte.dart';
import '../../domain/usecases/reporte_usecases.dart';
import 'load_state.dart';

/// Controlador (ChangeNotifier) de los rankings de venta del dashboard.
///
/// Capa `presentation`: consume el caso de uso [Reportes] y expone dos
/// listas —las más y las menos vendidas— más el estado de carga.
class ReportesController extends ChangeNotifier {
  ReportesController(this._reportes);

  final Reportes _reportes;

  LoadState state = LoadState.initial;
  List<VentaProducto> masVendidos = const [];
  List<VentaProducto> menosVendidos = const [];
  String? errorMessage;
  bool _activo = true;

  /// Carga los dos rankings en paralelo (una sola ida y vuelta de red).
  Future<void> cargar() async {
    state = LoadState.loading;
    errorMessage = null;
    _emit();

    try {
      final rankings = await Future.wait([
        _reportes.productosVendidos(limite: _limite, orden: 'desc'),
        _reportes.productosVendidos(limite: _limite, orden: 'asc'),
      ]);
      masVendidos = rankings[0];
      menosVendidos = rankings[1];
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

  /// Filas que pinta cada gráfico de ranking.
  static const int _limite = 6;

  void _emit() {
    if (_activo) notifyListeners();
  }

  @override
  void dispose() {
    _activo = false;
    super.dispose();
  }
}
