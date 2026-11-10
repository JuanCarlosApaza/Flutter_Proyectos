/// Exportación CSV de la pantalla «Reportes».
///
/// Formato pensado para **abrirlo en Excel/LibreOffice en español** (y en
/// Bolivia, con el mismo criterio):
///
/// * separador de campos `;` (la coma es el separador decimal);
/// * decimales con `,` y millares con `.` (`1.234,56`), que es como los
///   interpreta «Texto en columnas» de esos programas;
/// * **BOM UTF-8** al principio, para que el Excel de Windows no muestre
///   «ñ» como «Ã±»;
/// * fin de línea `\r\n`.
///
/// Es una función pura: se puede probar sin tocar la red ni los ficheros.
library;

import '../../domain/entities/reporte.dart';

/// Monta el CSV completo: cabecera, resumen, serie por periodo, productos y
/// categorías (los mismos datos que la pantalla y el PDF).
String construirInformeCsv({
  required InformeVentas ventas,
  required InformeProductos detalle,
}) {
  // BOM UTF-8 (U+FEFF): sin él, el Excel de Windows muestra «ñ» como «Ã±».
  final salida = StringBuffer(String.fromCharCode(0xFEFF));

  // --- Cabecera -----------------------------------------------------------
  salida.write(_fila(['Informe de ventas']));
  salida.write(_fila(['Rango', '${ventas.desde} al ${ventas.hasta}']));
  salida.write(_fila(['Agrupación', 'por ${_agrupacion(ventas.agrupacion)}']));
  salida.write('\r\n');

  // --- Resumen ------------------------------------------------------------
  final resumen = ventas.resumen;
  salida.write(_fila(['Resumen']));
  salida.write(_fila(['Total (Bs)', _numero(resumen.total)]));
  salida.write(_fila(['Órdenes', '${resumen.ordenes}']));
  salida.write(_fila(['Unidades', _numero(resumen.unidades)]));
  salida.write(_fila(['Ticket medio (Bs)', _numero(resumen.ticketMedio)]));
  salida.write('\r\n');

  // --- Serie (con los periodos sin ventas en cero) ------------------------
  salida.write(_fila(['Ventas por ${_agrupacion(ventas.agrupacion)}']));
  salida.write(
    _fila(['Periodo', 'Órdenes', 'Unidades', 'Total (Bs)', '% del total']),
  );
  for (final periodo in ventas.serieCompleta) {
    salida.write(
      _fila([
        periodo.etiqueta,
        '${periodo.ordenes}',
        _numero(periodo.unidades),
        _numero(periodo.total),
        _numero(_tantoPorCiento(periodo.total, resumen.total)),
      ]),
    );
  }
  salida.write('\r\n');

  // --- Productos ----------------------------------------------------------
  salida.write(_fila(['Ventas por producto']));
  salida.write(
    _fila([
      'Producto',
      'Categoría',
      'Unidades',
      'Total (Bs)',
      '% del total',
    ]),
  );
  for (final producto in detalle.productos) {
    salida.write(
      _fila([
        producto.nombre,
        producto.categoria ?? '(sin categoría)',
        _numero(producto.unidades),
        _numero(producto.monto),
        _numero(_tantoPorCiento(producto.monto, resumen.total)),
      ]),
    );
  }
  salida.write('\r\n');

  // --- Categorías ---------------------------------------------------------
  salida.write(_fila(['Reparto por categoría']));
  salida.write(_fila(['Categoría', 'Unidades', 'Total (Bs)', '% del total']));
  for (final categoria in detalle.categorias) {
    salida.write(
      _fila([
        categoria.nombre,
        _numero(categoria.unidades),
        _numero(categoria.monto),
        _numero(_tantoPorCiento(categoria.monto, resumen.total)),
      ]),
    );
  }

  return salida.toString();
}

/// `dia` → `día`, `mes` → `mes`, `anio` → `año`.
String _agrupacion(String agrupacion) => switch (agrupacion) {
  'mes' => 'mes',
  'anio' => 'año',
  _ => 'día',
};

/// Porcentaje de [valor] sobre el total del rango (`0` si no hubo ventas).
double _tantoPorCiento(double valor, double total) =>
    total == 0 ? 0 : valor * 100 / total;

/// `1540.5` → `1.540,50` (formato numérico de un texto español).
String _numero(double valor) {
  final partes = valor.toStringAsFixed(2).split('.');
  final entero = partes[0];
  final signo = entero.startsWith('-') ? '-' : '';
  final digitos = entero.replaceFirst('-', '');
  final conMillares = StringBuffer();
  for (var i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) conMillares.write('.');
    conMillares.write(digitos[i]);
  }
  return '$signo$conMillares,${partes[1]}';
}

/// Una línea de campos, con las comillas que exija el formato.
String _fila(List<String> campos) =>
    '${campos.map(_campo).join(';')}\r\n';

/// Rodea de comillas un campo que contenga el separador, comillas o saltos
/// de línea (el «doble comilla doble» es la escapación del CSV).
String _campo(String texto) =>
    (texto.contains(';') ||
        texto.contains('"') ||
        texto.contains('\n') ||
        texto.contains('\r'))
    ? '"${texto.replaceAll('"', '""')}"'
    : texto;
