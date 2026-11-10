import 'package:flutter/material.dart';

import '../../domain/entities/usuario.dart';

/// Datos de la sesión activos que necesita la UI (sidebar, drawer, barras).
///
/// Se exponen con un `InheritedWidget` propio en lugar de un `Provider` para
/// que la UI pueda leerlos **con null-safety**: si la sesión no está
/// registrada (pantallas aisladas en tests), `SesionScope.de(context)` es
/// `null` y los widgets caen en su comportamiento por defecto.
class DatosSesion {
  const DatosSesion({required this.usuario, required this.cerrarSesion});

  /// Cuenta conectada (nombre, nivel e iniciales del avatar).
  final Usuario usuario;

  /// Cierra la sesión: invalida el token en el servidor y limpia el equipo.
  final Future<void> Function() cerrarSesion;
}

/// Árbol de la sesión activa; va justo encima de las pantallas autenticadas.
class SesionScope extends InheritedWidget {
  const SesionScope({super.key, required this.datos, required super.child});

  final DatosSesion datos;

  /// `null` si no hay sesión (o no hay scope, p. ej. en un test de widget).
  static DatosSesion? de(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SesionScope>()?.datos;

  @override
  bool updateShouldNotify(SesionScope anterior) =>
      anterior.datos.usuario.id != datos.usuario.id ||
      anterior.datos.usuario.nombreUsuario != datos.usuario.nombreUsuario;
}
