import 'usuario.dart';

/// Sesión de acceso: token guardado + cuenta que lo usa.
///
/// El backend devuelve el mismo objeto en `POST /api/v1/auth/login` y lo
/// valida en cada petición (`Authorization: Bearer <token>`).
final class Sesion {
  const Sesion({
    required this.token,
    required this.expiraEn,
    required this.usuario,
  });

  factory Sesion.fromJson(Map<String, dynamic> json) {
    final usuario = json['usuario'];
    return Sesion(
      token: json['token']?.toString() ?? '',
      expiraEn: DateTime.tryParse(json['expiraEn']?.toString() ?? '')?.toUtc(),
      usuario: usuario is Map<String, dynamic>
          ? Usuario.fromJson(usuario)
          : null,
    );
  }

  final String token;

  /// Instante (UTC) en el que el servidor deja de aceptar el token.
  final DateTime? expiraEn;

  /// Cuenta dueña de la sesión.
  final Usuario? usuario;

  bool get caducada =>
      expiraEn != null && expiraEn!.isBefore(DateTime.now().toUtc());

  Map<String, Object?> toJson() => {
    'token': token,
    'expiraEn': expiraEn?.toIso8601String(),
    'usuario': usuario?.toJson(),
  };
}
