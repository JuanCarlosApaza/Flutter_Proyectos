import '../../core/errors/failure.dart';

/// Registro genérico de cualquier recurso de la API.
///
/// La API de la tienda expone 10 recursos con el mismo contrato
/// (`{total, items}` + CRUD), así que en lugar de repetir entidad, modelo,
/// datasource y repositorio por cada uno se usa este contenedor que conserva
/// el JSON tal cual. Cada pantalla decide qué campos muestra y edita.
final class Recurso {
  const Recurso({required this.id, required this.datos});

  factory Recurso.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! num) throw const ParsingFailure();
    return Recurso(id: id.toInt(), datos: Map<String, Object?>.from(json));
  }

  final int id;

  /// Campos del registro tal como los devuelve la API.
  final Map<String, Object?> datos;

  Object? operator [](String clave) => datos[clave];

  /// Valor como texto; `vacio` cuando el campo es `null` o cadena nula.
  String texto(String clave, {String vacio = '—'}) {
    final valor = datos[clave];
    if (valor == null) return vacio;
    final texto = valor.toString();
    return texto.isEmpty ? vacio : texto;
  }

  /// Valor numérico (`null` si no lo es).
  double? numero(String clave) {
    final valor = datos[clave];
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '');
  }
}

/// Respuesta de un listado: `{"total": n, "items": [...]}`.
final class ListadoRecurso {
  const ListadoRecurso({required this.total, required this.items});

  final int total;
  final List<Recurso> items;
}
