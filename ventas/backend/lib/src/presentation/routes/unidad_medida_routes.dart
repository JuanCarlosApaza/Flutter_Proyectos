import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/usecases/unidad_medida_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas del catálogo de unidades de medida:
///
/// * `GET/POST    /api/v1/unidades`
/// * `GET/PUT/DEL /api/v1/unidades/{id}`
///
/// El módulo (`unidades`) es el 13º de la app: su permiso nació en la
/// migración `017_unidades_medida`. Las rutas solo traducen HTTP <-> casos de
/// uso: nunca hacen SQL ni contienen reglas de negocio.
void addUnidadMedidaRoutes(Router router, {required Unidades unidades}) {
  router
    ..get('/api/v1/unidades', (Request request) async {
      asegurarPermiso(request, 'unidades', 'ver');
      final page = paginationOf(request);
      final q = queryOrNull(request, 'q', maxLength: 100);
      final estado = queryOrNull(request, 'estado');
      final total = await unidades.contar(estado: estado, q: q);
      final items = await unidades.listar(
        limit: page.limit,
        offset: page.offset,
        estado: estado,
        q: q,
      );
      return listJsonResponse(
        items.map((e) => e.toJson()).toList(),
        total: total,
        limit: page.limit,
        offset: page.offset,
      );
    })
    ..get('/api/v1/unidades/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'unidades', 'ver');
      final item = await unidades.obtener(pathId(id));
      return jsonResponse(200, item.toJson());
    })
    ..post('/api/v1/unidades', (Request request) async {
      asegurarPermiso(request, 'unidades', 'crear');
      final body = await readJsonObject(request);
      final fields = readUnidad(body);
      detalleRegistro(request, nombre: fields.nombre);
      final item = await unidades.crear(
        codigo: fields.codigo,
        nombre: fields.nombre,
        tipo: fields.tipo,
        decimales: fields.decimales,
        estado: fields.estado,
      );
      return jsonResponse(201, item.toJson());
    })
    ..put('/api/v1/unidades/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'unidades', 'editar');
      final body = await readJsonObject(request);
      final fields = readUnidadParcial(body);
      final antes = await unidades.obtener(pathId(id));
      detalleRegistro(
        request,
        nombre: antes.toJson()['nombre']?.toString(),
        antes: antes.toJson(),
        despues: body,
        campos: camposEnviados(body, const [
          'codigo',
          'nombre',
          'tipo',
          'decimales',
          'estado',
        ]),
      );
      final item = await unidades.actualizar(
        pathId(id),
        codigo: fields.codigo,
        nombre: fields.nombre,
        tipo: fields.tipo,
        decimales: fields.decimales,
        estado: fields.estado,
      );
      return jsonResponse(200, item.toJson());
    })
    ..delete('/api/v1/unidades/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'unidades', 'eliminar');
      final antes = await unidades.obtener(pathId(id));
      detalleRegistro(request, nombre: antes.toJson()['nombre']?.toString());
      await unidades.eliminar(pathId(id));
      return noContent();
    });
}

/// Extrae los campos de un cuerpo de **creación**: `codigo` y `nombre`
/// obligatorios; el resto con su valor por defecto (la capa `domain/` vuelve
/// a validar todo contra las reglas del negocio).
({String codigo, String nombre, String tipo, int decimales, String estado})
readUnidad(Map<String, Object?> body) => (
  codigo: requireText(body, 'codigo', maxLength: 10),
  nombre: requireText(body, 'nombre', maxLength: 50),
  tipo: textOrNull(body, 'tipo') ?? 'UNIDAD',
  decimales: intOrNull(body, 'decimales') ?? 0,
  estado: textOrNull(body, 'estado') ?? 'ACTIVO',
);

/// Extrae los campos de un cuerpo de **actualización parcial**: lo que no
/// venga en el cuerpo no se modifica (`null` conserva el valor vigente).
///
/// El `codigo` se puede enviar igual que los demás — quien decide si admite
/// cambios es el caso de uso (`Unidades.actualizar`).
({String? codigo, String? nombre, String? tipo, int? decimales, String? estado})
readUnidadParcial(Map<String, Object?> body) {
  final campos = camposEnviados(body, const [
    'codigo',
    'nombre',
    'tipo',
    'decimales',
    'estado',
  ]);
  ensureHayCampos(campos);
  return (
    codigo: campos.contains('codigo')
        ? requireText(body, 'codigo', maxLength: 10)
        : null,
    nombre: campos.contains('nombre')
        ? requireText(body, 'nombre', maxLength: 50)
        : null,
    // `tipo: null` explícito en el cuerpo no lo fuerza a `UNIDAD`: en una
    // actualización parcial, null significa «no tocar».
    tipo: campos.contains('tipo') ? textOrNull(body, 'tipo') : null,
    decimales: campos.contains('decimales')
        ? intOrNull(body, 'decimales')
        : null,
    estado: textOrNull(body, 'estado'),
  );
}
