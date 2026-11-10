import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/sesion.dart';
import '../../domain/repositories/auth_repository.dart';

/// Persistencia local de la sesión y de las credenciales "recordadas".
///
/// La respalda `shared_preferences`, que guarda en `localStorage` del
/// navegador (web) y en el archivo de preferencias del sistema (exe
/// Windows/Linux, macOS, Android e iOS): la sesión sobrevive a cerrar la
/// pestaña o la aplicación en todas las plataformas.
///
/// Claves:
/// * `auth.sesion`           → `{token, expiraEn, usuario}` en JSON
/// * `auth.credencial.*`     → usuario y contraseña del check "Recordarme"
class SesionLocalDataSource {
  static const _kSesion = 'auth.sesion';
  static const _kUsuario = 'auth.credencial.usuario';
  static const _kContrasena = 'auth.credencial.contrasena';

  Future<SharedPreferences> get _preferencias =>
      SharedPreferences.getInstance();

  /// Sesión guardada; `null` si no existe o está corrupta.
  Future<Sesion?> sesion() async {
    final prefs = await _preferencias;
    final crudo = prefs.getString(_kSesion);
    if (crudo == null || crudo.isEmpty) return null;

    try {
      final json = jsonDecode(crudo);
      if (json is! Map<String, dynamic>) return null;
      final sesion = Sesion.fromJson(json);
      return sesion.token.isEmpty ? null : sesion;
    } on FormatException {
      await limpiarTodo();
      return null;
    }
  }

  Future<void> guardarSesion(Sesion sesion) async {
    final prefs = await _preferencias;
    await prefs.setString(_kSesion, jsonEncode(sesion.toJson()));
  }

  Future<void> guardarCredenciales(Credenciales credenciales) async {
    final prefs = await _preferencias;
    await prefs.setString(_kUsuario, credenciales.usuario);
    await prefs.setString(_kContrasena, credenciales.contrasena);
  }

  Future<Credenciales?> credenciales() async {
    final prefs = await _preferencias;
    final usuario = prefs.getString(_kUsuario);
    final contrasena = prefs.getString(_kContrasena);
    if (usuario == null || usuario.isEmpty) return null;
    if (contrasena == null || contrasena.isEmpty) return null;
    return (usuario: usuario, contrasena: contrasena);
  }

  /// Borra la sesión (deja las credenciales: sigue el autocompletado).
  Future<void> limpiarSesion() async {
    final prefs = await _preferencias;
    await prefs.remove(_kSesion);
  }

  /// Borra sesión **y** credenciales (logout completo).
  Future<void> limpiarTodo() async {
    final prefs = await _preferencias;
    await prefs.remove(_kSesion);
    await prefs.remove(_kUsuario);
    await prefs.remove(_kContrasena);
  }
}
