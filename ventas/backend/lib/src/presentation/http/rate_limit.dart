import '../../core/errors/app_exception.dart';

/// Contador de intentos fallidos de login por **IP + usuario**, con ventana
/// deslizante.
///
/// Se usa en `POST /api/v1/auth/login`: la clave combina cliente e
/// identidad para que un atacante desde una IP no pueda bloquear a otro
/// usuario legítimo de la misma red (NAT/oficina). Estado **en memoria** y
/// por proceso: la API es de una sola instancia, así que no hace falta I/O
/// de BD por cada intento; varias instancias requerirían una tabla
/// compartida.
final class RateLimiter {
  RateLimiter({required this.maxIntentos, required this.ventana});

  /// Intentos fallidos tolerados dentro de [ventana].
  final int maxIntentos;

  /// Duración de la ventana deslizante.
  final Duration ventana;

  final Map<String, _Conteo> _conteos = {};

  /// Lanza `429` si la clave ya agotó sus intentos en la ventana actual.
  void verificar(String clave) {
    final conteo = _conteos[clave];
    if (conteo == null) return;
    if (DateTime.now().difference(conteo.inicio) > ventana) {
      _conteos.remove(clave);
      return;
    }
    if (conteo.intentos >= maxIntentos) {
      throw const TooManyRequestsException(
        'Demasiados intentos de acceso. Vuelve a intentarlo en unos minutos.',
        code: 'demasiados_intentos',
      );
    }
  }

  /// Anota un intento fallido (las contraseñas correctas no cuentan).
  void registrarFallo(String clave) {
    final ahora = DateTime.now();
    final conteo = _conteos[clave];
    if (conteo == null || ahora.difference(conteo.inicio) > ventana) {
      _conteos[clave] = _Conteo(inicio: ahora, intentos: 1);
      return;
    }
    conteo.intentos++;
    _limpiar(ahora);
  }

  /// Un login correcto borra la clave: quien sabe la contraseña no puede
  /// quedar bloqueado por sus propios fallos previos.
  void registrarExito(String clave) => _conteos.remove(clave);

  /// Poda las claves ya caducadas para que el mapa no crezca sin límite.
  void _limpiar(DateTime ahora) {
    if (_conteos.length < 1000) return;
    _conteos.removeWhere(
      (_, conteo) => ahora.difference(conteo.inicio) > ventana,
    );
  }
}

class _Conteo {
  _Conteo({required this.inicio, required this.intentos});
  final DateTime inicio;
  int intentos;
}
