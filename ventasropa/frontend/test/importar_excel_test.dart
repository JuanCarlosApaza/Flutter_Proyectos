import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventas/core/excel/importar_productos.dart';
import 'package:ventas/core/excel/leer_excel.dart';
import 'package:ventas/core/excel/plantilla_excel.dart';

import 'archivo_excel_prueba.dart';

/// Importación de productos desde Excel: lectura del `.xlsx` (encabezados
/// en cualquier orden, filas numeradas como en el archivo) y validación
/// de cada fila con las mismas reglas que el formulario de producto.
void main() {
  group('plantilla descargable', () {
    test('se lee a sí misma y sus 3 ejemplos validan sin errores', () {
      final leido = leerExcel(plantillaExcel());
      expect(leido.fallo, isNull);
      expect(leido.filas, hasLength(3));
      // La cabecera es la fila 1: los datos empiezan en la 2.
      expect(leido.filas.first.fila, 2);
      expect(leido.filas.first.celdas['nombre'], 'Pantalón mezclillo');

      final filas = validarFilasExcel(leido.filas);
      final malas = filas.where((f) => f.errores.isNotEmpty).toList();
      expect(
        malas,
        isEmpty,
        reason: malas
            .map((f) => 'Fila ${f.fila}: ${f.errores.join(', ')}')
            .join('\n'),
      );

      // Una con tallas, una sin tallas (stock → «Única») y calzado con rango.
      expect(filas[0].producto!.variantes, hasLength(3));
      expect(filas[1].producto!.variantes, isEmpty);
      expect(filas[1].producto!.stock, 24);
      expect(filas[2].producto!.estado, 'AGOTADO');
      expect(filas.every((f) => f.importable), isTrue);
    });
  });

  group('lectura de encabezados', () {
    test('cualquier orden, otros nombres y columnas de más', () {
      final bytes = archivoExcel(
        [
          [
            'DISPONIBLE',
            'Textil Andina',
            'nota interna',
            89.9,
            'Ropa',
            59.9,
            'S|Negro|5',
            'Camiseta básica',
            12,
          ],
        ],
        cabeceras: const [
          'Estado', // desordenados respecto a la plantilla
          'Proveedor',
          'Notas Internas', // columna de más: se ignora
          'precioVenta', // alias camelCase
          'Categoría',
          'Precio de compra (Bs)', // con acento y paréntesis
          'Variantes (talla|color|stock)',
          'Nombre',
          'Stock inicial',
        ],
      );

      final leido = leerExcel(bytes);
      expect(leido.fallo, isNull);
      final celdas = leido.filas.single.celdas;
      expect(celdas['nombre'], 'Camiseta básica');
      expect(celdas['categoria'], 'Ropa');
      expect(celdas['precioCompra'], '59.9');
      expect(celdas['precioVenta'], '89.9');
      expect(celdas['variantes'], 'S|Negro|5');
      expect(celdas.keys, isNot(contains('notasinternas')));

      final filaLeida = validarFilasExcel(leido.filas).single;
      expect(filaLeida.errores, isEmpty, reason: filaLeida.errores.join(', '));
      expect(filaLeida.importable, isTrue);
    });

    test('faltan columnas obligatorias → el motivo, sin filas', () {
      final bytes = archivoExcel(
        [
          ['Camiseta básica', 'Ropa', 89.9],
        ],
        cabeceras: const ['Nombre', 'Categoría', 'Precio de venta (Bs)'],
      );

      final leido = leerExcel(bytes);
      expect(leido.fallo, contains('Faltan columnas obligatorias'));
      expect(leido.fallo, contains('Proveedor'));
      expect(leido.fallo, contains('Precio de compra (Bs)'));
      expect(leido.filas, isEmpty);
    });

    test('las filas totalmente vacías se saltan', () {
      final bytes = archivoExcel([
        ['', '', '', '', '', '', '', '', ''],
        ['Gorra Lana', 'Accesorios', 'Textil Andina', 20, 35],
      ]);

      final leido = leerExcel(bytes);
      expect(leido.fallo, isNull);
      expect(leido.filas, hasLength(1));
      expect(leido.filas.single.fila, 3); // cabecera + fila vacía
    });

    test('un archivo sin datos da error legible', () {
      final leido = leerExcel(
        archivoExcel([
          ['', '', '', '', '', '', '', '', ''],
        ]),
      );
      expect(leido.fallo, contains('ninguna fila de datos'));
    });

    test('un fichero que no es Excel no lanza, devuelve el motivo', () {
      final leido = leerExcel(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(leido.fallo, isNotNull);
      expect(leido.filas, isEmpty);
    });
  });

  group('validación de filas (espejo del formulario)', () {
    /// Una sola fila de datos leída de un `.xlsx` de verdad.
    FilaImportacion validar(
      Map<String, Object?> campos, {
      Set<String> existentes = const {},
    }) {
      final leido = leerExcel(archivoExcel([fila(campos)]));
      expect(leido.fallo, isNull, reason: leido.fallo);
      return validarFilasExcel(leido.filas, existentes: existentes).single;
    }

    test('precios con coma decimal y como celda numérica', () {
      final conComa = validar({
        'nombre': 'Camisa Algodón',
        'categoria': 'Ropa',
        'proveedor': 'Textil Andina',
        'precioCompra': '59,90',
        'precioVenta': '89,90',
        'variantes': 'M|Blanco|4',
      });
      expect(conComa.errores, isEmpty, reason: conComa.errores.join(', '));
      expect(conComa.producto!.precioCompra, 59.9);
      expect(conComa.producto!.precioVenta, 89.9);

      final numerica = validar({
        'nombre': 'Camisa Algodón',
        'categoria': 'Ropa',
        'proveedor': 'Textil Andina',
        'precioCompra': 59.9,
        'precioVenta': 89.9,
        'variantes': 'M|Blanco|4',
      });
      expect(numerica.errores, isEmpty, reason: numerica.errores.join(', '));
    });

    test('la venta por debajo de la compra es error y no deja producto', () {
      final filaLeida = validar({
        'nombre': 'Barato raro',
        'categoria': 'Ropa',
        'proveedor': 'Textil Andina',
        'precioCompra': 50,
        'precioVenta': 30,
        'variantes': 'M|Blanco|4',
      });
      expect(filaLeida.errores.single, contains('no puede ser menor'));
      expect(filaLeida.producto, isNull);
      expect(filaLeida.importable, isFalse);
    });

    test('más de 2 decimales en precios y de 3 en stock', () {
      final precio = validar({
        'nombre': 'Camisa Algodón',
        'categoria': 'Ropa',
        'proveedor': 'Textil Andina',
        'precioCompra': '59.999',
        'precioVenta': 89,
        'variantes': 'M|Blanco|4',
      });
      expect(precio.errores.single, contains('máximo 2 decimales'));

      final stock = validar({
        'nombre': 'Camisa Algodón',
        'categoria': 'Ropa',
        'proveedor': 'Textil Andina',
        'precioCompra': 59,
        'precioVenta': 89,
        'variantes': '',
        'stock': '10.5555',
      });
      expect(stock.errores.single, contains('máximo 3 decimales'));
    });

    test('frases de talla no valen; rangos, mezclas y «Única» sí', () {
      final mala = validar({
        'nombre': 'Zapatilla Rara',
        'categoria': 'Zapatos',
        'proveedor': 'Deportes Sur',
        'precioCompra': 100,
        'precioVenta': 150,
        'variantes': 'talla 38|Negro|5',
      });
      expect(mala.errores.single, contains('Talla no válida'));
      expect(mala.errores.single, contains('talla 38')); // se ve el combo

      final buena = validar({
        'nombre': 'Zapatilla Running',
        'categoria': 'Zapatos',
        'proveedor': 'Deportes Sur',
        'precioCompra': 100,
        'precioVenta': 150,
        'variantes': 'S/M|Negro|2;39-41|Blanco|4;40/41|Rojo|3;Única|Único|6',
      });
      expect(buena.errores, isEmpty, reason: buena.errores.join(', '));
      expect(buena.producto!.variantes, hasLength(4));
    });

    test('sin variantes: stock obligatorio; con stock, producto «Única»', () {
      final sinNada = validar({
        'nombre': 'Medias Clásicas',
        'categoria': 'Medias',
        'proveedor': 'Textil Andina',
        'precioCompra': 15,
        'precioVenta': 25,
        'variantes': '',
        'stock': '',
      });
      expect(sinNada.errores.single, contains('Falta el stock inicial'));
      expect(sinNada.producto, isNull);

      final conStock = validar({
        'nombre': 'Medias Clásicas',
        'categoria': 'Medias',
        'proveedor': 'Textil Andina',
        'precioCompra': 15,
        'precioVenta': 25,
        'variantes': '',
        'stock': 24,
      });
      expect(conStock.errores, isEmpty, reason: conStock.errores.join(', '));
      expect(conStock.producto!.variantes, isEmpty);
      expect(conStock.producto!.stock, 24);
    });

    test('combinación repetida dentro de la misma fila', () {
      final filaLeida = validar({
        'nombre': 'Camisa Algodón',
        'categoria': 'Ropa',
        'proveedor': 'Textil Andina',
        'precioCompra': 59,
        'precioVenta': 89,
        'variantes': 'S|Negro|5;s|negro|3',
      });
      expect(filaLeida.errores.single, contains('repetida'));
    });

    test('estado: vacío → DISPONIBLE, minúsculas se aceptan, basura no', () {
      final base = {
        'nombre': 'Camisa Algodón',
        'categoria': 'Ropa',
        'proveedor': 'Textil Andina',
        'precioCompra': 59,
        'precioVenta': 89,
        'variantes': 'M|Blanco|4',
      };

      expect(validar({...base, 'estado': ''}).producto!.estado, 'DISPONIBLE');
      expect(
        validar({...base, 'estado': 'agotado'}).producto!.estado,
        'AGOTADO',
      );
      final basura = validar({...base, 'estado': 'ROTO'});
      expect(basura.errores.single, contains('Estado no válido'));
    });

    test('marca opcional: se lee del Excel y valida su longitud', () {
      final conMarca = validar({
        'nombre': 'Camisa Algodón',
        'categoria': 'Ropa',
        'marca': 'Denver',
        'proveedor': 'Textil Andina',
        'precioCompra': 59,
        'precioVenta': 89,
        'variantes': 'M|Blanco|4',
      });
      expect(conMarca.errores, isEmpty, reason: conMarca.errores.join(', '));
      expect(conMarca.producto!.marca, 'Denver');

      // Sin marca la prenda queda sin ella (nunca es obligatoria).
      final sinMarca = validar({
        'nombre': 'Camisa Algodón',
        'categoria': 'Ropa',
        'proveedor': 'Textil Andina',
        'precioCompra': 59,
        'precioVenta': 89,
        'variantes': 'M|Blanco|4',
      });
      expect(sinMarca.errores, isEmpty, reason: sinMarca.errores.join(', '));
      expect(sinMarca.producto!.marca, isNull);

      // El límite del backend (100) también se corta aquí, con la fila.
      final larga = validar({
        'nombre': 'Camisa Algodón',
        'categoria': 'Ropa',
        'marca': 'x' * 101,
        'proveedor': 'Textil Andina',
        'precioCompra': 59,
        'precioVenta': 89,
        'variantes': 'M|Blanco|4',
      });
      expect(larga.errores.single, contains('100 caracteres'));
      expect(larga.producto, isNull);
    });

    test('faltan el nombre, la categoría o el proveedor', () {
      final filaLeida = validar({
        'nombre': '',
        'categoria': '',
        'proveedor': '',
        'precioCompra': 59,
        'precioVenta': 89,
        'variantes': 'M|Blanco|4',
      });
      expect(filaLeida.errores, contains('Falta el nombre'));
      expect(filaLeida.errores, contains('Falta la categoría'));
      expect(filaLeida.errores, contains('Falta el proveedor'));
    });

    test('repetidos: en la BD (acentos) y en el propio archivo', () {
      final enBd = validar(
        {
          'nombre': 'Pantalón Mezclillo',
          'categoria': 'Ropa',
          'proveedor': 'Textil Andina',
          'precioCompra': 59,
          'precioVenta': 89,
          'variantes': 'S|Negro|5',
        },
        existentes: const {'pantalon mezclillo'},
      );
      expect(enBd.errores, isEmpty); // la fila está bien… pero se salta
      expect(enBd.duplicada, isTrue);
      expect(enBd.importable, isFalse);
      expect(enBd.avisos.single, contains('Ya existe'));

      final leido = leerExcel(
        archivoExcel([
          fila({
            'nombre': 'Gorra Lana',
            'categoria': 'Accesorios',
            'proveedor': 'Textil Andina',
            'precioCompra': 20,
            'precioVenta': 35,
            'variantes': 'Única|Verde|9',
          }),
          fila({
            'nombre': 'gorra lana',
            'categoria': 'Accesorios',
            'proveedor': 'Textil Andina',
            'precioCompra': 20,
            'precioVenta': 35,
            'variantes': 'Única|Verde|9',
          }),
        ]),
      );
      final filas = validarFilasExcel(leido.filas);
      expect(filas[0].importable, isTrue); // gana el primero
      expect(filas[1].duplicada, isTrue);
      expect(filas[1].avisos.single, contains('repetido'));
      expect(filas[1].importable, isFalse);
    });
  });
}
