import '../../database/database.dart';

/// Condición ILIKE insensible a mayúsculas **y acentos** en ambos lados.
///
/// Las preguntas llegan sin tildes («analgésicos» → «analgesicos») y los
/// nombres de la BD con tildes («Analgésicos»): un ILIKE normal no casan.
/// `translate` es de PostgreSQL, sin dependencias.
String ilike(String columna, int parametro) =>
    "translate(lower($columna), 'áéíóúüñç', 'aeiouunc') "
    "ILIKE translate(lower(\$$parametro), 'áéíóúüñç', 'aeiouunc')";

/// Parámetro de una función del catálogo.
///
/// [valores] es el dominio cerrado (si es `null`, el valor es texto libre:
/// el resolvedor lo valida contra la base de datos antes de ejecutar).
final class ParametroFuncion {
  const ParametroFuncion(
    this.nombre, {
    this.valores,
    this.defecto,
    this.obligatorio = false,
    this.esNumero = false,
    this.pregunta,
  });

  final String nombre;

  /// Dominio permitido; `null` = texto libre (producto, categoría…).
  final List<String>? valores;

  /// Valor a usar si la pregunta no lo trae.
  final String? defecto;

  /// Si es obligatorio y la pregunta no lo aporta → `falta_info` con
  /// [pregunta].
  final bool obligatorio;

  /// El valor debe ser un entero (p. ej. `dias`, `limite`).
  final bool esNumero;

  /// Texto que la IA le devuelve al usuario cuando falta este parámetro.
  final String? pregunta;
}

/// Una función del catálogo: pregunta que resuelve + cómo ejecutarla.
///
/// El SQL vive aquí, escrito y probado; la IA nunca redacta consultas: solo
/// elige [nombre] y rellena los [parametros] de dominios cerrados.
final class FuncionConsulta {
  const FuncionConsulta({
    required this.nombre,
    required this.descripcion,
    required this.claves,
    required this.ejecutar,
    this.parametros = const [],
  });

  /// Identificador que la IA debe devolver en su JSON (`producto_stock`…).
  final String nombre;

  /// Una línea para el prompt del clasificador.
  final String descripcion;

  /// Frases gatillo (ya normalizadas: minúsculas y sin acentos) para el
  /// resolvedor por palabras clave; cuanto más larga la frase, más peso.
  final List<String> claves;

  final List<ParametroFuncion> parametros;

  /// Ejecuta la consulta y devuelve el resultado en texto plano para que lo
  /// redacte la IA. Nunca escribe SQL el modelo.
  final Future<String> Function(
    DatabaseConnection db,
    Map<String, String> parametros,
  ) ejecutar;
}

/// El catálogo completo: árbol de capacidades del asistente.
///
/// Añadir una capacidad nueva es añadir una entrada aquí (y su SQL); la IA
/// solo aprende el nombre nuevo porque el prompt del clasificador se genera
/// a partir de esta lista.
final class CatalogoConsultas {
  CatalogoConsultas(this.funciones);

  final List<FuncionConsulta> funciones;

  FuncionConsulta? porNombre(String nombre) {
    for (final funcion in funciones) {
      if (funcion.nombre == nombre) return funcion;
    }
    return null;
  }

  /// Listado para el prompt del clasificador: nombre, qué resuelve y con
  /// qué parámetros (dominio y defecto incluidos).
  String describir() {
    final buffer = StringBuffer();
    for (final funcion in funciones) {
      buffer.writeln('- ${funcion.nombre}: ${funcion.descripcion}');
      if (funcion.parametros.isEmpty) {
        buffer.writeln('  (sin parámetros)');
        continue;
      }
      for (final parametro in funcion.parametros) {
        final dominio = parametro.valores != null
            ? 'valores: ${parametro.valores!.join(', ')}'
            : 'texto libre';
        final defecto = parametro.defecto != null
            ? ', defecto: ${parametro.defecto}'
            : '';
        final obligatorio = parametro.obligatorio ? ', obligatorio' : '';
        buffer.writeln('  - ${parametro.nombre} ($dominio$defecto$obligatorio)');
      }
    }
    return buffer.toString().trimRight();
  }
}
