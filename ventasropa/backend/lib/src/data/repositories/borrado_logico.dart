import '../../domain/rules/estados.dart';
import '../database/database.dart';

/// Borrado lógico (soft delete).
///
/// En esta aplicación **jamás se ejecuta un `DELETE` sobre las tablas**: la
/// operación "eliminar" de la API escribe `estado = 'ELIMINADO'` y ya. La fila
/// conserva su identidad, su historial, sus fechas y sus referencias; los
/// listados la excluyen (ver `whereEstado`), de modo que solo "desaparece" de
/// la interfaz.
///
/// Devuelve:
///
/// * `true` → se ocultó ahora;
/// * `false` → la fila no existe **o** ya estaba oculta (la capa de dominio
///   lo traduce en un `404`, igual que antes con un borrado físico).
///
/// `IS DISTINCT FROM` hace la operación idempotente sin depender del orden y
/// evita pisar un estado que ya fuera `ELIMINADO`.
({String sql, List<Object?> params}) sentenciaOcultar({
  required String tabla,
  required String pk,
  required String enumTipo,
  required int id,
}) => (
  sql:
      'UPDATE $tabla SET estado = \$1::$enumTipo '
      'WHERE $pk = \$2 AND estado IS DISTINCT FROM \$1::$enumTipo '
      'RETURNING $pk',
  params: [estadoEliminado, id],
);

/// Ejecuta [sentenciaOcultar] sobre una conexión (fuera de transacción).
///
/// Dentro de una transacción, usa [sentenciaOcultar] con `session.query(...)`.
Future<bool> ocultarRegistro(
  DatabaseConnection db, {
  required String tabla,
  required String pk,
  required String enumTipo,
  required int id,
}) async {
  final sentencia = sentenciaOcultar(
    tabla: tabla,
    pk: pk,
    enumTipo: enumTipo,
    id: id,
  );
  final rows = await db.query(sentencia.sql, sentencia.params);
  return rows.isNotEmpty;
}
