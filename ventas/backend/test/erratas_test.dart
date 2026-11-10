import 'dart:io';

import 'package:test/test.dart';

/// La errata «ELIMINIDO» (con I de más) ha colado el SQL tres veces y solo
/// la cazaba la prueba contra la BD real: este test la detecta en cuanto se
/// escribe. El enum se llama `ELIMINADO`.
void main() {
  test('ninguna fuente usa ELIMINIDO (la errata del enum estado)', () {
    final culpables = <String>[];
    for (final entidad in Directory('lib').listSync(recursive: true)) {
      if (entidad is! File || !entidad.path.endsWith('.dart')) continue;
      if (entidad.readAsStringSync().contains('ELIMINIDO')) {
        culpables.add(entidad.path);
      }
    }
    expect(
      culpables,
      isEmpty,
      reason: 'ELIMINIDO no existe en la BD: escribe ELIMINADO',
    );
  });
}
