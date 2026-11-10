import 'dart:typed_data';

import '../../core/network/api_client.dart';
import '../../core/storage/guardar_fichero.dart';
import '../../domain/usecases/crud.dart';
import 'recurso_controller.dart';

/// Respaldos de la base de datos (sección «Respaldos» de la vista Ajustes).
///
/// Hereda el CRUD genérico: `cargar()`/`recargar()` sirven el listado de la
/// carpeta del servidor y `crear()` dispara `POST /respaldos` (pg_dump) y
/// vuelve a pedir la lista. Lo único propio es la descarga, que necesita los
/// **bytes** del `.dump` y por eso no puede ir por el `Crud` (que solo
/// habla JSON).
final class RespaldosController extends RecursoController {
  RespaldosController(Crud crud, this.api) : super(crud, 'respaldos');

  final ApiClient api;

  /// Genera un respaldo ahora y recarga el listado.
  Future<void> respaldar() => crear(const {});

  /// Descarga el respaldo [nombre] al equipo de quien lo pide.
  Future<void> descargar(String nombre) async {
    final bytes = await api.getBytes('/api/v1/respaldos/$nombre/descarga');
    await guardarFichero(Uint8List.fromList(bytes), nombre);
  }
}
