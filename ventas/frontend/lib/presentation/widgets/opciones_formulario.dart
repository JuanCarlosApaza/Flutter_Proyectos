/// Opciones compartidas de los campos desplegable de los formularios.
///
/// Estas listas estaban escritas a mano en cada página (productos, usuarios,
/// categorías, proveedores, fichas de persona), con el riesgo de que una
/// actualización llegara a unas sí y a otras no. Aquí vive **una sola copia**
/// y las pantallas las comparten —el mismo criterio que ya seguían
/// `tiposPago` y `ordenesCatalogo`.
///
/// La vista «Ajustes» también las usa para pintar los desplegables de
/// **valor por defecto** (ver `Ajustes.defecto...`), de modo que las opciones
/// que se pueden elegir como arranque son exactamente las del formulario.
library;

import 'package:flutter/widgets.dart';

import '../../core/widgets/ajustes_scope.dart';
import '../../domain/entities/recurso.dart';
import 'recurso_form.dart';

/// `estado` de un producto (`productos_page`).
const List<Opccion> estadosProducto = [
  Opccion('DISPONIBLE', 'Disponible'),
  Opccion('AGOTADO', 'Agotado'),
  Opccion('POR_VENCER', 'Por vencer'),
  Opccion('DESCONTINUADO', 'Descontinuado'),
];

/// `estado` del genérico `estado_general`: usuarios, clientes, proveedores,
/// categorías y presentaciones.
const List<Opccion> estadosGenerales = [
  Opccion('ACTIVO', 'Activo'),
  Opccion('INACTIVO', 'Inactivo'),
  Opccion('BLOQUEADO', 'Bloqueado'),
];

/// `estado` de un empleado (`estado_empleado`): añade vacaciones y licencia.
const List<Opccion> estadosEmpleados = [
  Opccion('ACTIVO', 'Activo'),
  Opccion('VACACIONES', 'Vacaciones'),
  Opccion('LICENCIA', 'Licencia'),
  Opccion('INACTIVO', 'Inactivo'),
];

/// `genero` de una persona (ficha de cliente).
const List<Opccion> generos = [
  Opccion('M', 'Masculino'),
  Opccion('F', 'Femenino'),
  Opccion('O', 'Otro'),
];

/// `tipo` de una unidad de medida (`unidades_medida.tipo`, migración
/// 017). `PESO` y `VOLUMEN` se fraccionan; `UNIDAD` se cuenta por envase.
const List<Opccion> tiposUnidad = [
  Opccion('PESO', 'Peso (KG, LB, ONZA)'),
  Opccion('VOLUMEN', 'Volumen (LT, ML)'),
  Opccion('UNIDAD', 'Unidad o envase (UN, CAJA)'),
];

/// Unidad de venta de un producto (`productos.unidad`).
///
/// Es la misma unidad del `stock` y de la cantidad de una línea de venta, de
/// modo que «1.450 KG» se lee igual en la ficha y en la factura.
///
/// **Respaldo, no fuente**: desde la migración `017_unidades_medida` las
/// unidades válidas las decide la tabla `unidades_medida` (pantalla
/// «Unidades»), y el formulario de producto y el carrito leen el catálogo
/// (`UnidadesController`). Esta lista fija solo pinta el desplegable
/// mientras ese catálogo no está cargado (p. ej. sin sesión o con la API
/// caída), para que un producto se pueda seguir guardando.
const List<Opccion> unidadesVenta = [
  Opccion('UN', 'Unidad (UN)'),
  Opccion('KG', 'Kilogramo (KG)'),
  Opccion('GR', 'Gramo (GR)'),
  Opccion('LT', 'Litro (LT)'),
  Opccion('ML', 'Mililitro (ML)'),
  Opccion('CAJA', 'Caja (CAJA)'),
  Opccion('BLISTER', 'Blister (BLISTER)'),
  Opccion('FRASCO', 'Frasco (FRASCO)'),
  Opccion('SOBRE', 'Sobre (SOBRE)'),
];

/// Opciones del desplegable «Unidad de venta» a partir del **catálogo de la
/// BD** (`UnidadesController.items`, tabla `unidades_medida`), ordenadas
/// como el listado de la pantalla «Unidades»: por tipo y código.
///
/// El `valor` de cada opción es el `codigo` (lo que viaja en
/// `productos.unidad`), no el id de la fila.
List<Opccion> unidadesDe(List<Recurso> items) {
  final unidades = [
    for (final item in items)
      if (item.texto('codigo', vacio: '').isNotEmpty) item,
  ];
  unidades.sort((a, b) {
    final porTipo = a.texto('tipo').compareTo(b.texto('tipo'));
    if (porTipo != 0) return porTipo;
    return a.texto('codigo').compareTo(b.texto('codigo'));
  });
  return [
    for (final item in unidades)
      Opccion(
        item.texto('codigo'),
        '${item.texto('nombre')} (${item.texto('codigo')})',
      ),
  ];
}

/// Valores iniciales de un **alta**: lo que cada campo opción arranca con
/// según los ajustes `defecto.<entidad>.<campo>`.
///
/// Es el único punto donde se aplican: `RecursoContenido` (los formularios de
/// los módulos) y `altaPersona` (el alta rápida desde la caja) la llaman al
/// crear, de modo que cada desplegable tiene una sola fuente de verdad.
///
/// Solo se incluyen los campos con ajuste **no vacío**; un `''` («— Sin valor
/// por defecto —») deja el campo fuera del mapa, así que arranca vacío y, si
/// es obligatorio, la validación del formulario pide elegirlo. Los campos de
/// `TipoCampo.opcion` con `opcionesDinamicas` también entran: su valor es el
/// `id` del registro elegido.
///
/// [entidad] es la `entidad` de la página (`'producto'`, `'categoría'`…): se
/// pasa tal cual y aquí se convierte a slug, de modo que quien llama no tiene
/// que acordarse de normalizarla.
Map<String, Object?> defectosDeAlta(
  BuildContext context, {
  required String entidad,
  required List<CampoFormulario> campos,
}) {
  final ajustes = AjustesScope.de(context);
  final slug = Ajustes.slugEntidad(entidad);
  final valores = <String, Object?>{};

  for (final campo in campos) {
    if (campo.tipo != TipoCampo.opcion) continue;
    final valor = ajustes.valor(Ajustes.claveDefecto(slug, campo.clave));
    if (valor.isNotEmpty) valores[campo.clave] = valor;
  }

  return valores;
}
