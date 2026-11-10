import '../../core/errors/failure.dart';
import '../../core/network/api_client.dart';

/// Fuente de datos remota de autenticación (`/api/v1/auth`).
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._client);

  final ApiClient _client;

  static const _prefijo = '/api/v1/auth';

  /// `POST /auth/login` → `{token, expiraEn, usuario}`.
  ///
  /// Lanza [ServerFailure] con `401` si las credenciales no valen.
  Future<Map<String, dynamic>> login({
    required String nombreUsuario,
    required String contrasena,
    required bool recuerdame,
  }) async {
    final body = await _client.post(
      '$_prefijo/login',
      body: {
        'nombreUsuario': nombreUsuario,
        'contrasena': contrasena,
        'recuerdame': recuerdame,
      },
    );
    if (body is! Map<String, dynamic>) throw const ParsingFailure();
    return body;
  }

  /// `POST /auth/logout` → invalida el token en el servidor.
  Future<void> logout() async {
    await _client.post('$_prefijo/logout');
  }

  /// `GET /auth/me` → `{usuario, expiraEn}` de la sesión vigente.
  Future<Map<String, dynamic>> me() async {
    final body = await _client.get('$_prefijo/me');
    if (body is! Map<String, dynamic>) throw const ParsingFailure();
    return body;
  }
}
