import 'dart:async';
import 'dart:io';

import '../../domain/usecases/ajuste_usecases.dart';
import '../../domain/usecases/respaldo_usecases.dart';

/// Respaldo automático de la BD: decide **cuándo** toca, no **cómo**.
///
/// El backend no tenía ningún temporizador; este es el primero. Usa un
/// `Timer` que se re-arma solo (no `Timer.periodic`) para que el instante
/// siguiente se recalcule siempre contra el último `.dump` real: si alguien
/// respalda a mano, la cuenta empieza de nuevo desde ese momento.
final class ProgramadorRespaldos {
  ProgramadorRespaldos({required this.ajustes, required this.respaldos});

  /// Ajustes del sistema: de aquí sale el intervalo (`respaldoIntervalo`).
  final Ajustes ajustes;

  /// Caso de uso que ejecuta el respaldo (y cuenta los existentes).
  final Respaldos respaldos;

  Timer? _timer;
  bool _enCurso = false;

  /// Clave del ajuste con el intervalo en minutos (`0` = solo manual).
  static const String claveIntervalo = Ajustes.claveRespaldoIntervalo;

  /// Arranca la programación (llamado al servir) y devuelve los minutos que
  /// quedan para el próximo respaldo (`null` = apagado o BD no disponible).
  ///
  /// Un fallo aquí solo deja el respaldo automático sin programar: nunca
  /// debe impedir que el servidor arranque.
  Future<int?> iniciar() async {
    try {
      return await reprogramar();
    } catch (error) {
      stderr.writeln('No se pudo programar el respaldo automático: $error');
      return null;
    }
  }

  /// Cancela el temporizador (llamado al parar el servidor).
  void detener() {
    _timer?.cancel();
    _timer = null;
  }

  /// Recalcula el próximo disparo. Se llama al arrancar, al terminar cada
  /// respaldo y tras guardar los ajustes.
  Future<int?> reprogramar() async {
    _timer?.cancel();
    _timer = null;

    final minutos = await _intervalo();
    if (minutos == null || minutos <= 0) return null;

    final pendientes = await _minutosHastaElProximo(minutos);
    _timer = Timer(Duration(minutes: pendientes), _ejecutar);
    return pendientes;
  }

  /// Intervalo configurado en minutos, o `null` si está sin configurar o la
  /// BD no responde (arranque degradado): sin intervalo no hay automático.
  Future<int?> _intervalo() async {
    try {
      final items = await ajustes.listar();
      for (final item in items) {
        if (item.clave == claveIntervalo) {
          return int.tryParse(item.valor.trim());
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Minutos que faltan para que se cumpla el intervalo desde el último
  /// respaldo; si aún no hay ninguno, desde el arranque. Nunca menos de 1:
  /// un `Timer` de 0 dispararía en el siguiente ciclo del bucle de eventos.
  Future<int> _minutosHastaElProximo(int minutos) async {
    final ultimo = respaldos.ultimo();
    if (ultimo == null) return minutos;
    final transcurridos = DateTime.now().difference(ultimo.creado).inMinutes;
    return (minutos - transcurridos).clamp(1, minutos);
  }

  /// Dispara el respaldo automático.
  ///
  /// Cualquier fallo se anota en `stderr` y se vuelve a programar: un
  /// `pg_dump` que falla no puede tumbar el servidor ni dejar el programador
  /// muerto.
  Future<void> _ejecutar() async {
    if (_enCurso) return;
    _enCurso = true;
    try {
      final creado = await respaldos.respaldar();
      stdout.writeln('Respaldo automático creado: ${creado.nombre}');
    } catch (error) {
      stderr.writeln('Respaldo automático fallido: $error');
    } finally {
      _enCurso = false;
      await reprogramar();
    }
  }
}
