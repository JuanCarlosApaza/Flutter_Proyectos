import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';

import '../storage/guardar_fichero.dart';

/// Encabezados de la plantilla, en el orden en que se rellenan.
///
/// Se reconocen en cualquier orden y escritos de otras formas (ver
/// `leer_excel.dart`), así que quien prefiera reordenar o renombrar las
/// columnas de su propio archivo no pierde nada.
const List<String> encabezadosPlantilla = [
  'Nombre',
  'Categoría',
  'Marca',
  'Proveedor',
  'Precio de compra (Bs)',
  'Precio de venta (Bs)',
  'Variantes (talla|color|stock)',
  'Stock inicial',
  'Código',
  'Estado',
];

/// Tres filas de ejemplo: una con tallas, una sin tallas (medias) y una
/// de calzado con rango. Se borran antes de importar (la hoja «Ayuda» lo
/// recuerda).
final List<List<CellValue?>> _ejemplos = [
  [
    TextCellValue('Pantalón mezclillo'),
    TextCellValue('Ropa'),
    TextCellValue('Denver'),
    TextCellValue('Textil Andina'),
    const DoubleCellValue(59.9),
    const DoubleCellValue(89.9),
    TextCellValue('S|Negro|5;M|Negro|3;L|Rojo|2'),
    null,
    TextCellValue('PANT-001'),
    TextCellValue('DISPONIBLE'),
  ],
  [
    TextCellValue('Medias clásicas'),
    TextCellValue('Medias'),
    null,
    TextCellValue('Textil Andina'),
    const DoubleCellValue(15),
    const DoubleCellValue(25),
    null,
    const IntCellValue(24),
    TextCellValue('MED-001'),
    null,
  ],
  [
    TextCellValue('Zapatilla running'),
    TextCellValue('Zapatos'),
    TextCellValue('Sportix'),
    TextCellValue('Deportes Sur'),
    const DoubleCellValue(150),
    const DoubleCellValue(240),
    TextCellValue('38|Blanco|4;40/41|Negro|6'),
    null,
    TextCellValue('ZAP-001'),
    TextCellValue('AGOTADO'),
  ],
];

/// Instrucciones de la hoja «Ayuda» (una línea por fila).
const List<String> _ayuda = [
  'CÓMO RELLENAR LA PLANTILLA DE PRODUCTOS',
  '',
  '1) La fila 1 son los encabezados: no los borres. El orden da igual, '
      'las columnas de más se ignoran y se aceptan otros nombres parecidos '
      '(«precioVenta», «PRECIO DE VENTA»...).',
  '2) Una fila = un producto con todas sus variantes.',
  '3) Obligatorias: Nombre, Categoría, Proveedor, Precio de compra (Bs) y '
      'Precio de venta (Bs). Las categorías, marcas y proveedores que no '
      'existan se crean solos al importar.',
  '4) Marca opcional: déjala vacía si la prenda no tiene marca.',
  '5) Variantes: combos «talla|color|unidades» separados por «;» → '
      'S|Negro|5;M|Negro|3;39-41|Blanco|4',
  '   · Tallas: S, M, XL, 38, 40.5 · rangos 39-41 o 40/41 · mezcla S/M · '
      '«Única». Las frases («talla 38») no valen.',
  '   · Las tallas y los colores nuevos se crean solos al importar.',
  '6) Producto SIN tallas (medias, gorros...): deja «Variantes» vacía y pon '
      'la cantidad en «Stock inicial». Con variantes, «Stock inicial» se '
      'ignora: el stock lo da cada fila.',
  '7) Precios con coma o punto (59,90 o 59.90), máximo 2 decimales, y el '
      'de venta nunca por debajo del de compra.',
  '8) Estado opcional: DISPONIBLE (por defecto), AGOTADO o DESCONTINUADO. '
      'Código opcional, máximo 60 caracteres.',
  '9) Borra las 3 filas de ejemplo antes de importar. Guarda como .xlsx '
      '(no como .csv).',
  '10) Máximo 1000 productos por archivo. Los nombres repetidos (en el '
      'inventario o en el propio archivo) se saltan con aviso.',
];

/// Genera los bytes del `.xlsx` de plantilla: hoja «productos» con los
/// encabezados en negrita y tres filas de ejemplo, más la hoja «Ayuda»
/// con estas reglas.
Uint8List plantillaExcel() {
  final libro = Excel.createExcel();
  final defecto = libro.getDefaultSheet() ?? libro.sheetOrder.first;
  libro.rename(defecto, 'productos');
  final productos = libro['productos'];

  productos.appendRow([
    for (final encabezado in encabezadosPlantilla) TextCellValue(encabezado),
  ]);
  for (var columna = 0; columna < encabezadosPlantilla.length; columna++) {
    productos
        .cell(CellIndex.indexByColumnRow(columnIndex: columna, rowIndex: 0))
        .cellStyle = CellStyle(
      bold: true,
    );
  }
  const anchos = [26, 14, 14, 18, 20, 20, 36, 14, 14, 16];
  for (var columna = 0; columna < anchos.length; columna++) {
    productos.setColumnWidth(columna, anchos[columna].toDouble());
  }
  for (final fila in _ejemplos) {
    productos.appendRow(fila);
  }

  final ayuda = libro['Ayuda'];
  for (final linea in _ayuda) {
    ayuda.appendRow([TextCellValue(linea)]);
  }
  ayuda.setColumnWidth(0, 110);

  return Uint8List.fromList(libro.save() ?? const []);
}

/// Descarga la plantilla en el equipo de quien la pide (web: descarga del
/// navegador; móvil: hoja de compartir; escritorio: «Guardar como»).
Future<bool> descargarPlantilla() => guardarFichero(
  plantillaExcel(),
  'plantilla_productos.xlsx',
  extensiones: const ['xlsx'],
  etiqueta: 'Plantilla de productos',
  mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
);
