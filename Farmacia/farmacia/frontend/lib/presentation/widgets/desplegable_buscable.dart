import 'package:flutter/material.dart';

import '../../core/errors/failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/alertas.dart';
import 'buscador_tabla.dart';
import 'imagen_recurso.dart';
import 'recurso_form.dart';

/// Desplegable con buscador.
///
/// Se pinta igual que `DropdownButtonFormField` (rótulo, auxiliar, borde y
/// error de validación) y lo sustituye en todos los desplegables del
/// proyecto: al pulsarlo abre una hoja con **la lista completa** y un campo
/// de texto para ir escribiendo y filtrar con el teclado (mayúsculas, acentos
/// y espacios dan igual, ver `normalizarTexto`).
///
/// El foco del campo se pide solo cuando hay más de ocho opciones: en listas
/// cortas la lista ya se ve entera y no conviene abrir el teclado.
///
/// La hoja se cierra al elegir una opción (o con `Intro`, que toma la
/// primera coincidencia); `onChanged` recibe el valor elegido.
class DesplegableBuscable extends FormField<String> {
  DesplegableBuscable({
    super.key,
    super.initialValue,
    super.validator,
    required List<Opccion> opciones,
    ValueChanged<String?>? onChanged,
    InputDecoration? decoracion,
    bool habilitado = true,
    TextStyle? estiloTexto,
    IconData icono = Icons.arrow_drop_down_rounded,
    this.onCrear,
    this.onAlta,
    this.etiquetaCrear,
  }) : super(
         enabled: habilitado,
         builder: (state) => _CampoConBuscador(
           state: state,
           opciones: opciones,
           habilitado: habilitado,
           onChanged: onChanged,
           decoracion: decoracion,
           estiloTexto: estiloTexto,
           icono: icono,
           onCrear: onCrear,
           onAlta: onAlta,
           etiquetaCrear: etiquetaCrear,
         ),
       );

  /// Crea una opción sobre la marcha (categoría, proveedor...): abre un
  /// diálogo con el nombre, crea el registro con [onCrear] y devuelve su
  /// valor para seleccionarlo. Ver `CampoFormulario.onCrear`.
  final Future<String?> Function(String nombre)? onCrear;

  /// Igual que [onCrear], pero con **flujo de alta propio**: aquí va el
  /// diálogo completo (todos los campos, p. ej. el alta de un cliente desde
  /// la caja) y devuelve el valor a seleccionar, `null` si se cancela. Si
  /// viene, no se pide el nombre. Ver `CampoFormulario.onAlta`.
  final Future<String?> Function()? onAlta;

  /// Etiqueta rozable del botón de creación (p. ej. «Nueva categoría»).
  final String? etiquetaCrear;
}

/// Diálogo con un campo para el nombre de una opción nueva (categoría,
/// presentación, proveedor…).
///
/// Devuelve el nombre recortado o `null` si se cancela. Es el mismo diálogo
/// para las dos vías de creación: el botón «+» al lado del desplegable (en
/// `RecursoForm`) y el botón del final de la hoja de opciones.
Future<String?> pedirNombreAlta(
  BuildContext context, {
  required String titulo,
}) async {
  final resultado = await showDialog<String>(
    context: context,
    builder: (ctx) => _DialogoNombre(titulo: titulo),
  );
  return (resultado == null || resultado.isEmpty) ? null : resultado;
}

/// Diálogo con un campo para el nombre de la nueva opción.
///
/// El controlador vive en **este** widget y se suelta en `dispose`: al cerrar
/// la ruta, `showDialog` devuelve antes de que termine su animación de salida,
/// y el `TextField` sigue repintándose (si se soltara al volver, se quedaría
/// con un controlador ya destruido).
class _DialogoNombre extends StatefulWidget {
  const _DialogoNombre({required this.titulo});

  final String titulo;

  @override
  State<_DialogoNombre> createState() => _DialogoNombreState();
}

class _DialogoNombreState extends State<_DialogoNombre> {
  final TextEditingController _controlador = TextEditingController();

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        controller: _controlador,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Nombre',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (texto) {
          final nombre = texto.trim();
          if (nombre.isNotEmpty) Navigator.pop(context, nombre);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () {
            final nombre = _controlador.text.trim();
            if (nombre.isNotEmpty) Navigator.pop(context, nombre);
          },
          child: const Text(
            'Crear',
            style: TextStyle(color: AppColors.brandGreen),
          ),
        ),
      ],
    );
  }
}

class _CampoConBuscador extends StatelessWidget {
  const _CampoConBuscador({
    required this.state,
    required this.opciones,
    required this.habilitado,
    required this.onChanged,
    required this.decoracion,
    required this.estiloTexto,
    required this.icono,
    this.onCrear,
    this.onAlta,
    this.etiquetaCrear,
  });

  final FormFieldState<String> state;
  final List<Opccion> opciones;
  final bool habilitado;
  final ValueChanged<String?>? onChanged;
  final InputDecoration? decoracion;
  final TextStyle? estiloTexto;
  final IconData icono;
  final Future<String?> Function(String nombre)? onCrear;
  final Future<String?> Function()? onAlta;
  final String? etiquetaCrear;

  /// Texto que se ve en el campo: la etiqueta del valor elegido (`null` o
  /// sin opción = campo vacío, solo se ve el rótulo).
  String get _etiquetaActual {
    final valor = state.value;
    if (valor == null) return '';
    for (final opcion in opciones) {
      if (opcion.valor == valor) return opcion.etiqueta;
    }
    return valor;
  }

  Future<void> _abrir() async {
    final elegido = await showModalBottomSheet<String>(
      context: state.context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _HojaDeOpciones(
        titulo: decoracion?.labelText,
        opciones: opciones,
        valor: state.value,
        onCrear: onCrear,
        onAlta: onAlta,
        etiquetaCrear: etiquetaCrear,
      ),
    );
    // La hoja puede haberse abierto y el formulario cerrarse a la vez:
    // sobre un `FormFieldState` desmontado no se toca nada.
    if (elegido == null || !state.mounted) return;
    state.didChange(elegido);
    onChanged?.call(elegido);
  }

  @override
  Widget build(BuildContext context) {
    final etiqueta = _etiquetaActual;
    // «— Sin asignar —» (valor '') se muestra atenuado, como en el
    // formulario genérico; un valor real, a color normal.
    final esSinAsignar = state.value == null || state.value!.isEmpty;

    // El `InkWell` envuelve el campo **entero** (rótulo, valor y auxiliar):
    // cualquier toque sobre el desplegable lo abre, no solo la línea del valor.
    return InkWell(
      onTap: habilitado ? _abrir : null,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: decoracion ?? const InputDecoration(),
        isEmpty: etiqueta.isEmpty,
        child: Row(
          children: [
            Expanded(
              child: Text(
                etiqueta,
                style:
                    estiloTexto ??
                    TextStyle(
                      fontSize: 14,
                      color: esSinAsignar
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // La flecha crece con el texto para no despeinar los selectores
            // compactos (p. ej. el de orden del catálogo).
            Icon(
              icono,
              size: (estiloTexto?.fontSize ?? 14) + 4,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja con las opciones del selector: campo de búsqueda arriba y la lista
/// filtrada debajo (sin desplazar el formulario que queda debajo).
class _HojaDeOpciones extends StatefulWidget {
  const _HojaDeOpciones({
    required this.titulo,
    required this.opciones,
    required this.valor,
    this.onCrear,
    this.onAlta,
    this.etiquetaCrear,
  });

  final String? titulo;
  final List<Opccion> opciones;
  final String? valor;
  final Future<String?> Function(String nombre)? onCrear;
  final Future<String?> Function()? onAlta;
  final String? etiquetaCrear;

  @override
  State<_HojaDeOpciones> createState() => _HojaDeOpcionesState();
}

class _HojaDeOpcionesState extends State<_HojaDeOpciones> {
  /// Texto escrito en el buscador (se normaliza al comparar).
  String _busqueda = '';

  List<Opccion> get _coincidencias {
    final consulta = normalizarTexto(_busqueda);
    if (consulta.isEmpty) return widget.opciones;
    return [
      for (final opcion in widget.opciones)
        if (normalizarTexto(opcion.etiqueta).contains(consulta) ||
            normalizarTexto(opcion.valor).contains(consulta))
          opcion,
    ];
  }

  void _elegir(Opccion opcion) => Navigator.pop(context, opcion.valor);

  @override
  Widget build(BuildContext context) {
    final coincidencias = _coincidencias;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        // El teclado del buscador no debe tapar la lista.
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (widget.titulo != null) ...[
            const SizedBox(height: 14),
            Text(
              widget.titulo!,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          BuscadorTabla(
            onChanged: (texto) => setState(() => _busqueda = texto),
            onBuscar: (texto) {
              if (coincidencias.isNotEmpty) _elegir(coincidencias.first);
            },
            autofocus: widget.opciones.length > 8,
            anchuraMaxima: double.infinity,
            textoAyuda: 'Escribe para buscar…',
          ),
          const SizedBox(height: 6),
          if (coincidencias.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Sin coincidencias para «$_busqueda»',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [for (final opcion in coincidencias) _fila(opcion)],
              ),
            ),
          // Crear opción sobre la marcha (categoría, proveedor, cliente...).
          if ((widget.onCrear != null || widget.onAlta != null) &&
              widget.etiquetaCrear != null) ...[
            const SizedBox(height: 6),
            _separador(),
            _botonCrear(),
          ],
        ],
      ),
    );
  }

  Widget _separador() =>
      const Divider(height: 1, thickness: 1, color: AppColors.cardBorder);

  /// Botón para crear una opción nueva sin salir del formulario.
  Widget _botonCrear() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: _crearNuevo,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(widget.etiquetaCrear!),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.brandGreen,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppColors.brandGreen),
            ),
          ),
        ),
      ),
    );
  }

  /// Crea la opción y la selecciona al instante.
  ///
  /// Dos vías: con [widget.onAlta] el flujo trae su **propio** diálogo (alta
  /// completa, p. ej. la de un cliente desde la caja) y devuelve el valor ya
  /// creado; con [widget.onCrear] se pide solo el nombre y se crea al vuelo.
  Future<void> _crearNuevo() async {
    final altaPropia = widget.onAlta;
    final invocable = widget.onCrear;
    if (altaPropia == null && invocable == null) return;

    String? nombre;
    String? nuevoValor;
    try {
      if (altaPropia != null) {
        nuevoValor = await altaPropia();
      } else {
        nombre = await pedirNombreAlta(
          context,
          titulo: widget.etiquetaCrear!,
        );
        if (nombre == null || !mounted) return;
        nuevoValor = await invocable!(nombre);
      }
    } on Failure catch (failure) {
      // La hoja sigue abierta: el error se enseña como en el resto de la app.
      if (!mounted) return;
      await alertaError(context, mensaje: failure.message);
      return;
    } catch (_) {
      if (!mounted) return;
      await alertaError(
        context,
        mensaje: nombre == null
            ? 'No se pudo crear el registro'
            : 'No se pudo crear «$nombre».',
      );
      return;
    }

    if (nuevoValor == null || !mounted) return;
    Navigator.pop(context, nuevoValor);
  }

  Widget _fila(Opccion opcion) {
    final elegida = opcion.valor == (widget.valor ?? '');
    return ListTile(
      dense: true,
      // Miniatura del registro cuando la opción la trae (productos): el
      // selector se ve con la foto, no solo el nombre.
      leading: opcion.imagen == null
          ? null
          : ImagenRecurso(ruta: opcion.imagen, tamano: 36, radio: 8),
      title: Text(
        opcion.etiqueta,
        style: TextStyle(
          fontSize: 14,
          fontWeight: elegida ? FontWeight.w600 : FontWeight.w400,
          color: elegida ? AppColors.brandGreen : AppColors.textPrimary,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: elegida
          ? const Icon(
              Icons.check_rounded,
              size: 18,
              color: AppColors.brandGreen,
            )
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: () => _elegir(opcion),
    );
  }
}
