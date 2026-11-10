/// Normalización de textos para comparar sin importar mayúsculas ni acentos.
///
/// Una sola copia para toda la app: la usan el buscador de tablas, el
/// desplegable buscable, la validación de variantes y la importación de
/// productos desde Excel.
library;

/// Equivalencias acento → letra para comparar sin importar cómo las escriba
/// el usuario ("algodon" encuentra "Algodón").
const Map<String, String> _acentos = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
};

/// Pasa a minúsculas, recorta y quita acentos: es la forma en la que se
/// comparan las búsquedas contra los registros.
///
/// Un solo recorrido por carácter (el mapeo [_acentosPorCodigo] resuelve de
/// golpe): antes eran 22 `replaceAll` consecutivos sobre cada registro.
String normalizarTexto(String texto) {
  final base = texto.toLowerCase().trim();
  final salida = StringBuffer();
  for (final codigo in base.runes) {
    salida.writeCharCode(_acentosPorCodigo[codigo] ?? codigo);
  }
  return salida.toString();
}

/// Equivalencias de [_acentos] por código de punto de código.
final Map<int, int> _acentosPorCodigo = {
  for (final entrada in _acentos.entries)
    entrada.key.runes.first: entrada.value.runes.first,
};
