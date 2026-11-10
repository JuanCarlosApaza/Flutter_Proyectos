/// Utilidades para construir `.xlsx` **en memoria** de pruebas.
///
/// No termina en `_test.dart`: el runner no lo ejecuta, solo lo importan
/// `importar_excel_test.dart` e `importar_excel_dialog_test.dart`.
library;

import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';
import 'package:ventas/core/excel/plantilla_excel.dart';

/// Índice de cada clave en [encabezadosPlantilla].
const ordenPlantilla = {
  'nombre': 0,
  'categoria': 1,
  'marca': 2,
  'proveedor': 3,
  'precioCompra': 4,
  'precioVenta': 5,
  'variantes': 6,
  'stock': 7,
  'codigo': 8,
  'estado': 9,
};

/// Fila de datos alineada con [encabezadosPlantilla]: `{'nombre': 'Camisa',
/// 'precioVenta': 89.9}` ocupa las columnas que dice la plantilla y las
/// demás quedan vacías.
List<Object?> fila(Map<String, Object?> campos) {
  final resultado = List<Object?>.filled(encabezadosPlantilla.length, null);
  campos.forEach((clave, valor) => resultado[ordenPlantilla[clave]!] = valor);
  return resultado;
}

/// `.xlsx` en memoria con una hoja «productos»: los [cabeceras] (por
/// defecto, los de la plantilla) seguidos de las [filas]. Los números
/// se escriben como celda numérica (como hace Excel al teclear `59,9`).
Uint8List archivoExcel(List<List<Object?>> filas, {List<String>? cabeceras}) {
  final libro = Excel.createExcel();
  final defecto = libro.getDefaultSheet() ?? libro.sheetOrder.first;
  libro.rename(defecto, 'productos');
  final hoja = libro['productos'];

  hoja.appendRow([
    for (final encabezado in cabeceras ?? encabezadosPlantilla)
      TextCellValue(encabezado),
  ]);
  for (final datos in filas) {
    hoja.appendRow([
      for (final celda in datos)
        celda == null
            ? null
            : celda is num
            ? DoubleCellValue(celda.toDouble())
            : TextCellValue('$celda'),
    ]);
  }
  return Uint8List.fromList(libro.save()!);
}
