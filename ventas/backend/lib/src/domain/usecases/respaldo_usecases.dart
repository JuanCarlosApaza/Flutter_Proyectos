import '../entities/respaldo.dart';
import '../repositories/respaldo_repository.dart';

/// Casos de uso de los respaldos de la base de datos.
///
/// Son una pasarela fina al repositorio (la única lógica vive en la
/// implementación: nombre del fichero, retención y ejecución de `pg_dump`);
/// aquí queda el sitio donde más adelante encajarían reglas de negocio
/// (p. ej. «no respaldar si la BD está caída»).
final class Respaldos {
  const Respaldos({required this.repository});

  final RespaldoRepository repository;

  /// Genera un respaldo ahora (el botón «Respaldar ahora»).
  Future<Respaldo> respaldar() => repository.respaldar();

  /// Listado para la vista de Ajustes, del más reciente al más antiguo.
  List<Respaldo> listar() => repository.listar();

  /// El más reciente, para calcular el próximo respaldo automático.
  Respaldo? ultimo() => repository.ultimo();

  /// Bytes del respaldo [nombre] para descargarlo.
  Future<List<int>> leer(String nombre) => repository.leer(nombre);
}
