import 'dart:io';

import '../../core/errors/app_exception.dart';
import '../entities/auditoria.dart';
import '../repositories/auditoria_repository.dart';

/// Casos de uso de la auditoría de cambios.
///
/// * [registrar] **nunca** rompe la operación de negocio: si la BD falla,
///   se avisa por `stderr` y la petición sigue su curso.
/// * Las fechas llegan como texto (`yyyy-MM-dd`) desde la API y se validan
///   aquí (`400 fecha_invalida` si no son parseables).
/// * [limpiar]/[limpiarTodo] devuelven el nº de eventos borrados.
final class Auditorias {
  const Auditorias({required this.repository});

  final AuditoriaRepository repository;

  /// Inserta el evento sin propagar errores (la auditoría no puede tumbar la API).
  Future<void> registrar(AuditoriaEvento evento) async {
    try {
      await repository.registrar(evento);
    } catch (error) {
      stderr.writeln('Aviso: no se pudo registrar la auditoría: $error');
    }
  }

  Future<List<AuditoriaEvento>> listar({
    int limit = 50,
    int offset = 0,
    String? usuario,
    String? desde,
    String? hasta,
    String? entidad,
    String? accion,
    String? q,
  }) => repository.listar(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    usuario: usuario,
    desde: _fecha(desde),
    hasta: _fecha(hasta),
    entidad: entidad,
    accion: accion,
    q: q,
  );

  /// Total de eventos con **los mismos filtros** que [listar] (COUNT real):
  /// mismas fechas parseadas y mismo `q`.
  Future<int> contar({
    String? usuario,
    String? desde,
    String? hasta,
    String? entidad,
    String? accion,
    String? q,
  }) => repository.count(
    usuario: usuario,
    desde: _fecha(desde),
    hasta: _fecha(hasta),
    entidad: entidad,
    accion: accion,
    q: q,
  );

  /// Borra los eventos anteriores a `antesDe` (`yyyy-MM-dd`) y devuelve
  /// cuántos se borraron.
  Future<int> limpiar(String antesDe) =>
      repository.eliminarAntesDe(_fecha(antesDe, obligatoria: true)!);

  /// Vacía la tabla y devuelve cuántos eventos se borraron.
  Future<int> limpiarTodo() => repository.eliminarTodo();

  /// `yyyy-MM-dd` → `DateTime` (local); vacío → `null`; inválido → `400`.
  DateTime? _fecha(String? texto, {bool obligatoria = false}) {
    final limpio = texto?.trim() ?? '';
    if (limpio.isEmpty) {
      if (obligatoria) {
        throw const BadRequestException(
          'Indica la fecha límite (yyyy-MM-dd).',
          code: 'fecha_invalida',
        );
      }
      return null;
    }
    final fecha = DateTime.tryParse(limpio);
    if (fecha == null) {
      throw BadRequestException(
        'La fecha "$limpio" no es válida (formato yyyy-MM-dd).',
        code: 'fecha_invalida',
      );
    }
    return DateTime(fecha.year, fecha.month, fecha.day);
  }
}
