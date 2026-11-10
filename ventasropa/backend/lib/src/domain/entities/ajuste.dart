/// Ajuste global de la aplicación (clave/valor).
///
/// Dominio puro: sin SQL ni HTTP. La tabla guarda **solo** lo que alguien
/// cambió en la vista «Ajustes»; lo que no esté guardado lo decide el
/// cliente con su valor por defecto, así que esta entidad nunca lleva
/// «valores nulos».
final class Ajuste {
  const Ajuste({
    required this.id,
    required this.clave,
    required this.valor,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int id;

  /// Identificador del ajuste (`tipoPagoPorDefecto`, `porPagina`…).
  final String clave;

  /// Último valor elegido (cadena: los ids vienen como texto).
  final String valor;

  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  Map<String, Object?> toJson() => {
    'id': id,
    'clave': clave,
    'valor': valor,
    'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
    'fechaActualizacion': fechaActualizacion.toUtc().toIso8601String(),
  };
}
