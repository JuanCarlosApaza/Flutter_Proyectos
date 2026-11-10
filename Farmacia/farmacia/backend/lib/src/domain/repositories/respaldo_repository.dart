import '../entities/respaldo.dart';

/// Contrato de los respaldos de la BD.
///
/// El dominio solo pide *qué* se puede hacer (crear, listar, leer); dónde se
/// escribe y con qué herramienta (`pg_dump`) lo decide la implementación.
abstract interface class RespaldoRepository {
  /// Genera un respaldo y devuelve su ficha.
  Future<Respaldo> respaldar();

  /// Los respaldos existentes, del más reciente al más antiguo.
  List<Respaldo> listar();

  /// El más reciente, o `null` si todavía no hay ninguno.
  Respaldo? ultimo();

  /// Bytes de un respaldo (`404` si no existe).
  Future<List<int>> leer(String nombre);
}
