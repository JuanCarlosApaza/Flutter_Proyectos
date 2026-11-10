import 'dart:io';

import 'package:farmacia_backend/src/core/log_asistente.dart';
import 'package:farmacia_backend/src/data/services/descargador_modelo.dart';
import 'package:test/test.dart';

void main() {
  logAsistenteActivo = false;

  late Directory carpeta;

  setUp(() {
    carpeta = Directory.systemTemp.createTempSync('descargador_test');
  });

  tearDown(() {
    if (carpeta.existsSync()) carpeta.deleteSync(recursive: true);
  });

  /// Descargador con descarga y `ollama create` sustituidos por fakes.
  ///
  /// [bytes] es lo que el fake de descarga deja escrito y [codigoCreate] el
  /// código de salida que devuelve `ollama create`.
  DescargadorModelo descargador({
    List<int> bytes = const [1, 2, 3],
    int codigoCreate = 0,
    String errorCreate = '',
    void Function(int recibidos, int? total)? avances,
    bool falla = false,
  }) => DescargadorModelo(
    url: 'https://huggingface.co/x/resolve/main/modelo.gguf',
    modelo: 'farmacia-x',
    directorio: carpeta.path,
    descargar: (uri, destino, {required onProgreso}) async {
      if (falla) throw Exception('se cortó la red');
      destino.writeAsBytesSync(bytes);
      onProgreso(bytes.length, 100);
      avances?.call(bytes.length, 100);
    },
    crear: (argumentos) async {
      // Guarda los argumentos para poder asertar el Modelfile.
      File('${carpeta.path}${Platform.pathSeparator}create_args.txt')
          .writeAsStringSync(argumentos.join(' | '));
      return (codigo: codigoCreate, error: errorCreate);
    },
  );

  test('descarga, renombra .part → .gguf y ejecuta ollama create', () async {
    final d = descargador();
    await d.iniciar();
    // `iniciar()` no espera: la tarea corre en segundo plano.
    await _esperar(() => d.estado.fase != FaseDescarga.descargando);

    expect(d.estado.fase, FaseDescarga.listo);
    expect(d.estado.error, isNull);

    final gguf = File('${carpeta.path}${Platform.pathSeparator}modelo.gguf');
    expect(gguf.existsSync(), isTrue);
    expect(gguf.readAsBytesSync(), [1, 2, 3]);
    // El `.part` ya no existe: el renombrado es el sello de «completo».
    expect(
      File('${carpeta.path}${Platform.pathSeparator}modelo.gguf.part')
          .existsSync(),
      isFalse,
    );

    final args = File('${carpeta.path}${Platform.pathSeparator}create_args.txt')
        .readAsStringSync();
    expect(args, startsWith('create | farmacia-x | -f | '));

    // El Modelfile apunta al GGUF absoluto y fija la ventana del contexto.
    final modelfile = File('${carpeta.path}${Platform.pathSeparator}Modelfile')
        .readAsStringSync();
    expect(modelfile, contains('FROM '));
    expect(modelfile, contains('modelo.gguf'));
    expect(modelfile, contains('num_ctx 8192'));
  });

  test('publica el porcentaje mientras descarga', () async {
    final vistos = <int?>[];
    final d = descargador(avances: (r, t) => vistos.add(t));

    await d.iniciar();
    await _esperar(() => d.estado.fase == FaseDescarga.listo);

    expect(vistos, isNotEmpty);
    expect(d.estado.bytes, 3);
  });

  test('si la descarga falla → fase error y borra el .part', () async {
    final d = descargador(falla: true);
    await d.iniciar();
    await _esperar(() => d.estado.fase == FaseDescarga.error);

    expect(d.estado.error, contains('se cortó la red'));
    expect(
      File('${carpeta.path}${Platform.pathSeparator}modelo.gguf.part')
          .existsSync(),
      isFalse,
    );
    // Nunca se llegó a crear el modelo.
    expect(
      File('${carpeta.path}${Platform.pathSeparator}create_args.txt')
          .existsSync(),
      isFalse,
    );
  });

  test(
    'si ollama create devuelve distinto de 0 → fase error legible',
    () async {
      final d = descargador(
        codigoCreate: 1,
        errorCreate: 'Error: model "x" not found',
      );
      await d.iniciar();
      await _esperar(() => d.estado.fase == FaseDescarga.error);

      expect(d.estado.error, contains('Ollama'));
    },
  );

  test('si no existe el binario → mensaje de instalar ollama.com', () async {
    final d = descargador(
      codigoCreate: 127,
      errorCreate: 'No se pudo ejecutar "ollama": el sistema no encuentra',
    );
    await d.iniciar();
    await _esperar(() => d.estado.fase == FaseDescarga.error);

    expect(d.estado.error, contains('ollama.com'));
  });

  test('un GGUF ya descargado no se vuelve a bajar', () async {
    var bajadas = 0;
    final d = DescargadorModelo(
      url: 'https://huggingface.co/x/resolve/main/modelo.gguf',
      modelo: 'farmacia-x',
      directorio: carpeta.path,
      descargar: (uri, destino, {required onProgreso}) async {
        bajadas++;
        destino.writeAsBytesSync([9]);
        onProgreso(1, 1);
      },
      crear: (argumentos) async => (codigo: 0, error: ''),
    );

    File('${carpeta.path}${Platform.pathSeparator}modelo.gguf')
        .writeAsBytesSync([7, 7, 7]);

    await d.iniciar();
    await _esperar(() => d.estado.fase == FaseDescarga.listo);

    expect(bajadas, 0);
    expect(d.estado.bytes, 3);
  });

  test('iniciar() mientras hay una en marcha no duplica el trabajo', () async {
    final d = descargador();
    await d.iniciar();
    expect(d.estado.activo, isTrue);
    await d.iniciar(); // se ignora
    await _esperar(() => d.estado.fase == FaseDescarga.listo);
  });

  test('comandoDisponible() distingue «no está» de «está y falla»', () async {
    // Instalado: cualquier salida que no sea el 127 cuenta como disponible.
    expect(await descargador().comandoDisponible(), isTrue);
    expect(await descargador(codigoCreate: 1).comandoDisponible(), isTrue);
    // El binario no se encuentra en ningún emplazamiento.
    expect(await descargador(codigoCreate: 127).comandoDisponible(), isFalse);
  });

  test('marcarListo() y reiniciar() cambian el estado', () {
    final d = descargador();
    d.marcarListo();
    expect(d.estado.fase, FaseDescarga.listo);
    expect(d.estado.activo, isFalse);
    d.reiniciar();
    expect(d.estado.fase, FaseDescarga.inactivo);
  });

  test('bytesLegibles traduce B/KB/MB/GB', () {
    expect(bytesLegibles(512), '512 B');
    expect(bytesLegibles(2048), '2.0 KB');
    expect(bytesLegibles(5 * 1024 * 1024), '5.0 MB');
    expect(bytesLegibles(1024 * 1024 * 1024), '1.00 GB');
  });
}

/// Espera a que [condicion] se cumpla sin usar `Future.delayed` a ciegas:
/// el estado se publica dentro de la tarea en background, así que basta con
/// ceder el turno unas cuantas veces.
Future<void> _esperar(bool Function() condicion) async {
  for (var i = 0; i < 200; i++) {
    if (condicion()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('La condición no se cumplió a tiempo.');
}
