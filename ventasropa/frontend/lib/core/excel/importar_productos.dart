import '../utils/normalizacion.dart';
import '../validation/reglas.dart';
import 'leer_excel.dart';

/// Cómo quedó cada fila del Excel tras validarla.
///
/// Las reglas son **espejo del formulario de producto** (y por tanto del
/// backend): mismos límites de nombre y precios, `tallaValida` de
/// `core/validation/reglas.dart`, «variantes o stock, uno de los dos» y
/// estados del desplegable. Así un archivo se rechaza aquí, con la fila y
/// el motivo, en lugar de fallar en el envío.
final class FilaImportacion {
  const FilaImportacion({
    required this.fila,
    required this.celdas,
    required this.errores,
    required this.avisos,
    required this.duplicada,
    this.producto,
  });

  /// Número de fila en el Excel (1 = cabecera): el que ve el usuario.
  final int fila;

  /// Celdas originales por clave (`nombre`, `precioCompra`...).
  final Map<String, String> celdas;

  /// Motivos por los que la fila no se puede importar (vacío = fila buena).
  final List<String> errores;

  /// Avisos que no impiden validar pero sí hacen saltar la fila
  /// (nombre repetido en el archivo o ya existente en la BD).
  final List<String> avisos;

  /// `true` si por [avisos] la fila se salta al importar.
  final bool duplicada;

  /// Producto interpretado; `null` si la fila tiene [errores].
  final ProductoExcel? producto;

  /// Lo que se enviaría al backend: fila buena y no repetida.
  bool get importable => errores.isEmpty && !duplicada && producto != null;
}

/// Producto ya interpretado a partir de una fila válida.
final class ProductoExcel {
  const ProductoExcel({
    required this.nombre,
    required this.categoria,
    required this.proveedor,
    required this.precioCompra,
    required this.precioVenta,
    required this.variantes,
    this.stock,
    this.codigo,
    this.marca,
    required this.estado,
  });

  final String nombre;
  final String categoria;
  final String proveedor;
  final double precioCompra;
  final double precioVenta;

  /// Combos `talla|color|stock` de la fila; vacío = producto sin tallas
  /// (medias, gorros...) y entonces manda [stock] (variante «Única»).
  final List<({String talla, String color, double stock})> variantes;

  final double? stock;
  final String? codigo;

  /// Marca opcional de la prenda (`null` = sin marca).
  final String? marca;
  final String estado;
}

/// Valida las [filas] crudas y devuelve el veredicto de cada una.
///
/// [existentes] son los nombres ya presentes en la inventario (normalizados
/// con [normalizarTexto]): esos productos se marcan con un aviso y se
/// saltan, de modo que re-subir el mismo archivo no duplica nada. Dentro
/// del propio archivo también se detectan repetidos: gana el primero.
List<FilaImportacion> validarFilasExcel(
  List<CeldaFila> filas, {
  Set<String> existentes = const {},
}) {
  final resultado = <FilaImportacion>[];
  final vistos = <String>{};

  for (final fila in filas) {
    final c = fila.celdas;
    final errores = <String>[];
    final avisos = <String>[];

    // ── Nombre ─────────────────────────────────────────────────────────
    final nombre = (c['nombre'] ?? '').trim();
    if (nombre.isEmpty) {
      errores.add('Falta el nombre');
    } else if (nombre.length < 2 || nombre.length > 150) {
      errores.add('El nombre debe tener de 2 a 150 caracteres');
    }

    // ── Categoría y proveedor (se crean solos si no existen) ───────────
    final categoria = (c['categoria'] ?? '').trim();
    if (categoria.isEmpty) errores.add('Falta la categoría');
    final proveedor = (c['proveedor'] ?? '').trim();
    if (proveedor.isEmpty) errores.add('Falta el proveedor');

    // ── Marca (opcional; se crea sola si no existía) ───────────────────
    final marca = (c['marca'] ?? '').trim();
    if (marca.isNotEmpty && marca.length < 2) {
      errores.add('La marca debe tener al menos 2 caracteres');
    } else if (marca.length > 100) {
      errores.add('La marca no puede superar 100 caracteres');
    }

    // ── Precios (coma o punto decimal, como en Excel/Bolivia) ──────────
    final (compra, falloCompra) = _numero(
      c['precioCompra'],
      etiqueta: 'El precio de compra',
      decimales: 2,
    );
    if (falloCompra != null) errores.add(falloCompra);
    final (venta, falloVenta) = _numero(
      c['precioVenta'],
      etiqueta: 'El precio de venta',
      decimales: 2,
    );
    if (falloVenta != null) errores.add(falloVenta);
    if (falloCompra == null && compra == null) {
      errores.add('Falta el precio de compra');
    }
    if (falloVenta == null && venta == null) {
      errores.add('Falta el precio de venta');
    }
    if (compra != null && compra < 0.01) {
      errores.add('El precio de compra debe ser mayor que 0');
    }
    if (venta != null && venta < 0.01) {
      errores.add('El precio de venta debe ser mayor que 0');
    }
    if (compra != null && compra > 99999999.99) {
      errores.add('El precio de compra supera el máximo (99.999.999,99 Bs)');
    }
    if (venta != null && venta > 99999999.99) {
      errores.add('El precio de venta supera el máximo (99.999.999,99 Bs)');
    }
    if (compra != null && venta != null) {
      final fallo = ventaNoMenorQueCoste(venta, compra);
      if (fallo != null) errores.add(fallo);
    }

    // ── Variantes o stock inicial: uno de los dos ──────────────────────
    List<({String talla, String color, double stock})>? variantes;
    double? stock;
    final crudoVariantes = (c['variantes'] ?? '').trim();
    if (crudoVariantes.isEmpty) {
      // Sin variantes es el producto «sin tallas»: el stock es obligatorio.
      final (valorStock, falloStock) = _numero(
        c['stock'],
        etiqueta: 'El stock inicial',
        decimales: 3,
      );
      if (falloStock != null) {
        errores.add(falloStock);
      } else if (valorStock == null) {
        errores.add(
          'Falta el stock inicial (o escribe las variantes en su columna)',
        );
      } else if (valorStock < 0) {
        errores.add('El stock inicial no puede ser negativo');
      } else if (valorStock > 999999.999) {
        errores.add('El stock inicial supera el máximo (999.999,999)');
      } else {
        stock = valorStock;
      }
    } else {
      variantes = _variantes(crudoVariantes, errores);
    }

    // ── Estado (vacío = DISPONIBLE) ────────────────────────────────────
    var estado = 'DISPONIBLE';
    final crudoEstado = (c['estado'] ?? '').trim();
    if (crudoEstado.isNotEmpty) {
      final normal = crudoEstado.toUpperCase();
      if (const {'DISPONIBLE', 'AGOTADO', 'DESCONTINUADO'}.contains(normal)) {
        estado = normal;
      } else {
        errores.add(
          'Estado no válido: usa DISPONIBLE, AGOTADO o DESCONTINUADO',
        );
      }
    }

    // ── Código (opcional) ──────────────────────────────────────────────
    final codigo = (c['codigo'] ?? '').trim();
    if (codigo.length > 60) {
      errores.add('El código no puede superar 60 caracteres');
    }

    // ── Repetidos (solo cuando la fila está bien) ──────────────────────
    if (errores.isEmpty && nombre.isNotEmpty) {
      final clave = normalizarTexto(nombre);
      if (existentes.contains(clave)) {
        avisos.add(
          'Ya existe un producto con ese nombre en el inventario: se salta',
        );
      } else if (!vistos.add(clave)) {
        avisos.add('Nombre repetido en el archivo: se salta');
      }
    }

    resultado.add(
      FilaImportacion(
        fila: fila.fila,
        celdas: c,
        errores: errores,
        avisos: avisos,
        duplicada: avisos.isNotEmpty,
        producto: errores.isEmpty
            ? ProductoExcel(
                nombre: nombre,
                categoria: categoria,
                proveedor: proveedor,
                precioCompra: compra!,
                precioVenta: venta!,
                variantes: variantes ?? const [],
                stock: stock,
                codigo: codigo.isEmpty ? null : codigo,
                marca: marca.isEmpty ? null : marca,
                estado: estado,
              )
            : null,
      ),
    );
  }

  return resultado;
}

/// Interpreta la celda «Variantes»: combos `talla|color|stock` separados
/// por `;` (p. ej. `S|Negro|5;M|Negro|3;39-41|Blanco|4`).
///
/// Se usan `|` y `;` —y no `/` ni `-`— porque esas marcas las traen los
/// rangos de calzado (`40/41`, `39-41`). Cada combo se valida con
/// [tallaValida] y una combinación repetida dentro de la fila es error.
List<({String talla, String color, double stock})> _variantes(
  String crudo,
  List<String> errores,
) {
  final lista = <({String talla, String color, double stock})>[];
  final claves = <String>{};

  for (final trozo in crudo.split(';')) {
    final combo = trozo.trim();
    if (combo.isEmpty) continue;

    final partes = combo.split('|').map((p) => p.trim()).toList();
    if (partes.length != 3) {
      errores.add('«$combo» debe escribirse así: talla|color|stock');
      continue;
    }
    final talla = partes[0];
    final color = partes[1];
    var comboOk = true;

    if (talla.isEmpty) {
      errores.add('A «$combo» le falta la talla');
      comboOk = false;
    } else {
      final fallo = tallaValida(talla);
      if (fallo != null) {
        errores.add('Combo «$combo» → $fallo');
        comboOk = false;
      } else if (talla.length > 30) {
        errores.add('La talla «$talla» no puede superar 30 caracteres');
        comboOk = false;
      }
    }
    if (color.isEmpty) {
      errores.add('A «$combo» le falta el color');
      comboOk = false;
    } else if (color.length > 50) {
      errores.add('El color «$color» no puede superar 50 caracteres');
      comboOk = false;
    }

    final (stock, falloStock) = _numero(
      partes[2],
      etiqueta: 'Las unidades de «$combo»',
      decimales: 3,
    );
    if (falloStock != null) {
      errores.add(falloStock);
      comboOk = false;
    } else if (stock == null) {
      errores.add('A «$combo» le falta el stock');
      comboOk = false;
    } else if (stock < 0) {
      errores.add('Las unidades de «$combo» no pueden ser negativas');
      comboOk = false;
    }

    final clave = '${normalizarTexto(talla)}|${normalizarTexto(color)}';
    if (!claves.add(clave)) {
      errores.add('La talla «$talla» con el color «$color» está repetida');
      comboOk = false;
    }

    if (comboOk) lista.add((talla: talla, color: color, stock: stock!));
  }

  if (lista.isEmpty && errores.isEmpty) {
    errores.add('Las variantes no tienen ninguna combinación');
  }
  return lista;
}

/// Número escrito en una celda: acepta el valor numérico de Excel
/// (`59.9`) y también texto con coma decimal (`59,90`), como se escribe
/// en Bolivia. Rechaza todo lo demás, incluido el uso simultáneo de los
/// dos separadores (`1.234,56`).
///
/// Devuelve el valor y, si no es número, el mensaje para [etiqueta]
/// (p. ej. «El precio de compra»). `null` en los dos = celda vacía: quién
/// decide si es obligatoria es quien llama.
(double? valor, String? fallo) _numero(
  String? crudo, {
  required String etiqueta,
  required int decimales,
}) {
  final texto = (crudo ?? '').trim().replaceAll(' ', '');
  if (texto.isEmpty) return (null, null);
  if (!RegExp(r'^-?\d+([.,]\d+)?$').hasMatch(texto)) {
    return (null, '$etiqueta no es un número (usa coma o punto: 59,90)');
  }
  final fraccion = texto.split(RegExp(r'[.,]'));
  if (fraccion.length > 1 && fraccion[1].length > decimales) {
    final unidad = decimales == 1 ? 'decimal' : 'decimales';
    return (null, '$etiqueta admite máximo $decimales $unidad');
  }
  final valor = double.tryParse(texto.replaceAll(',', '.'));
  if (valor == null || valor.isNaN || valor.isInfinite) {
    return (null, '$etiqueta no es un número');
  }
  return (valor, null);
}
