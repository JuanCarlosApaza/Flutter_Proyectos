import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/presentation/widgets/buscador_tabla.dart';
import 'package:ventas/presentation/widgets/recurso_tabla.dart';
import 'package:ventas/presentation/widgets/vistas_estado.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final List<ColumnaTabla> _columnas = [
  const ColumnaTabla(clave: 'nombre', etiqueta: 'Producto', flex: 3),
  ColumnaTabla(
    clave: 'id',
    etiqueta: 'Código',
    flex: 1,
    formato: (r) => '#${r.id}',
  ),
  ColumnaTabla(
    clave: 'categoriaId',
    etiqueta: 'Categoría',
    flex: 2,
    formato: (r) =>
        r.numero('categoriaId') == 7 ? 'Analgésicos' : 'Antibióticos',
  ),
];

final List<Recurso> _items = [
  Recurso(
    id: 3,
    datos: const {
      'id': 3,
      'nombre': 'Paracetamol 500 mg',
      'categoriaId': 7,
      'precioVenta': 12.5,
    },
  ),
  Recurso(
    id: 8,
    datos: const {
      'id': 8,
      'nombre': 'Ibuprofeno 400 mg',
      'categoriaId': 7,
      'precioVenta': 8.75,
    },
  ),
  Recurso(
    id: 12,
    datos: const {
      'id': 12,
      'nombre': 'Amoxicilina 500 mg',
      'categoriaId': 2,
      'precioVenta': 15.0,
    },
  ),
  Recurso(
    id: 15,
    datos: const {
      'id': 15,
      'nombre': 'Suero Fisiológico 500 ml',
      'categoriaId': 2,
      'precioVenta': 6.0,
    },
  ),
];

Widget _envuelve(Widget hijo) => MaterialApp(home: Scaffold(body: hijo));

void main() {
  group('normalizarTexto', () {
    test('quita acentos, pasa a minúsculas y recorta', () {
      expect(normalizarTexto('  Analgésicos  '), 'analgesicos');
      expect(normalizarTexto('FISIOLÓGICO'), 'fisiologico');
      expect(normalizarTexto('ÑUÑOA y üBER'), 'nunoa y uber');
    });
  });

  group('filtrarPorBusqueda', () {
    test('sin texto devuelve la misma lista', () {
      expect(filtrarPorBusqueda(_items, _columnas, ''), same(_items));
      expect(filtrarPorBusqueda(_items, _columnas, '   '), same(_items));
    });

    test('filtra por nombre sin distinguir mayúsculas', () {
      final res = filtrarPorBusqueda(_items, _columnas, 'IBUPROFENO');
      expect(res, hasLength(1));
      expect(res.single.id, 8);
    });

    test('filtra por nombre con y sin acentos', () {
      expect(
        filtrarPorBusqueda(_items, _columnas, 'fisiologico').single.id,
        15,
      );
      expect(
        filtrarPorBusqueda(_items, _columnas, 'Fisiológico').single.id,
        15,
      );
    });

    test('filtra por el valor visible de una columna (categoría)', () {
      expect(
        filtrarPorBusqueda(_items, _columnas, 'analgesicos'),
        hasLength(2),
      );
      expect(
        filtrarPorBusqueda(_items, _columnas, 'Antibióticos').map((r) => r.id),
        [12, 15],
      );
    });

    test('filtra por el id formateado (#8)', () {
      final res = filtrarPorBusqueda(_items, _columnas, '#8');
      expect(res, hasLength(1));
      expect(res.single.id, 8);
    });

    test('filtra por un campo numérico del registro', () {
      final res = filtrarPorBusqueda(_items, _columnas, '8.75');
      expect(res, hasLength(1));
      expect(res.single.id, 8);
    });

    test('mantiene el orden original y devuelve vacío si no hay match', () {
      expect(filtrarPorBusqueda(_items, _columnas, '500 mg').map((r) => r.id), [
        3,
        12,
      ]);
      expect(filtrarPorBusqueda(_items, _columnas, 'ketorolaco'), isEmpty);
    });
  });

  testWidgets('BuscadorTabla notifica al escribir y al limpiar', (
    tester,
  ) async {
    final recibido = <String>[];
    await tester.pumpWidget(_envuelve(BuscadorTabla(onChanged: recibido.add)));

    await tester.enterText(find.byType(TextField), 'ibuprofeno');
    await tester.pump();
    expect(recibido, ['ibuprofeno']);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(recibido.last, '');
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('VistaSinResultados muestra la consulta y limpia', (
    tester,
  ) async {
    var limpiado = false;
    await tester.pumpWidget(
      _envuelve(
        VistaSinResultados(
          busqueda: 'ketorolaco',
          onLimpiar: () => limpiado = true,
        ),
      ),
    );

    expect(find.textContaining('ketorolaco'), findsOneWidget);
    await tester.tap(find.text('Limpiar búsqueda'));
    expect(limpiado, isTrue);
  });
}
