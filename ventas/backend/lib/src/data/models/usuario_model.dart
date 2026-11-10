import '../../domain/entities/usuario.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de `usuarios` (con su `Roles` unido) a la
/// entidad [Usuario].
///
/// El campo `contrasena` solo se lee cuando la consulta lo pide
/// explícitamente (nunca aparece en las listas que van a la API).
///
/// `nivel_usuario` es el **alias SQL** de `Roles.nombre` (la columna propia
/// desapareció en la migración `009_roles_permisos`). `permisos` no viene en
/// la fila: lo hidrata el repositorio con [Usuario.conPermisos].
final class UsuarioModel {
  const UsuarioModel._();

  static Usuario usuario(Map<String, Object?> row) => Usuario(
    id: RowUtils.intValue(row['usuario_id']),
    empleadoId: RowUtils.intOrNull(row['empleado_id']),
    rolId: RowUtils.intValue(row['rol_id']),
    nivelUsuario: RowUtils.text(row['nivel_usuario']),
    nombreUsuario: RowUtils.text(row['nombre_usuario']),
    contrasena: RowUtils.textOrNull(row['contrasena']),
    estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
  );
}
