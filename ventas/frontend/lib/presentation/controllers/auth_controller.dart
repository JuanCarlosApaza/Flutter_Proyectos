import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/failure.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/usuario.dart';
import '../../domain/repositories/auth_repository.dart' show Credenciales;
import '../../domain/usecases/auth_usecases.dart';

/// Estados del login de la aplicación.
enum AuthEstado {
  /// Aún no se ha intentado restaurar nada (splash de arranque).
  inicial,

  /// Restaurando la sesión guardada al abrir la app.
  cargando,

  /// Sin sesión: toca mostrar la pantalla de login.
  sinSesion,

  /// Sesión válida: hay usuario conectado.
  autenticado,
}

/// Estado global de la sesión (el equivalente a un Context global en React o
/// a un `Supabase.auth` compartido en PHP): un único `ChangeNotifier` en la
/// raíz del árbol del que dependen el login, el sidebar y el resto de UI.
///
/// * `restaurar()` se llama al arrancar: lee lo guardado en el equipo y lo
///   valida con el servidor (la sesión persiste al cerrar y abrir la app).
/// * `iniciarSesion()` guarda token + usuario + contraseña si el check
///   "Recordarme" está activado.
/// * `cerrarSesion()` invalida el token **en el servidor** y limpia el
///   dispositivo (web y exe se comportan igual).
class AuthController extends ChangeNotifier {
  AuthController({
    required Autenticacion autenticacion,
    required ApiClient apiClient,
  }) : _auth = autenticacion,
       _api = apiClient {
    // Si el servidor responde 401 en cualquier petición (token caducado o
    // cerrado desde otro sitio), la app vuelve sola a la pantalla de login.
    _api.onUnauthorized = _sesionRechazada;
    // Suscripción vencida (o fecha del equipo trucada): la app entera pasa
    // a la pantalla de bloqueo, que lleva el campo de la clave maestra.
    _api.onSuscripcionVencida = _suscripcionVencida;
  }

  final Autenticacion _auth;
  final ApiClient _api;

  AuthEstado _estado = AuthEstado.inicial;
  Usuario? _usuario;
  String? _error;
  Credenciales? _credenciales;
  bool _ocupado = false;
  bool _cerrando = false;
  bool _disposed = false;
  bool _suscripcionBloqueada = false;
  String _motivoSuscripcion = '';

  AuthEstado get estado => _estado;
  Usuario? get usuario => _usuario;
  String? get error => _error;

  /// `true` mientras la suscripción esté vencida o el guardián de fecha
  /// detecte un reloj retrocedido: la UI muestra la pantalla de bloqueo.
  bool get suscripcionVencida => _suscripcionBloqueada;

  /// Mensaje del backend para la pantalla de bloqueo.
  String get motivoSuscripcion => _motivoSuscripcion;

  /// `true` mientras hay una operación de login/logout en curso.
  bool get ocupado => _ocupado;

  /// Nombre conectado o vacío.
  String get nombreUsuario => _usuario?.nombreUsuario ?? '';

  /// Nivel de acceso conectado (`ADMIN`, `CAJERO`...).
  String get nivelUsuario => _usuario?.nivelUsuario ?? '';

  /// Usuario guardado por el check "Recordarme" (autocompletado).
  String get usuarioGuardado => _credenciales?.usuario ?? '';

  /// Contraseña guardada por el check "Recordarme" (autocompletado).
  String get contrasenaGuardada => _credenciales?.contrasena ?? '';

  /// ¿Hay credenciales guardadas en este equipo?
  bool get recordarCredenciales => _credenciales != null;

  /// Restaura la sesión y las credenciales persistidas. Se ejecuta una vez,
  /// al arrancar la app: pasa de [AuthEstado.inicial] a sesión o a login.
  Future<void> restaurar() async {
    if (_ocupado || _estado != AuthEstado.inicial) return;
    _ocupado = true;
    _estado = AuthEstado.cargando;
    _error = null;
    _notificar();

    try {
      _credenciales = await _auth.credenciales();
      final sesion = await _auth.restaurar();
      final usuario = sesion?.usuario;
      if (usuario != null) {
        _usuario = usuario;
        _estado = AuthEstado.autenticado;
      } else {
        _usuario = null;
        _estado = AuthEstado.sinSesion;
      }
    } on Failure catch (failure) {
      _usuario = null;
      _estado = AuthEstado.sinSesion;
      _error = failure.message;
    } on Exception {
      _usuario = null;
      _estado = AuthEstado.sinSesion;
    } finally {
      _ocupado = false;
      _notificar();
    }
  }

  /// Inicia sesión. Devuelve `true` si todo fue bien; si no, deja el motivo
  /// en [error] y la UI sigue en login.
  Future<bool> iniciarSesion({
    required String usuario,
    required String contrasena,
    required bool recuerdame,
  }) async {
    if (_ocupado) return false;
    _ocupado = true;
    _error = null;
    _notificar();

    try {
      final sesion = await _auth.iniciar(
        usuario: usuario,
        contrasena: contrasena,
        recuerdame: recuerdame,
      );
      final cuenta = sesion.usuario;
      if (cuenta == null) throw const ParsingFailure();

      _usuario = cuenta;
      _credenciales = recuerdame
          ? (usuario: usuario.trim(), contrasena: contrasena)
          : null;
      _estado = AuthEstado.autenticado;
      return true;
    } on Failure catch (failure) {
      _estado = AuthEstado.sinSesion;
      _error = failure.message;
      return false;
    } on Exception {
      _estado = AuthEstado.sinSesion;
      _error = 'No se pudo iniciar sesión. Inténtalo de nuevo.';
      return false;
    } finally {
      _ocupado = false;
      _notificar();
    }
  }

  /// Cierra la sesión (botón "Cerrar sesión"): la invalida en el servidor y
  /// borra token, usuario y contraseña de este equipo.
  Future<void> cerrarSesion() =>
      _cerrar(invalidarEnServidor: true, olvidarCredenciales: true);

  /// Activa (o reactiva) la suscripción con la clave maestra. Devuelve
  /// `true` si la aceptó: el bloqueo se levanta solo al confirmarlo el
  /// servidor. La clave y la duración viajan a `PUT /ajustes/suscripcion`,
  /// que es la única ruta que responde con la suscripción bloqueada.
  Future<bool> activarSuscripcion({
    required String clave,
    required String duracion,
  }) async {
    try {
      await _api.put(
        '/api/v1/ajustes/suscripcion',
        body: {'clave': clave, 'duracion': duracion},
      );
      _suscripcionBloqueada = false;
      _motivoSuscripcion = '';
      _error = null;
      _notificar();
      return true;
    } on Failure catch (failure) {
      _error = failure.message;
      _notificar();
      return false;
    } on Exception {
      _error = 'No se pudo activar la suscripción. Inténtalo de nuevo.';
      _notificar();
      return false;
    }
  }

  /// El servidor rechazó una petición por suscripción (403): se levanta el
  /// bloqueo en pantalla con el motivo que mandó la API.
  void _suscripcionVencida(String motivo) {
    if (_disposed) return;
    _suscripcionBloqueada = true;
    _motivoSuscripcion = motivo;
    _notificar();
  }

  /// El servidor rechazó el token: se olvida la sesión pero se conservan
  /// usuario y contraseña para poder volver a entrar sin reescribirlos.
  void _sesionRechazada() {
    if (_cerrando || _estado != AuthEstado.autenticado) return;
    unawaited(_cerrar(invalidarEnServidor: false, olvidarCredenciales: false));
  }

  Future<void> _cerrar({
    required bool invalidarEnServidor,
    required bool olvidarCredenciales,
  }) async {
    if (_cerrando) return;
    _cerrando = true;
    try {
      await _auth.cerrar(
        invalidarEnServidor: invalidarEnServidor,
        olvidarCredenciales: olvidarCredenciales,
      );
    } on Failure {
      // El servidor no respondió: de todos modos se cierra en local.
    } finally {
      _usuario = null;
      if (olvidarCredenciales) _credenciales = null;
      _estado = AuthEstado.sinSesion;
      _error = null;
      _cerrando = false;
      _notificar();
    }
  }

  void _notificar() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _api.onUnauthorized = null;
    _api.onSuscripcionVencida = null;
    super.dispose();
  }
}
