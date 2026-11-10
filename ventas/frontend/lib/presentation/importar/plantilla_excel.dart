import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../widgets/recurso_form.dart';

/// Plantilla `.xlsx` para importar productos: hoja `datos` con los
/// encabezados del formulario + 2 filas de ejemplo, y hoja `Ayuda` con las
/// reglas. Se genera aquí (sin servidor): el .xlsx es un zip con XML dentro.
///
/// Los encabezados salen de las MISMAS etiquetas de [campos], así que si el
/// formulario cambia una columna, la plantilla cambia con él.
Uint8List plantillaProductos({required List<CampoFormulario> campos}) {
  final columnas = [
    for (final campo in campos)
      if (campo.tipo != TipoCampo.imagen) campo,
  ];

  // Dos filas de ejemplo sobre el catálogo de prueba (una con colores).
  const ejemplos = <Map<String, Object?>>[
    {
      'nombre': 'Gaseosa Cola 2 L',
      'codigo': 'BEB-002',
      'descripcion': 'Ejemplo: bórralas antes de importar',
      'precioCompra': 8.0,
      'precioVenta': 12.0,
      'stock': 60,
      'unidad': 'LT',
      'estado': 'DISPONIBLE',
      'categoriaId': 'Bebidas',
      'presentacionId': 'Botella',
      'marcaId': 'Andina',
      'stockMinimo': 6,
    },
    {
      'nombre': 'Papas Fritas 150 g',
      'precioCompra': 5.0,
      'precioVenta': 8.5,
      'precioRebaja': 2.0,
      'stock': 90,
      'unidad': 'UN',
      'estado': 'DISPONIBLE',
      'categoriaId': 'Snacks',
      'presentacionId': 'Paquete',
      'marcaId': 'Andina',
      'variantes': 'Rojo|2;Azul|5',
    },
  ];

  final filasDatos = <String>[
    _fila(1, [
      for (var i = 0; i < columnas.length; i++)
        _celdaTexto(1, i, _sinAsterisco(columnas[i].etiqueta)),
    ]),
    for (var i = 0; i < ejemplos.length; i++)
      _fila(i + 2, [
        for (var j = 0; j < columnas.length; j++)
          _celdaDe(j, i + 2, columnas[j], ejemplos[i][columnas[j].clave]),
      ]),
  ];

  final filasAyuda = <String>[
    _fila(1, [_celdaTexto(1, 0, 'Cómo importar productos')]),
    for (var i = 0; i < _ayuda.length; i++)
      _fila(i + 2, [_celdaTexto(i + 2, 0, _ayuda[i])]),
  ];

  final zip = Archive()
    ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes))
    ..addFile(ArchiveFile.string('_rels/.rels', _rels))
    ..addFile(ArchiveFile.string('xl/workbook.xml', _workbook))
    ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', _workbookRels))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', _hoja(filasDatos)))
    ..addFile(
      ArchiveFile.string('xl/worksheets/sheet2.xml', _hoja(filasAyuda)),
    );
  return ZipEncoder().encodeBytes(zip);
}

/// Reglas que se escriben en la hoja `Ayuda`.
const List<String> _ayuda = [
  'Hoja «datos», fila 1 = encabezados. El orden no importa y las columnas '
      'que sobren se ignoran.',
  'Una fila = un producto. Las filas completamente vacías se ignoran.',
  'Campos obligatorios: Nombre, Precio de compra, Precio de venta, Stock, '
      'Unidad de venta, Estado, Categoría, Presentación y Marca.',
  'Números: aceptan coma o punto decimal (59,90 = 59.90).',
  'Fechas: dd/mm/aaaa o aaaa-mm-dd; no puede ser anterior a hoy.',
  'Categoría, Presentación, Marca y Proveedor van por NOMBRE: si no existe, '
      'se crea al importar (igual que el botón + del formulario).',
  'Unidad de venta va por código o nombre del catálogo (KG, LT, UN...): si '
      'no existe, la fila da error (el formulario no crea unidades).',
  'Colores (variaciones opcionales): Color|cantidad y ; entre filas, '
      'p. ej. Rojo|2;Azul|5. Con colores, la celda Stock se ignora y manda '
      'la suma.',
  'Ganancia %: solo se usa si el Precio de venta viene vacío (lo calcula '
      'sobre el precio de compra).',
  'Duplicados: un producto con el mismo Código —o el mismo Nombre, '
      'Categoría y Presentación— se omite con aviso: puedes re-subir el '
      'archivo completo sin duplicar nada.',
  'Máximo 1000 filas por archivo.',
];

// ── Piezas fijas del .xlsx ──────────────────────────────────────────────

const String _contentTypes =
    '<?xml version="1.0" encoding="UTF-8" '
    'standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
    'content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-'
    'package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.'
    'openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/'
    'vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/'
    'vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '</Types>';

const String _rels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/officeDocument" '
    'Target="xl/workbook.xml"/>'
    '</Relationships>';

const String _workbook =
    '<?xml version="1.0" encoding="UTF-8" '
    'standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/'
    'main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/'
    'relationships">'
    '<sheets>'
    '<sheet name="datos" sheetId="1" r:id="rId1"/>'
    '<sheet name="Ayuda" sheetId="2" r:id="rId2"/>'
    '</sheets>'
    '</workbook>';

const String _workbookRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/worksheet" '
    'Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/worksheet" '
    'Target="worksheets/sheet2.xml"/>'
    '</Relationships>';

String _hoja(List<String> filas) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/'
    'main">'
    '<sheetData>${filas.join()}</sheetData>'
    '</worksheet>';

String _fila(int numero, List<String> celdas) =>
    '<row r="$numero">${celdas.join()}</row>';

/// Celda de texto (cadenas en línea: no hace falta sharedStrings).
String _celdaTexto(int fila, int columna, String texto) =>
    '<c r="${_ref(columna, fila)}" t="inlineStr"><is><t xml:space="preserve">'
    '${_escapar(texto)}</t></is></c>';

/// Celda numérica (sin `.0` sobrante: Excel escribe `12`, no `12.0`).
String _celdaNumero(int fila, int columna, double valor) =>
    '<c r="${_ref(columna, fila)}"><v>${_numeroXml(valor)}</v></c>';

String _numeroXml(double valor) =>
    valor == valor.roundToDouble() ? valor.toInt().toString() : '$valor';

/// Celda según el valor de ejemplo y el tipo del campo (número → numérico).
String _celdaDe(int columna, int fila, CampoFormulario campo, Object? valor) {
  if (valor == null) return '';
  if (valor is num &&
      (campo.tipo == TipoCampo.decimal || campo.tipo == TipoCampo.numero)) {
    return _celdaNumero(fila, columna, valor.toDouble());
  }
  return _celdaTexto(fila, columna, '$valor');
}

/// `0,1` → `A1` (columnas con letra, como en Excel).
String _ref(int columna, int fila) {
  var n = columna + 1;
  var letras = '';
  while (n > 0) {
    final resto = (n - 1) % 26;
    letras = String.fromCharCode(65 + resto) + letras;
    n = (n - 1) ~/ 26;
  }
  return '$letras$fila';
}

String _escapar(String texto) => texto
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _sinAsterisco(String etiqueta) =>
    etiqueta.replaceFirst(RegExp(r'\s*\*\s*$'), '').trim();
