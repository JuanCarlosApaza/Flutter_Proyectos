import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventas/presentation/importar/lector_excel.dart';
import 'package:ventas/presentation/importar/plantilla_excel.dart';
import 'package:ventas/presentation/importar/validador_producto.dart';
import 'package:ventas/presentation/widgets/recurso_form.dart';

/// Mismo reparto que el de `ProductosPage`: los nueve campos obligatorios
/// (nombre, precios, stock, unidad, estado y los tres catálogos) y el resto
/// opcional. Los límites son los del formulario, porque el validador los
/// lee de aquí. No puede ser `const`: los campos traen cierres
/// (`opcionesDinamicas`, `onCrear`).
final List<CampoFormulario> _campos = [
  CampoFormulario(
    clave: 'nombre',
    etiqueta: 'Nombre *',
    obligatorio: true,
    minCaracteres: 2,
    maxCaracteres: 150,
  ),
  CampoFormulario(
    clave: 'precioCompra',
    etiqueta: 'Precio de compra (Bs) *',
    obligatorio: true,
    tipo: TipoCampo.decimal,
    min: 0.01,
    max: 99999999.99,
  ),
  CampoFormulario(
    clave: 'precioVenta',
    etiqueta: 'Precio de venta (Bs) *',
    obligatorio: true,
    tipo: TipoCampo.decimal,
    min: 0.01,
    max: 99999999.99,
  ),
  CampoFormulario(
    clave: 'gananciaPct',
    etiqueta: 'Ganancia %',
    tipo: TipoCampo.porcentaje,
    min: 0,
    max: 999,
    porcentajeSobre: 'precioCompra',
    porcentajeDestino: 'precioVenta',
  ),
  CampoFormulario(
    clave: 'stock',
    etiqueta: 'Stock *',
    obligatorio: true,
    tipo: TipoCampo.decimal,
    min: 0,
    max: 999999.999,
    decimales: 3,
  ),
  CampoFormulario(
    clave: 'unidad',
    etiqueta: 'Unidad de venta *',
    obligatorio: true,
    tipo: TipoCampo.opcion,
    opcionesDinamicas: () => const [
      Opccion('UN', 'Unidad (UN)'),
      Opccion('KG', 'Kilogramo (KG)'),
    ],
  ),
  CampoFormulario(
    clave: 'estado',
    etiqueta: 'Estado *',
    obligatorio: true,
    tipo: TipoCampo.opcion,
    opciones: [
      Opccion('DISPONIBLE', 'Disponible'),
      Opccion('AGOTADO', 'Agotado'),
      Opccion('POR_VENCER', 'Por vencer'),
    ],
  ),
  CampoFormulario(
    clave: 'variantes',
    etiqueta: 'Colores (stock por variante)',
    tipo: TipoCampo.variantes,
  ),
  CampoFormulario(clave: 'codigo', etiqueta: 'Código', maxCaracteres: 60),
  CampoFormulario(
    clave: 'descripcion',
    etiqueta: 'Descripción',
    maxCaracteres: 255,
  ),
  CampoFormulario(
    clave: 'precioRebaja',
    etiqueta: 'Máximo a rebajar por unidad (Bs)',
    tipo: TipoCampo.decimal,
    min: 0,
    max: 99999999.99,
  ),
  CampoFormulario(
    clave: 'stockMinimo',
    etiqueta: 'Stock mínimo',
    tipo: TipoCampo.decimal,
    min: 0,
    max: 999999.999,
    decimales: 3,
  ),
  CampoFormulario(
    clave: 'fechaVencimiento',
    etiqueta: 'Fecha de vencimiento',
    tipo: TipoCampo.fecha,
    minFecha: DateTime(2020, 1, 1),
  ),
  CampoFormulario(
    clave: 'categoriaId',
    etiqueta: 'Categoría *',
    obligatorio: true,
    tipo: TipoCampo.opcion,
    opcionesDinamicas: () => const [Opccion('1', 'Bebidas')],
    onCrear: _crear,
  ),
  CampoFormulario(
    clave: 'presentacionId',
    etiqueta: 'Presentación *',
    obligatorio: true,
    tipo: TipoCampo.opcion,
    opcionesDinamicas: () => const [Opccion('7', 'Botella')],
    onCrear: _crear,
  ),
  CampoFormulario(
    clave: 'marcaId',
    etiqueta: 'Marca *',
    obligatorio: true,
    tipo: TipoCampo.opcion,
    opcionesDinamicas: () => const [Opccion('3', 'Andina')],
    onCrear: _crear,
  ),
  CampoFormulario(
    clave: 'garantiaMeses',
    etiqueta: 'Garantía (meses)',
    tipo: TipoCampo.opcion,
    opciones: [Opccion('12', '12 meses'), Opccion('24', '24 meses')],
  ),
  CampoFormulario(
    clave: 'proveedorId',
    etiqueta: 'Proveedor',
    tipo: TipoCampo.opcion,
    opcionesDinamicas: () => const [Opccion('9', 'Distribuidora Sur')],
    onCrear: _crear,
  ),
  CampoFormulario(
    clave: 'imagen',
    etiqueta: 'Imagen del producto',
    tipo: TipoCampo.imagen,
  ),
];

Future<String?> _crear(String nombre) async => nombre;

/// Construye un .xlsx en memoria con una sola hoja `datos`.
Uint8List _xlsx(List<List<String?>> filas) {
  final celdas = <String>[];
  for (var i = 0; i < filas.length; i++) {
    final xml = <String>[];
    for (var j = 0; j < filas[i].length; j++) {
      final texto = filas[i][j];
      if (texto == null || texto.isEmpty) continue;
      final ref = _ref(j, i + 1);
      // Solo se escribe como número lo que ya viene con punto: una celda
      // de texto con coma (`12,50`) lo es, y el lector la acepta igual.
      final numero = double.tryParse(texto);
      final esNumero =
          numero != null && RegExp(r'^-?\d+(\.\d+)?$').hasMatch(texto);
      final guardado = numero == null
          ? texto
          : numero == numero.roundToDouble()
          ? numero.toInt().toString()
          : '$numero';
      xml.add(
        esNumero
            ? '<c r="$ref"><v>$guardado</v></c>'
            : '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
                  '$texto</t></is></c>',
      );
    }
    if (xml.isNotEmpty) celdas.add('<row r="${i + 1}">${xml.join()}</row>');
  }
  return _libro(celdas.join());
}

Uint8List _libro(String sheetData) {
  const types =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
      'content-types">'
      '<Default Extension="rels" ContentType="application/vnd.'
      'openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.'
      'openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="'
      'application/vnd.openxmlformats-officedocument.spreadsheetml.'
      'worksheet+xml"/>'
      '</Types>';
  const rels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/officeDocument" '
      'Target="xl/workbook.xml"/>'
      '</Relationships>';
  const workbook =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/'
      'main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships">'
      '<sheets><sheet name="datos" sheetId="1" r:id="rId1"/></sheets>'
      '</workbook>';
  const workbookRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/worksheet" '
      'Target="worksheets/sheet1.xml"/>'
      '</Relationships>';
  final zip = Archive()
    ..addFile(ArchiveFile.string('[Content_Types].xml', types))
    ..addFile(ArchiveFile.string('_rels/.rels', rels))
    ..addFile(ArchiveFile.string('xl/workbook.xml', workbook))
    ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', workbookRels))
    ..addFile(
      ArchiveFile.string(
        'xl/worksheets/sheet1.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
            '2006/main"><sheetData>$sheetData</sheetData></worksheet>',
      ),
    );
  return ZipEncoder().encodeBytes(zip);
}

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

void main() {
  group('lector de Excel', () {
    test('lee la plantilla y casa sus encabezados con los campos', () {
      final bytes = plantillaProductos(campos: _campos);
      final lectura = leerFilasExcel(bytes, campos: _campos);

      expect(lectura.error, isNull);
      expect(lectura.filas, hasLength(2));
      // La fila 1 es la de encabezados y no se cuenta como datos.
      expect(lectura.filas.first.fila, 2);
      expect(lectura.filas.first.valor('nombre'), 'Gaseosa Cola 2 L');
      expect(lectura.filas.first.valor('precioVenta'), '12');
      expect(lectura.filas.first.valor('categoriaId'), 'Bebidas');
      // La segunda fila trae la celda multi-valor de colores.
      expect(lectura.filas.last.valor('variantes'), 'Rojo|2;Azul|5');
    });

    test('el orden de las columnas no importa y acepta alias', () {
      final bytes = _xlsx([
        ['Marca', 'precio_venta', 'CATEGORIA', 'nombre', 'NoSirve'],
        ['Andina', '12,50', 'Bebidas', 'Gaseosa', 'x'],
      ]);
      final lectura = leerFilasExcel(bytes, campos: _campos);

      expect(lectura.error, isNull);
      final fila = lectura.filas.single;
      expect(fila.valor('marcaId'), 'Andina');
      expect(fila.valor('precioVenta'), '12,50');
      expect(fila.valor('categoriaId'), 'Bebidas');
      expect(fila.valor('nombre'), 'Gaseosa');
      expect(fila.celdas.containsKey('NoSirve'), isFalse);
    });

    test('las filas completamente vacías se ignoran sin error', () {
      final bytes = _xlsx([
        ['nombre', 'precioVenta'],
        ['Pan', '2'],
        [null, null],
        ['', ''],
        ['Croissant', '3'],
      ]);
      final lectura = leerFilasExcel(bytes, campos: _campos);

      expect(lectura.error, isNull);
      // El número real de fila se conserva (la 4 está vacía y no se escribe,
      // pero la Croissant sigue siendo la fila 5 del Excel).
      expect(lectura.filas.map((f) => f.fila), [2, 5]);
    });

    test('un fichero que no es .xlsx da error global', () {
      final lectura = leerFilasExcel(
        Uint8List.fromList('hola'.codeUnits),
        campos: _campos,
      );

      expect(lectura.error, contains('.xlsx'));
      expect(lectura.filas, isEmpty);
    });

    test('un libro sin encabezados reconocidos da error', () {
      final bytes = _xlsx([
        ['nada que ver', 'otra cosa'],
        ['a', 'b'],
      ]);
      final lectura = leerFilasExcel(bytes, campos: _campos);

      expect(lectura.error, contains('encabezado'));
      expect(lectura.filas, isEmpty);
    });
  });

  group('validación de filas', () {
    /// Cabecera como la escribe la plantilla (el orden de las columnas no
    /// importa, pero así es con el que trabajan estos tests).
    const cabecera = [
      'Nombre',
      'Precio de compra (Bs)',
      'Precio de venta (Bs)',
      'Ganancia %',
      'Stock',
      'Unidad de venta',
      'Estado',
      'Colores (stock por variante)',
      'Código',
      'Máximo a rebajar por unidad (Bs)',
      'Fecha de vencimiento',
      'Categoría *',
      'Presentación *',
      'Marca *',
      'Garantía (meses)',
    ];

    /// Una fila válida, escrita por NOMBRE de columna.
    Map<String, String?> porDefecto() => {
      'Nombre': 'Gaseosa Cola 2 L',
      'Precio de compra (Bs)': '8',
      'Precio de venta (Bs)': '12',
      'Stock': '60',
      'Unidad de venta': 'UN',
      'Estado': 'DISPONIBLE',
      'Código': 'BEB-002',
      'Categoría *': 'Bebidas',
      'Presentación *': 'Botella',
      'Marca *': 'Andina',
    };

    /// Valida varias filas: el helper monta la hoja con el orden de
    /// [cabecera], igual que haría Excel al guardar.
    List<FilaValidada> validar(List<Map<String, String?>> datos) {
      final hoja = <List<String?>>[
        cabecera,
        for (final fila in datos)
          [for (final titulo in cabecera) fila[titulo] ?? ''],
      ];
      final lectura = leerFilasExcel(_xlsx(hoja), campos: _campos);
      expect(lectura.error, isNull);
      return validarFilas(filas: lectura.filas, campos: _campos);
    }

    /// Una sola fila (la 2 de la hoja) con los valores que se indiquen.
    FilaValidada validarFila(Map<String, String?> valores) =>
        validar([porDefecto()..addAll(valores)]).single;

    test('una fila válida sale con el cuerpo listo para la API', () {
      final fila = validarFila({});

      expect(fila.motivo, isNull);
      expect(fila.duplicada, isFalse);
      expect(fila.debeImportar, isTrue);
      expect(fila.fila, 2);
      expect(fila.cuerpo['nombre'], 'Gaseosa Cola 2 L');
      expect(fila.cuerpo['precioCompra'], 8.0);
      expect(fila.cuerpo['precioVenta'], 12.0);
      expect(fila.cuerpo['stock'], 60.0);
      expect(fila.cuerpo['unidad'], 'UN');
      expect(fila.cuerpo['estado'], 'DISPONIBLE');
      expect(fila.cuerpo['categoriaId'], '1');
      expect(fila.cuerpo['presentacionId'], '7');
      expect(fila.cuerpo['marcaId'], '3');
      expect(fila.cuerpo['codigo'], 'BEB-002');
      expect(fila.cuerpo['variantes'], isEmpty);
    });

    test('números con coma y recorte de decimales como en el formulario', () {
      final fila = validarFila({
        'Precio de compra (Bs)': '8,50',
        'Precio de venta (Bs)': '12,75',
        'Stock': '1,2345',
      });

      expect(fila.motivo, isNull);
      expect(fila.cuerpo['precioCompra'], 8.5);
      expect(fila.cuerpo['precioVenta'], 12.75);
      // El stock admite 3 decimales: la cuarta cifra se recorta.
      expect(fila.cuerpo['stock'], 1.234);
    });

    test('campo obligatorio vacío → el mismo mensaje del formulario', () {
      final fila = validarFila({'Nombre': ''});

      expect(fila.motivo, 'Este campo es obligatorio');
      expect(fila.debeImportar, isFalse);
    });

    test('límites campo a campo (los mismos del formulario)', () {
      expect(
        validarFila({'Nombre': 'X'}).motivo,
        'Debe tener al menos 2 caracteres',
      );
      expect(
        validarFila({'Precio de venta (Bs)': '0'}).motivo,
        'Debe ser mayor o igual a 0.01',
      );
      expect(
        validarFila({'Precio de venta (Bs)': '100000000'}).motivo,
        'No puede superar 99999999.99',
      );
      expect(
        validarFila({'Stock': '1000000'}).motivo,
        'No puede superar 999999.999',
      );
      expect(validarFila({'Stock': '12,5'}).motivo, isNull);
      expect(
        validarFila({'Unidad de venta': 'Barril'}).motivo,
        contains('No existe'),
      );
      expect(validarFila({'Estado': 'vendido'}).motivo, contains('No existe'));
      expect(
        validarFila({'Garantía (meses)': '36'}).motivo,
        contains('No existe'),
      );
    });

    test('precio de venta por debajo del coste → igual que el formulario', () {
      final fila = validarFila({
        'Precio de compra (Bs)': '20',
        'Precio de venta (Bs)': '10',
      });

      expect(fila.motivo, contains('no puede ser menor'));
    });

    test('máximo a rebajar por encima del precio → avisa', () {
      final fila = validarFila({'Máximo a rebajar por unidad (Bs)': '20'});

      expect(fila.motivo, contains('no puede superar el precio de venta'));
      expect(
        validarFila({'Máximo a rebajar por unidad (Bs)': '5'}).motivo,
        isNull,
      );
    });

    test('la fecha no puede ser anterior a la del formulario', () {
      expect(
        validarFila({'Fecha de vencimiento': '01/01/2019'}).motivo,
        'No puede ser anterior a 2020-01-01',
      );
      expect(
        validarFila({'Fecha de vencimiento': '31/12/2030'}).motivo,
        isNull,
      );
      expect(
        validarFila({'Fecha de vencimiento': 'ayer'}).motivo,
        'Debe ser una fecha válida',
      );
    });

    test('Ganancia % calcula el precio cuando este viene vacío', () {
      final fila = validarFila({
        'Precio de compra (Bs)': '10',
        'Precio de venta (Bs)': '',
        'Ganancia %': '50',
      });

      expect(fila.motivo, isNull);
      expect(fila.cuerpo['precioVenta'], 15.0);
      // La calculadora no viaja al backend.
      expect(fila.cuerpo.containsKey('gananciaPct'), isFalse);
    });

    test(
      'Ganancia % sin precio de compra manda el error del propio precio',
      () {
        final fila = validarFila({
          'Precio de compra (Bs)': '',
          'Ganancia %': '50',
        });

        // El precio de compra es obligatorio y va antes que la calculadora,
        // igual que en el formulario.
        expect(fila.motivo, 'Este campo es obligatorio');
      },
    );

    test('Colores: manda la suma al stock y valida cada fila', () {
      final fila = validarFila({
        'Colores (stock por variante)': 'Rojo|2;Azul|0,5',
        'Stock': '999',
      });

      expect(fila.motivo, isNull);
      expect(fila.cuerpo['stock'], 2.5, reason: 'manda la suma, no la celda');
      expect(fila.cuerpo['variantes'], [
        {'color': 'Rojo', 'cantidad': 2.0},
        {'color': 'Azul', 'cantidad': 0.5},
      ]);

      expect(
        validarFila({'Colores (stock por variante)': 'Rojo|2;Rojo|1'}).motivo,
        contains('más de una vez'),
      );
      expect(
        validarFila({'Colores (stock por variante)': 'Rojo 2'}).motivo,
        contains('Color|cantidad'),
      );
      expect(
        validarFila({'Colores (stock por variante)': 'Ro|jo|2'}).motivo,
        contains('más de un «|»'),
      );
      expect(
        validarFila({'Colores (stock por variante)': 'Rojo|abc'}).motivo,
        contains('cantidad numérica'),
      );
    });

    test('relación inexistente → se creará al importar (no es error)', () {
      final fila = validarFila({'Categoría *': 'Refrescos'});

      expect(fila.motivo, isNull);
      expect(fila.debeImportar, isTrue);
      expect(fila.pendientes, hasLength(1));
      expect(fila.pendientes.single.clave, 'categoriaId');
      expect(fila.pendientes.single.nombre, 'Refrescos');
      expect(fila.cuerpo['categoriaId'], isNull);
    });

    test('duplicados: por código y por nombre + categoría + presentación', () {
      final conCodigo = porDefecto();
      final conCodigoRepetido = porDefecto();
      final otroNombre = porDefecto();
      otroNombre['Nombre'] = 'Otro Producto';
      otroNombre['Código'] = '';
      final mismoNombre = porDefecto();
      mismoNombre['Código'] = '';

      final filas = validar([
        conCodigo,
        conCodigoRepetido,
        otroNombre,
        mismoNombre,
      ]);

      expect(filas[0].debeImportar, isTrue);
      expect(filas[1].duplicada, isTrue, reason: 'mismo código');
      expect(filas[2].debeImportar, isTrue, reason: 'otro nombre, sin código');
      expect(
        filas[3].duplicada,
        isTrue,
        reason: 'sin código → nombre + categoría + presentación',
      );
      expect(filas[1].motivo, contains('repetida'));
    });

    test('el resumen cuenta válidas, con error y repetidas', () {
      final conError = porDefecto();
      conError['Nombre'] = '';
      final repetida = porDefecto();
      final otra = porDefecto();
      otra['Nombre'] = 'Pan Integral';
      otra['Código'] = 'PAN-001';

      final resumen = resumenImportacion(
        validar([porDefecto(), conError, repetida, otra]),
      );

      expect(resumen.validas, 2);
      expect(resumen.conError, 1);
      expect(resumen.repetidas, 1);
    });
  });
}
