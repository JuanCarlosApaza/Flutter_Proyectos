import 'package:flutter/foundation.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/health_status.dart';
import '../../domain/usecases/get_health_status.dart';
import 'load_state.dart';

/// Controlador (ChangeNotifier) del estado de salud de la API.
///
/// Capa `presentation`: consume casos de uso y expone estado observable.
/// No conoce HTTP ni JSON.
class HealthController extends ChangeNotifier {
  HealthController(this._getHealthStatus);

  final GetHealthStatus _getHealthStatus;

  LoadState state = LoadState.initial;
  HealthStatus? status;
  String? errorMessage;
  bool _active = true;

  Future<void> load() async {
    state = LoadState.loading;
    errorMessage = null;
    _emit();

    try {
      status = await _getHealthStatus();
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

  void _emit() {
    if (_active) notifyListeners();
  }

  @override
  void dispose() {
    _active = false;
    super.dispose();
  }
}
