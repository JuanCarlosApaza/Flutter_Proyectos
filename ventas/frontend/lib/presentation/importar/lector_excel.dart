import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../widgets/recurso_form.dart';

/// Una fila de datos leída del Excel, con su **número real de fila** de la
/// hoja (la fila 1 es la de encabezados) para que el usuario la encuentre.
class FilaExcel {
  const FilaExcel({required this.fila, required this.celdas});

  /// Número real de fila en el Excel (1 = encabezados).
  final int fila;

  /// Clave del `CampoFormulario` → texto de la celda (tal cual, sin parsear).
  final Map<String, String> celdas;

  /// Valor recortado de una columna; `''` si la celda venía vacía.
  String valor(String clave) => (celdas[clave] ?? '').trim();

  /// Fila sin ninguna celda con contenido → se ignora sin error.
  bool get vacia => celdas.values.every((v) => v.trim().isEmpty);
}

/// Resultado de leer la hoja: filas ya casadas con sus columnas, o un error
/// global (el fichero no es un .xlsx legible o no trae encabezados).
class LecturaExcel {
  const LecturaExcel({required this.filas, this.error});

  final List<FilaExcel> filas;
  final String? error;

  bool get hayError => error != null;
}

/// Encabezado → identificador comparable: minúsculas, sin acentos, sin
/// espacios ni signos (`Precio de venta (Bs)`, `precio_venta` y
/// `PrecioVenta` → `precio de ventabs`/`precioventa`… según venga).
///
/// Se comparan así el rótulo del formulario y la clave del campo, con lo que
/// el orden de las columnas no importa, se aceptan alias y las columnas
/// sobrantes se ignoran.
String encabezadoComparable(String texto) {
  const mapa = {
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
  final sinAcentos = texto
      .toLowerCase()
      .split('')
      .map((c) => mapa[c] ?? c)
      .join();
  return sinAcentos.replaceAll(RegExp('[^a-z0-9]'), '');
}

/// Lee la hoja `datos` de un .xlsx y devuelve sus filas casadas con [campos]
/// (la misma lista de `ProductosPage`, que es la única fuente de reglas).
///
/// No lanza: cualquier problema de lectura vuelve en [LecturaExcel.error] y
/// las filas vienen vacías.
LecturaExcel leerFilasExcel(
  Uint8List bytes, {
  required List<CampoFormulario> campos,
}) {
  final porEncabezado = <String, String>{};
  for (final campo in campos) {
    // «Precio de venta (Bs) *» → también admite «precioVenta».
    porEncabezado[encabezadoComparable(_sinAsterisco(campo.etiqueta))] =
        campo.clave;
    porEncabezado.putIfAbsent(
      encabezadoComparable(campo.clave),
      () => campo.clave,
    );
  }

  Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } on ArchiveException {
    return const LecturaExcel(
      filas: [],
      error: 'El archivo no es un .xlsx válido.',
    );
  } catch (_) {
    return const LecturaExcel(
      filas: [],
      error: 'El archivo no es un .xlsx válido.',
    );
  }
  // Un zip cualquiera (o bytes basura) decodifica sin reventar: lo que
  // delata un .xlsx es que traiga su `xl/workbook.xml`.
  if (_texto(zip, 'xl/workbook.xml') == null) {
    return const LecturaExcel(
      filas: [],
      error: 'El archivo no es un .xlsx válido.',
    );
  }

  final hoja = _hojaDatos(zip);
  if (hoja == null) {
    return const LecturaExcel(
      filas: [],
      error: 'No encuentro la hoja «datos» dentro del archivo.',
    );
  }
  final compartidas = _cadenasCompartidas(zip);

  final XmlDocument documento;
  try {
    documento = XmlDocument.parse(hoja);
  } on XmlException {
    return const LecturaExcel(
      filas: [],
      error: 'La hoja «datos» no se puede leer.',
    );
  }

  // ── Filas crudas: nº de fila → (columna → texto) ─────────────────────
  final filasCrudas = <int, Map<int, String>>{};
  for (final row in documento.findAllElements('row')) {
    final numero = int.tryParse(row.getAttribute('r') ?? '');
    if (numero == null || numero < 1) continue;
    final celdas = <int, String>{};
    var columna = 0;
    for (final c in row.findAllElements('c')) {
      final ref = c.getAttribute('r');
      columna = ref == null ? columna + 1 : _columnaDe(ref);
      final texto = _textoDeCelda(c, compartidas);
      if (texto.isNotEmpty) celdas[columna] = texto;
    }
    if (celdas.isNotEmpty) filasCrudas[numero] = celdas;
  }

  if (filasCrudas.isEmpty) {
    return const LecturaExcel(filas: [], error: 'La hoja «datos» está vacía.');
  }

  // ── Encabezados: la primera fila que traiga texto ────────────────────
  final primeraFila = filasCrudas.keys.reduce((a, b) => a < b ? a : b);
  final encabezados = filasCrudas[primeraFila]!;
  final columnas = <int, String>{};
  for (final entrada in encabezados.entries) {
    final clave = porEncabezado[encabezadoComparable(entrada.value)];
    if (clave != null) columnas[entrada.key] = clave;
  }
  if (columnas.isEmpty) {
    return const LecturaExcel(
      filas: [],
      error:
          'La fila 1 no tiene ningún encabezado reconocido '
          '(descarga la plantilla para ver los nombres).',
    );
  }

  // ── Filas de datos ───────────────────────────────────────────────────
  final filas = <FilaExcel>[];
  final numeros = filasCrudas.keys.where((n) => n > primeraFila).toList()
    ..sort();
  for (final numero in numeros) {
    final celdas = <String, String>{};
    for (final entrada in filasCrudas[numero]!.entries) {
      final clave = columnas[entrada.key];
      if (clave != null) celdas[clave] = entrada.value;
    }
    final fila = FilaExcel(fila: numero, celdas: celdas);
    if (!fila.vacia) filas.add(fila);
  }

  return LecturaExcel(filas: filas);
}

String _sinAsterisco(String etiqueta) =>
    etiqueta.replaceFirst(RegExp(r'\s*\*\s*$'), '').trim();

/// Hoja `datos` (insensible a mayúsculas); si no existe, la primera del
/// libro — la plantilla la pone primero, así que el resultado es el mismo.
String? _hojaDatos(Archive zip) {
  final workbook = _texto(zip, 'xl/workbook.xml');
  if (workbook == null) return null;
  final rels = _texto(zip, 'xl/_rels/workbook.xml.rels') ?? '';

  XmlDocument doc;
  try {
    doc = XmlDocument.parse(workbook);
  } on XmlException {
    return null;
  }

  final hojas = doc.findAllElements('sheet').toList();
  if (hojas.isEmpty) return null;
  final elegida = hojas.firstWhere(
    (h) => (h.getAttribute('name') ?? '').trim().toLowerCase() == 'datos',
    orElse: () => hojas.first,
  );
  final idRelacion = elegida.attributes
      .firstWhere(
        (a) => a.name.local == 'id',
        orElse: () => elegida.attributes.first,
      )
      .value;

  String destino;
  try {
    final relsDoc = XmlDocument.parse(rels);
    final relacion = relsDoc
        .findAllElements('Relationship')
        .firstWhere(
          (r) => r.getAttribute('Id') == idRelacion,
          orElse: () => relsDoc.findAllElements('Relationship').first,
        );
    destino = relacion.getAttribute('Target') ?? '';
  } on XmlException {
    destino = 'worksheets/sheet1.xml';
  } catch (_) {
    destino = 'worksheets/sheet1.xml';
  }

  if (destino.isEmpty) destino = 'worksheets/sheet1.xml';
  final normalizada = destino.startsWith('/') ? destino.substring(1) : destino;
  final ruta = normalizada.startsWith('xl/') ? normalizada : 'xl/$normalizada';
  return _texto(zip, ruta);
}

/// `xl/sharedStrings.xml` puede no existir (todo el libro con cadenas en
/// línea); devuelve las cadenas por su índice.
List<String> _cadenasCompartidas(Archive zip) {
  final bruto = _texto(zip, 'xl/sharedStrings.xml');
  if (bruto == null) return const [];
  try {
    final doc = XmlDocument.parse(bruto);
    return [
      for (final si in doc.findAllElements('si'))
        si.findAllElements('t').map((t) => t.innerText).join(),
    ];
  } on XmlException {
    return const [];
  }
}

/// Texto de una celda según su tipo (`t`):
/// `s` = índice en sharedStrings, `inlineStr` = texto en línea, `str` =
/// resultado de fórmula, `n`/ausente = número (se devuelve tal cual, con
/// punto decimal, para que el validador acepte coma o punto).
String _textoDeCelda(XmlElement celda, List<String> compartidas) {
  final tipo = celda.getAttribute('t') ?? '';
  switch (tipo) {
    case 's':
      final indice = int.tryParse(celda.getElement('v')?.innerText ?? '');
      if (indice == null || indice < 0 || indice >= compartidas.length) {
        return '';
      }
      return compartidas[indice];
    case 'inlineStr':
      final enLinea = celda.getElement('is');
      if (enLinea == null) return '';
      return enLinea.findAllElements('t').map((t) => t.innerText).join();
    case 'str':
    case 'e':
      return celda.getElement('v')?.innerText ?? '';
    case 'b':
      final v = celda.getElement('v')?.innerText ?? '';
      return v == '1' ? 'VERDADERO' : 'FALSO';
    default:
      return celda.getElement('v')?.innerText ?? '';
  }
}

/// `B12` → 2 (A = 1). El número de fila se ignora.
int _columnaDe(String referencia) {
  var columna = 0;
  for (final caracter in referencia.codeUnits) {
    final letra = caracter & ~0x20; // mayúscula sin comparar caracteres
    if (letra < 65 || letra > 90) break;
    columna = columna * 26 + (letra - 64);
  }
  return columna;
}

String? _texto(Archive zip, String ruta) {
  final fichero = zip.findFile(ruta);
  if (fichero == null) return null;
  final bytes = fichero.readBytes();
  if (bytes == null || bytes.isEmpty) return null;
  return utf8.decode(bytes, allowMalformed: true);
}

/// Serial de Excel (días desde 1899-12-30) → fecha. Lo usa el validador
/// cuando una columna de fecha viene como número (Excel guarda así las
/// fechas).
DateTime fechaDeSerial(double dias) =>
    DateTime(1899, 12, 30).add(Duration(days: dias.floor()));
