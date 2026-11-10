import '../../domain/entities/persona.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de `clientes`, `proveedores` y `empleados`
/// a sus entidades de dominio.
final class PersonaModel {
  const PersonaModel._();

  static Cliente cliente(Map<String, Object?> row) => Cliente(
    id: RowUtils.intValue(row['cliente_id']),
    nombre: RowUtils.text(row['nombre_cliente']),
    apellido: RowUtils.textOrNull(row['apellido']),
    direccion: RowUtils.textOrNull(row['direccion']),
    ciudad: RowUtils.textOrNull(row['ciudad']),
    genero: RowUtils.textOrNull(row['genero']),
    ci: RowUtils.textOrNull(row['ci']),
    telefono: RowUtils.textOrNull(row['telefono']),
    estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
  );

  static Proveedor proveedor(Map<String, Object?> row) => Proveedor(
    id: RowUtils.intValue(row['proveedor_id']),
    nombre: RowUtils.text(row['nombre_proveedor']),
    direccion: RowUtils.textOrNull(row['direccion']),
    ciudad: RowUtils.textOrNull(row['ciudad']),
    telefono: RowUtils.textOrNull(row['telefono']),
    estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
  );

  static Empleado empleado(Map<String, Object?> row) => Empleado(
    id: RowUtils.intValue(row['empleado_id']),
    nombre: RowUtils.text(row['nombre_empleado']),
    apellido: RowUtils.textOrNull(row['apellido']),
    direccion: RowUtils.textOrNull(row['direccion']),
    ciudad: RowUtils.textOrNull(row['ciudad']),
    rol: RowUtils.textOrNull(row['rol']),
    permisos: _permisos(row['permisos']),
    edad: RowUtils.intOrNull(row['edad']),
    telefono: RowUtils.textOrNull(row['telefono']),
    estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
  );

  /// Permisos del rol vinculados como `string_agg(modulo.accion, ',')`.
  /// En los `RETURNING` de INSERT/UPDATE no hay join y el campo no existe.
  static List<String> _permisos(Object? valor) {
    final texto = RowUtils.textOrNull(valor);
    if (texto == null || texto.isEmpty) return const [];
    return texto.split(',');
  }
}
