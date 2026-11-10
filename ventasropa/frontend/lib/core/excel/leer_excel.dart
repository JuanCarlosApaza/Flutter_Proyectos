import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';

import '../utils/normalizacion.dart';

/// Lectura de un `.xlsx` de productos: pasa del fichero a **filas de celdas
/// con claves internas** (`nombre`, `precioVenta`...), sin validar nada de
/// negocio (eso lo hace `importar_productos.dart`).
///
/// Los encabezados se comparan **normalizados** (minúsculas, sin acentos ni
/// símbolos): «Precio de compra (Bs)», «precioCompra» o «PRECIO DE COMPRA»
/// son la misma columna, el orden no importa y las columnas de más se
/// ignoran (así se pueden dejar notas al lado de los datos).

/// Alias de encabezado → clave interna (la clave del mapa ya está
/// normalizada con [normalizarTexto] sin espacios ni símbolos).
const Map<String, String> _aliasEncabezados = {
  'nombre': 'nombre',
  'categoria': 'categoria',
  'marca': 'marca',
  'proveedor': 'proveedor',
  'preciodecompra': 'precioCompra',
  'preciodecomprabs': 'precioCompra',
  'preciocompra': 'precioCompra',
  'preciodeventa': 'precioVenta',
  'preciodeventabs': 'precioVenta',
  'precioventa': 'precioVenta',
  'variantes': 'variantes',
  'variantestallacolorstock': 'variantes',
  'stock': 'stock',
  'stockinicial': 'stock',
  'codigo': 'codigo',
  'estado': 'estado',
};

/// Claves que **deben** existir entre los encabezados para que el archivo
/// sirva. `variantes`, `stock`, `codigo` y `estado` no: su obligatoriedad
/// se decide fila a fila (las variantes y el stock son «uno de los dos»).
const List<String> columnasObligatoriasExcel = [
  'nombre',
  'categoria',
  'proveedor',
  'precioCompra',
  'precioVenta',
];

/// Nombre bonito de cada clave para los mensajes de columna faltante.
const Map<String, String> _etiquetasColumnas = {
  'nombre': 'Nombre',
  'categoria': 'Categoría',
  'proveedor': 'Proveedor',
  'precioCompra': 'Precio de compra (Bs)',
  'precioVenta': 'Precio de venta (Bs)',
};

/// Una fila de datos del fichero: su número real en la hoja (la cabecera
/// es la 1) y sus celdas por clave interna.
final class CeldaFila {
  const CeldaFila({required this.fila, required this.celdas});

  /// Número de fila en Excel (1-based, incluida la cabecera): es el que
  /// se enseña en los mensajes para que coincida con lo que ve el usuario.
  final int fila;

  final Map<String, String> celdas;
}

/// Resultado de leer el fichero: o filas, o el motivo por el que no sirve.
final class FilasExcel {
  const FilasExcel.filas(this.filas) : fallo = null;
  const FilasExcel.error(String esteFallo)
    : filas = const [],
      fallo = esteFallo;

  /// Filas de datos (sin la cabecera, ya interpretada).
  final List<CeldaFila> filas;

  /// Mensaje si el archivo no se puede usar; `null` cuando hubo [filas].
  final String? fallo;
}

/// Lee [bytes] (`.xlsx`) y devuelve sus filas de datos.
///
/// La primera fila con texto de la hoja son los encabezados; las filas
/// totalmente vacías se ignoran. Si faltan columnas obligatorias o no hay
/// datos, se devuelve un `FilasExcel.error` con el motivo (nunca lanza).
FilasExcel leerExcel(Uint8List bytes) {
  try {
    final libro = Excel.decodeBytes(bytes);

    final hoja = _hojaProductos(libro);
    if (hoja == null) {
      return const FilasExcel.error('El archivo no tiene ninguna hoja.');
    }
    final filasHoja = hoja.rows;

    // ── Encabezados: la primera fila con algún texto ───────────────────
    int? indiceCabecera;
    List<Data?> cabecera = const [];
    for (var i = 0; i < filasHoja.length; i++) {
      final candidata = filasHoja[i];
      final conTexto = candidata.any(
        (celda) => (_textoCelda(celda) ?? '').trim().isNotEmpty,
      );
      if (conTexto) {
        indiceCabecera = i;
        cabecera = candidata;
        break;
      }
    }
    if (indiceCabecera == null) {
      return const FilasExcel.error(
        'El archivo no tiene ninguna fila con datos.',
      );
    }

    // ── Columna (índice) → clave interna ───────────────────────────────
    final claves = <int, String>{};
    for (var c = 0; c < cabecera.length; c++) {
      final texto = _textoCelda(cabecera[c]);
      if (texto == null || texto.trim().isEmpty) continue;
      final alias = _aliasEncabezados[_claveEncabezado(texto)];
      // Si repiten dos columnas la misma clave, gana la primera.
      if (alias == null || claves.containsValue(alias)) continue;
      claves[c] = alias;
    }

    final faltantes = [
      for (final requerida in columnasObligatoriasExcel)
        if (!claves.containsValue(requerida)) _etiquetasColumnas[requerida]!,
    ];
    if (faltantes.isNotEmpty) {
      return FilasExcel.error(
        'Faltan columnas obligatorias: ${faltantes.join(', ')}.',
      );
    }

    // ── Filas de datos ─────────────────────────────────────────────────
    final filas = <CeldaFila>[];
    for (var i = indiceCabecera + 1; i < filasHoja.length; i++) {
      final cruda = filasHoja[i];
      final celdas = <String, String>{};
      var alguna = false;
      claves.forEach((columna, clave) {
        final texto = columna < cruda.length
            ? (_textoCelda(cruda[columna]) ?? '')
            : '';
        final limpio = texto.trim();
        celdas[clave] = limpio;
        if (limpio.isNotEmpty) alguna = true;
      });
      if (alguna) filas.add(CeldaFila(fila: i + 1, celdas: celdas));
    }

    if (filas.isEmpty) {
      return const FilasExcel.error(
        'El archivo no tiene ninguna fila de datos.',
      );
    }
    return FilasExcel.filas(filas);
  } catch (_) {
    return const FilasExcel.error(
      'No se pudo leer el archivo: ¿es un .xlsx válido?',
    );
  }
}

/// Hoja con los productos: la que se llame «productos» (sin importar
/// mayúsculas), o la primera del libro si ninguna tiene ese nombre — así
/// la hoja «Ayuda» de la plantilla no se cuela.
Sheet? _hojaProductos(Excel libro) {
  Sheet? primera;
  for (final entrada in libro.tables.entries) {
    if (normalizarTexto(entrada.key) == 'productos') return entrada.value;
    primera ??= entrada.value;
  }
  return primera;
}

/// `«Precio de compra (Bs)»` → `preciodecomprabs`: minúsculas, sin acentos
/// y sin espacios ni símbolos, para poder comparar con [_aliasEncabezados].
String _claveEncabezado(String texto) =>
    normalizarTexto(texto).replaceAll(RegExp('[^a-z0-9]'), '');

/// Texto de una celda: las de tipo texto y las numéricas (`59.9`, que es
/// como Excel guarda los precios) llegan a la validación como string.
String? _textoCelda(Data? celda) {
  final valor = celda?.value;
  if (valor == null) return null;
  if (valor is TextCellValue) return valor.value.text;
  return valor.toString();
}
