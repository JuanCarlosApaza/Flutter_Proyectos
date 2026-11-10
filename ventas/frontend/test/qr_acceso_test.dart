import 'package:ventas/core/widgets/dashboard_top_bar.dart';
import 'package:ventas/core/widgets/qr_acceso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  group('urlAcceso', () {
    test('omite los puertos por defecto (80/443)', () {
      expect(urlAcceso('192.168.1.4', puerto: 80), 'http://192.168.1.4');
      expect(
        urlAcceso('192.168.1.4', puerto: 443, esquema: 'https'),
        'https://192.168.1.4',
      );
    });

    test('incluye los puertos no estándar (web-server 8081)', () {
      expect(urlAcceso('192.168.1.4', puerto: 8081), 'http://192.168.1.4:8081');
    });
  });

  group('hostEsLocal', () {
    test('solo la máquina actual se considera local', () {
      expect(hostEsLocal('localhost'), isTrue);
      expect(hostEsLocal('127.0.0.1'), isTrue);
      expect(hostEsLocal('::1'), isTrue);
      expect(hostEsLocal(''), isTrue);
      expect(hostEsLocal('192.168.1.4'), isFalse);
      expect(hostEsLocal('10.0.0.5'), isFalse);
    });
  });

  group('etiquetaCandidata', () {
    test('muestra la interfaz cuando la API la conoce', () {
      expect(
        etiquetaCandidata(
          const CandidataAcceso('http://192.168.1.25:8081', interfaz: 'Wi-Fi'),
        ),
        'Wi-Fi · 192.168.1.25',
      );
    });

    test('sin interfaz se muestra solo el host', () {
      expect(
        etiquetaCandidata(const CandidataAcceso('http://192.168.1.4:8081')),
        '192.168.1.4',
      );
    });

    test(
      'el punto de acceso se etiqueta por su función, no por el adaptador',
      () {
        expect(
          etiquetaCandidata(
            const CandidataAcceso(
              'http://192.168.137.1:8081',
              interfaz: 'Conexión de red local* 2',
            ),
          ),
          'Punto de acceso · 192.168.137.1',
        );
      },
    );
  });

  group('esPuntoAcceso', () {
    test('solo la subred ICS de Windows es el punto de acceso', () {
      expect(esPuntoAcceso('192.168.137.1'), isTrue);
      expect(esPuntoAcceso('192.168.1.4'), isFalse);
      expect(esPuntoAcceso('10.0.0.5'), isFalse);
      expect(esPuntoAcceso('localhost'), isFalse);
      // Aunque la URL lleve puerto o esquema, el host es lo que manda.
      expect(
        const CandidataAcceso('http://192.168.137.1:8081').puntoAcceso,
        isTrue,
      );
      expect(
        const CandidataAcceso('http://192.168.1.4:8081').puntoAcceso,
        isFalse,
      );
    });
  });

  group('ordenarCandidatas', () {
    const casa = CandidataAcceso('http://192.168.1.4:8081', interfaz: 'Wi-Fi');
    const ethernet = CandidataAcceso('http://192.168.1.24:8081');
    const hotspot = CandidataAcceso('http://192.168.137.1:8081');

    test('el punto de acceso va primero, sin reordenar el resto', () {
      final ordenadas = ordenarCandidatas([ethernet, hotspot, casa]);
      expect(
        [for (final c in ordenadas) c.url],
        [
          'http://192.168.137.1:8081',
          'http://192.168.1.24:8081',
          'http://192.168.1.4:8081',
        ],
      );
    });

    test('sin punto de acceso el orden no cambia', () {
      final ordenadas = ordenarCandidatas([ethernet, casa]);
      expect(
        [for (final c in ordenadas) c.url],
        ['http://192.168.1.24:8081', 'http://192.168.1.4:8081'],
      );
    });

    test('lista vacía y lista de una quedan igual', () {
      expect(ordenarCandidatas(const []), isEmpty);
      expect(ordenarCandidatas(const [hotspot]).single.puntoAcceso, isTrue);
    });
  });

  group('puertoAcceso', () {
    test('en escritorio usa WEB_PORT (8081 por defecto)', () {
      expect(puertoAcceso(esWeb: false), 8081);
    });

    test('en web usa el puerto de la propia página', () {
      expect(
        puertoAcceso(base: Uri.parse('http://192.168.1.4:9000/x'), esWeb: true),
        9000,
      );
    });

    test('en web sin puerto explícito usa 80 / 443', () {
      expect(
        puertoAcceso(base: Uri.parse('http://192.168.1.4/'), esWeb: true),
        80,
      );
      expect(
        puertoAcceso(base: Uri.parse('https://192.168.1.4/'), esWeb: true),
        443,
      );
    });
  });

  test('urlsAcceso devuelve URLs http(s) con host no vacío', () async {
    final urls = await urlsAcceso();
    for (final url in urls) {
      final uri = Uri.parse(url);
      expect(uri.scheme, anyOf('http', 'https'));
      expect(uri.host, isNotEmpty);
    }
  });

  testWidgets('el top bar muestra el botón QR en la esquina superior derecha', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardTopBar(
            title: 'Resumen general',
            showMenuButton: false,
            onMenuTap: () {},
            showAccessQr: true,
          ),
        ),
      ),
    );

    final boton = find.byTooltip('Abrir en el celular');
    expect(boton, findsOneWidget);
    // A la derecha del título (esquina superior derecha).
    expect(
      tester.getCenter(boton).dx,
      greaterThan(tester.getCenter(find.text('Resumen general')).dx),
    );
  });

  testWidgets('el top bar oculta el botón QR si no se pide', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardTopBar(
            title: 'Resumen general',
            showMenuButton: false,
            onMenuTap: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Abrir en el celular'), findsNothing);
  });

  testWidgets('el diálogo de acceso se abre y muestra su título', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const DialogAccesoMovil(),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Abrir en el celular'), findsOneWidget);
    // Sin IPs de red accesibles en el entorno de test, aparece el aviso;
    // con el backend corriendo aparecería el QR. En cualquiera de los dos
    // casos el diálogo no debe fallar al renderizar.
    expect(tester.takeException(), isNull);
  });

  testWidgets('con URLs reales el diálogo dibuja el QR y deja elegir IP', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DialogAccesoMovil(
            urlsIniciales: [
              'http://192.168.1.3:8081',
              'http://192.168.1.4:8081',
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(QrImageView), findsOneWidget);
    // Chips para elegir IP + URL visible.
    expect(find.text('192.168.1.3'), findsWidgets);
    expect(find.text('192.168.1.4'), findsWidgets);
    expect(find.text('http://192.168.1.3:8081'), findsWidgets);
    expect(find.text('Copiar URL'), findsOneWidget);
    expect(find.textContaining('misma red'), findsOneWidget);
    // Sin candidata de punto de acceso no se enseña su aviso.
    expect(find.textContaining('Punto de acceso activo'), findsNothing);

    // Al elegir la otra IP cambia la URL mostrada (el QR se re-dibuja).
    await tester.tap(find.text('192.168.1.4'));
    await tester.pumpAndSettle();
    expect(find.text('http://192.168.1.4:8081'), findsWidgets);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('con el punto de acceso entre las URLs se avisa y sale primero', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DialogAccesoMovil(
            urlsIniciales: [
              'http://192.168.1.4:8081',
              'http://192.168.137.1:8081',
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // El QR por defecto apunta al punto de acceso: el celular conectado a él
    // no alcanza la otra subred.
    expect(find.text('http://192.168.137.1:8081'), findsWidgets);
    expect(find.text('Punto de acceso · 192.168.137.1'), findsOneWidget);
    expect(find.textContaining('Punto de acceso activo'), findsOneWidget);
  });
}
