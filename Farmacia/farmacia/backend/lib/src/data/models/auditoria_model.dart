import 'dart:convert';

import '../../domain/entities/auditoria.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de `auditoria` a la entidad [AuditoriaEvento].
final class AuditoriaModel {
  const AuditoriaModel._();

  static AuditoriaEvento evento(Map<String, Object?> row) => AuditoriaEvento(
    id: RowUtils.intValue(row['id']),
    fecha: RowUtils.dateTime(row['fecha']),
    usuarioId: RowUtils.intOrNull(row['usuario_id']),
    nombreUsuario: RowUtils.textOrNull(row['nombre_usuario']),
    rol: RowUtils.textOrNull(row['rol']),
    accion: RowUtils.text(row['accion'], fallback: 'DESCONOCIDA'),
    exitoso: RowUtils.boolValue(row['exitoso']),
    codigoError: RowUtils.textOrNull(row['codigo_error']),
    entidad: RowUtils.textOrNull(row['entidad']),
    entidadId: RowUtils.intOrNull(row['entidad_id']),
    resumen: RowUtils.text(row['resumen']),
    detalles: detalles(row['detalles']),
    ip: RowUtils.textOrNull(row['ip']),
  );

  /// `detalles` (JSONB) llega como String o como Map según el driver: se
  /// normaliza a mapa; si no hay detalle, `null` (nada de `{}` vacíos).
  static Map<String, Object?>? detalles(Object? valor) {
    if (valor == null) return null;
    if (valor is Map) return Map<String, Object?>.from(valor);
    if (valor is String && valor.trim().isNotEmpty) {
      try {
        final decodificado = jsonDecode(valor);
        if (decodificado is Map) return Map<String, Object?>.from(decodificado);
      } on FormatException {
        return null;
      }
    }
    return null;
  }
}
