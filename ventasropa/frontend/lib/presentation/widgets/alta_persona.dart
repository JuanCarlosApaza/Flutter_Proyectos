import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/validation/reglas.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/recurso_controller.dart';
import 'opciones_formulario.dart';
import 'recurso_form.dart';

/// Ficha de cliente y de empleado.
///
/// Es **la misma** lista de campos para el módulo (alta, edición y detalle:
/// `ClientesPage` y `EmpleadosPage`) y para el alta rápida desde la caja,
/// «Nueva Orden» o el formulario de Usuarios (`altaCliente` / `altaEmpleado`),
/// de modo que etiquetas, límites y validaciones nunca se descuelgan.
const List<CampoFormulario> camposCliente = [
  CampoFormulario(
    clave: 'nombre',
    etiqueta: 'Nombre *',
    obligatorio: true,
    minCaracteres: 2,
    maxCaracteres: 150,
  ),
  CampoFormulario(
    clave: 'apellido',
    etiqueta: 'Apellido *',
    obligatorio: true,
    minCaracteres: 2,
    maxCaracteres: 100,
  ),
  CampoFormulario(
    clave: 'ci',
    etiqueta: 'CI *',
    obligatorio: true,
    soloDigitos: true,
    maxCaracteres: 15,
    validador: ciValido,
    auxiliar: 'De 7 a 15 dígitos',
  ),
  CampoFormulario(
    clave: 'telefono',
    etiqueta: 'Teléfono',
    maxCaracteres: 20,
    validador: telefonoValido,
  ),
  CampoFormulario(clave: 'ciudad', etiqueta: 'Ciudad', maxCaracteres: 100),
  CampoFormulario(clave: 'direccion', etiqueta: 'Dirección', maxCaracteres: 200),
  CampoFormulario(
    clave: 'genero',
    etiqueta: 'Género',
    tipo: TipoCampo.opcion,
    opciones: generos,
  ),
  CampoFormulario(
    clave: 'estado',
    etiqueta: 'Estado *',
    tipo: TipoCampo.opcion,
    obligatorio: true,
    opciones: estadosGenerales,
  ),
];

const List<CampoFormulario> camposEmpleado = [
  CampoFormulario(
    clave: 'nombre',
    etiqueta: 'Nombre *',
    obligatorio: true,
    minCaracteres: 2,
    maxCaracteres: 150,
  ),
  CampoFormulario(
    clave: 'apellido',
    etiqueta: 'Apellido *',
    obligatorio: true,
    minCaracteres: 2,
    maxCaracteres: 100,
  ),
  CampoFormulario(
    clave: 'edad',
    etiqueta: 'Edad',
    tipo: TipoCampo.numero,
    min: 18,
    max: 120,
    auxiliar: 'Entre 18 y 120 años',
  ),
  CampoFormulario(clave: 'ciudad', etiqueta: 'Ciudad', maxCaracteres: 100),
  CampoFormulario(clave: 'direccion', etiqueta: 'Dirección', maxCaracteres: 200),
  CampoFormulario(
    clave: 'telefono',
    etiqueta: 'Teléfono',
    maxCaracteres: 20,
    validador: telefonoValido,
  ),
  CampoFormulario(
    clave: 'estado',
    etiqueta: 'Estado *',
    tipo: TipoCampo.opcion,
    obligatorio: true,
    opciones: estadosEmpleados,
  ),
];

/// Alta de un cliente con **todos sus datos** sin salir del formulario que
/// la pide (selector del carrito o de «Nueva Orden»).
///
/// Devuelve el registro creado —para que quien lo llamó lo sume a su lista
/// y lo deje elegido— o `null` si se canceló. El estado nace `ACTIVO`.
Future<Recurso?> altaCliente(
  BuildContext context, {
  required ClientesController clientes,
}) => _altaPersona(
  context,
  titulo: 'Nuevo cliente',
  entidad: 'cliente',
  campos: camposCliente,
  crear: clientes.crear,
);

/// Alta de un empleado con todos sus datos: el mismo flujo que [altaCliente]
/// (lo usa el botón «Nuevo empleado» del formulario de Usuarios).
Future<Recurso?> altaEmpleado(
  BuildContext context, {
  required EmpleadosController empleados,
}) => _altaPersona(
  context,
  titulo: 'Nuevo empleado',
  entidad: 'empleado',
  campos: camposEmpleado,
  crear: empleados.crear,
);

/// Hoja con la ficha vacía; al guardar, [crear] da de alta el registro y se
/// devuelve su `Recurso`. `RecursoForm` hace de formulario y de validación
/// (los mismos `campos` del módulo), así que aquí solo se orquesta.
///
/// [entidad] selecciona qué ajustes `defecto.<entidad>.<campo>` arrancan el
/// formulario (antes el estado nacía siempre `ACTIVO`; ahora manda lo que se
/// haya configurado en Ajustes, y si es «sin valor por defecto» el campo sale
/// vacío y la validación pide elegirlo).
Future<Recurso?> _altaPersona(
  BuildContext context, {
  required String titulo,
  required String entidad,
  required List<CampoFormulario> campos,
  required Future<Recurso> Function(Map<String, Object?> body) crear,
}) async {
  final valores = defectosDeAlta(context, entidad: entidad, campos: campos);
  Recurso? creado;
  final guardado = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => RecursoForm(
      titulo: titulo,
      campos: campos,
      valores: valores,
      etiquetaGuardar: 'Crear',
      onSubmit: (body) async => creado = await crear(body),
    ),
  );
  return guardado == true ? creado : null;
}
