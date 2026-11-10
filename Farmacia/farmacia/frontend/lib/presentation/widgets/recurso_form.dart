import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors/failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/alertas.dart';
import '../../domain/entities/recurso.dart';
import 'campo_imagen.dart';
import 'desplegable_buscable.dart';
import 'recurso_tabla.dart';

/// Tipo de dato de un campo del formulario.
enum TipoCampo { texto, numero, decimal, fecha, opcion, clave, imagen }

/// Opción de un campo desplegable (`valor` = lo que viaja a la API).
final class Opccion {
  const Opccion(this.valor, this.etiqueta, {this.imagen});

  final String valor;
  final String etiqueta;

  /// Ruta de la imagen del registro (opcional): el selector la pinta como
  /// miniatura delante de la etiqueta —p. ej. los productos al escogerlos—.
  final String? imagen;
}

/// Opciones de un listado de recursos (`id` → `nombre`), ordenadas.
///
/// Las personas (clientes, empleados) se etiquetan con su nombre completo
/// (`nombreCompletoDe`); el resto de recursos, con su `nombre`.
///
/// [conImagen] adjunta la ruta `imagen` de cada registro para que el
/// desplegable muestre la miniatura junto al nombre.
List<Opccion> opcionesDe(List<Recurso> items, {bool conImagen = false}) {
  final opciones = [
    for (final item in items)
      Opccion(
        '${item.id}',
        nombreCompletoDe(item),
        imagen: conImagen ? item.texto('imagen', vacio: '') : null,
      ),
  ];
  opciones.sort((a, b) => a.etiqueta.compareTo(b.etiqueta));
  return opciones;
}

/// Tipos de pago admitidos: los usa el carrito, «Nueva Orden» y el
/// desplegable «Tipo de pago por defecto» de la vista «Ajustes» (una sola
/// lista para que las tres pantallas hablen siempre igual).
const List<Opccion> tiposPago = [
  Opccion('EFECTIVO', 'Efectivo'),
  Opccion('QR', 'QR'),
  Opccion('TARJETA', 'Tarjeta'),
  Opccion('YAPE', 'Yape'),
  Opccion('PLIN', 'Plin'),
  Opccion('TRANSFERENCIA', 'Transferencia'),
];

/// Métodos que el cobro ofrece hoy: **solo Efectivo y QR** (los demás
/// siguen siendo válidos en órdenes antiguas y en el backend).
const List<Opccion> metodosCobro = [
  Opccion('EFECTIVO', 'Efectivo'),
  Opccion('QR', 'QR'),
];

/// ¿Este empleado puede vender? La función la define el **rol** de la
/// cuenta vinculada (`usuarios` → `roles`), así que se comprueba el
/// permiso `ventas.crear` que ese rol tiene (no un texto libre).
bool esVendedor(Recurso empleado) {
  final permisos = empleado['permisos'];
  return permisos is List && permisos.contains('ventas.crear');
}

/// Empleados para el desplegable de **vendedor**: solo los cuyo rol permite
/// crear ventas, más [sesion] (el de la cuenta conectada) por si su rol no
/// aparece.
///
/// La segunda parte es el invariante del selector: el vendedor por defecto
/// nunca puede quedar fuera de sus propias opciones.
List<Recurso> vendedoresDe(List<Recurso> empleados, {int? sesion}) => [
  for (final empleado in empleados)
    if (esVendedor(empleado) || empleado.id == sesion) empleado,
];

/// Definición de un campo del formulario (y de su etiqueta en la tabla).
final class CampoFormulario {
  const CampoFormulario({
    required this.clave,
    required this.etiqueta,
    this.tipo = TipoCampo.texto,
    this.obligatorio = false,
    this.obligatorioSoloCreacion = false,
    this.soloEnCreacion = false,
    this.omitirSiVacio = false,
    this.opciones,
    this.opcionesDinamicas,
    this.auxiliar,
    this.onCrear,
    this.onAlta,
    this.etiquetaCrear,
    this.maximasLineas = 1,
    this.min,
    this.max,
    this.minCaracteres,
    this.maxCaracteres,
    this.patron,
    this.mensajePatron,
    this.soloDigitos = false,
    this.minFecha,
    this.maxFecha,
    this.validador,
  });

  /// Clave del JSON (también la etiqueta por defecto de la tarjeta mobile).
  final String clave;

  final String etiqueta;
  final TipoCampo tipo;

  /// Siempre obligatorio.
  final bool obligatorio;

  /// Obligatorio solo al crear (p. ej. la contraseña de un usuario).
  final bool obligatorioSoloCreacion;

  /// El campo solo aparece en el alta; al editar (y en el detalle) se omite.
  /// Útil para campos con flujo propio, como la contraseña de un usuario
  /// (se cambia con el botón «Restablecer contraseña», no en la ficha).
  final bool soloEnCreacion;

  /// Si viene vacío la clave no se envía (no se borra el valor en la API).
  final bool omitirSiVacio;

  /// Opciones fijas del desplegable.
  final List<Opccion>? opciones;

  /// Opciones resueltas en tiempo de ejecución (p. ej. desde otro controller).
  final List<Opccion> Function()? opcionesDinamicas;

  /// Etiqueta del botón para **crear una opción sobre la marcha** (p. ej.
  /// «Nueva categoría»). Hay dos accesos al mismo diálogo: el botón «+» que
  /// se pinta **al lado del desplegable** y el botón del final de la propia
  /// hoja de opciones («busco y no está → la creo aquí»).
  final String? etiquetaCrear;

  /// Crea la opción con el [nombre] escrito y devuelve su valor (el id en
  /// texto) para **seleccionarlo al instante**; `null` si no hay que
  /// seleccionar nada. Debe recargar las opciones antes de devolver (lo hace
  /// el CRUD del controlador en `crear`).
  final Future<String?> Function(String nombre)? onCrear;

  /// Flujo de alta **completo** que sustituye al diálogo de solo nombre de
  /// [onCrear]: aquí va el propio diálogo (todos los campos de la ficha) y
  /// devuelve el valor a seleccionar, `null` si se cancela. Es el patrón de
  /// «Nuevo cliente» (caja y Ventas) y «Nuevo empleado» (Usuarios), donde
  /// hace falta más que un nombre (ver `alta_persona.dart`).
  ///
  /// Solo uno de los dos puede venir: si hay `onAlta`, no se pide el nombre.
  final Future<String?> Function()? onAlta;

  /// Texto de ayuda bajo el campo.
  final String? auxiliar;

  final int maximasLineas;

  /// Límites numéricos para `numero`/`decimal` (`min` incluido).
  ///
  /// El tope del backend es 99 999 999.99 (`NUMERIC(10, 2)`), así que un
  /// importe que no cabe se rechaza aquí antes de viajar a la API.
  final double? min;
  final double? max;

  /// Longitud del texto (los mismos `maxLength` que aplica el backend).
  final int? minCaracteres;
  final int? maxCaracteres;

  /// Forma que debe cumplir el valor completo (p. ej. `^\d{7,15}$` en el CI).
  final RegExp? patron;

  /// Mensaje propio para [patron] (por defecto `Formato no válido`).
  final String? mensajePatron;

  /// Si solo admite dígitos: teclado numérico y filtro de entrada.
  final bool soloDigitos;

  /// Rango de fechas admitido en `TipoCampo.fecha`.
  final DateTime? minFecha;
  final DateTime? maxFecha;

  /// Regla adicional escrita a mano (p. ej. un teléfono con 6-15 dígitos).
  /// Devuelve `null` cuando el valor es válido.
  final String? Function(String valor)? validador;
}

/// Formulario de bottom sheet: título + campos + Cancelar/Crear.
///
/// Devuelve `true` por el `Navigator` cuando el envío termina bien.
///
/// Con [soloLectura] se convierte en la **vista de detalle**: mismos campos
/// y mismas etiquetas que la edición, pero deshabilitados y con un único
/// botón "Cerrar" (no se envía nada a la API).
class RecursoForm extends StatefulWidget {
  const RecursoForm({
    super.key,
    required this.titulo,
    required this.campos,
    required this.valores,
    this.onSubmit,
    this.esEdicion = false,
    this.etiquetaGuardar = 'Guardar',
    this.soloLectura = false,
    this.validar,
  });

  final String titulo;
  final List<CampoFormulario> campos;

  /// Valores iniciales (el JSON del recurso en edición, vacío al crear).
  final Map<String, Object?> valores;

  /// Envío del formulario. No se usa (ni es necesario) en modo solo lectura.
  final Future<void> Function(Map<String, Object?> body)? onSubmit;
  final bool esEdicion;
  final String etiquetaGuardar;

  /// `true` para la vista de detalle: campos deshabilitados y "Cerrar".
  final bool soloLectura;

  /// Validación **entre campos**, posterior a la de cada campo (p. ej.
  /// "el precio de venta no puede ser menor al de compra").
  ///
  /// Devuelve `null` si todo está bien o el mensaje de error a mostrar.
  final String? Function(Map<String, Object?> valores)? validar;

  @override
  State<RecursoForm> createState() => _RecursoFormState();
}

class _RecursoFormState extends State<RecursoForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controladores;
  final Map<String, String?> _selecciones = {};

  /// Revisiones de los desplegables que han creado una opción en línea.
  ///
  /// Un `FormField` solo toma `initialValue` al montarse (no lo sincroniza
  /// después), así que al crear una opción se sube la revisión para que la
  /// clave del campo cambie y se recree con el id nuevo: sin esto, el
  /// selector se quedaría mostrando el valor anterior.
  final Map<String, int> _revisiones = {};
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _controladores = {
      for (final campo in widget.campos)
        campo.clave: TextEditingController(
          text: _aTexto(widget.valores[campo.clave]),
        ),
    };
    for (final campo in widget.campos) {
      _selecciones[campo.clave] = _aTexto(widget.valores[campo.clave]);
      if (_selecciones[campo.clave]!.isEmpty) _selecciones[campo.clave] = null;
    }
  }

  static String _aTexto(Object? valor) {
    if (valor == null) return '';
    if (valor is double) {
      return valor == valor.roundToDouble()
          ? valor.toInt().toString()
          : valor.toString();
    }
    return valor.toString();
  }

  @override
  void dispose() {
    for (final controlador in _controladores.values) {
      controlador.dispose();
    }
    super.dispose();
  }

  bool _esRequerido(CampoFormulario campo) =>
      campo.obligatorio || (campo.obligatorioSoloCreacion && !widget.esEdicion);

  List<Opccion> _opciones(CampoFormulario campo) =>
      campo.opcionesDinamicas?.call() ?? campo.opciones ?? const [];

  String? _validar(CampoFormulario campo, String? valor) {
    final texto = (valor ?? '').trim();
    if (_esRequerido(campo) && texto.isEmpty) {
      return 'Este campo es obligatorio';
    }
    if (texto.isEmpty) return null;

    // --- Números: formato + rango (espejo de las reglas del backend) --------
    if (campo.tipo == TipoCampo.numero || campo.tipo == TipoCampo.decimal) {
      final double numero;
      if (campo.tipo == TipoCampo.numero) {
        final entero = int.tryParse(texto);
        if (entero == null) return 'Debe ser un número entero';
        numero = entero.toDouble();
      } else {
        final decimal = double.tryParse(texto);
        if (decimal == null || decimal.isNaN || decimal.isInfinite) {
          return 'Debe ser un número';
        }
        numero = decimal;
      }
      if (campo.min != null && numero < campo.min!) {
        return campo.min! <= 0
            ? 'No puede ser negativo'
            : 'Debe ser mayor o igual a ${_numero(campo.min!)}';
      }
      if (campo.max != null && numero > campo.max!) {
        return 'No puede superar ${_numero(campo.max!)}';
      }
      return campo.validador?.call(texto);
    }

    // --- Fechas: formato + no anterior/superior al rango permitido ----------
    if (campo.tipo == TipoCampo.fecha) {
      final fecha = DateTime.tryParse(texto);
      if (fecha == null) return 'Debe ser una fecha válida';
      final desde = campo.minFecha;
      if (desde != null && _soloFecha(fecha).isBefore(_soloFecha(desde))) {
        return 'No puede ser anterior a ${_corta(desde)}';
      }
      final hasta = campo.maxFecha;
      if (hasta != null && _soloFecha(fecha).isAfter(_soloFecha(hasta))) {
        return 'No puede ser posterior a ${_corta(hasta)}';
      }
      return campo.validador?.call(texto);
    }

    // --- Texto: longitud + forma + regla propia -----------------------------
    if (campo.maxCaracteres != null && texto.length > campo.maxCaracteres!) {
      return 'No puede superar ${campo.maxCaracteres} caracteres';
    }
    if (campo.minCaracteres != null && texto.length < campo.minCaracteres!) {
      return 'Debe tener al menos ${campo.minCaracteres} caracteres';
    }
    if (campo.patron != null && !campo.patron!.hasMatch(texto)) {
      return campo.mensajePatron ?? 'Formato no válido';
    }
    return campo.validador?.call(texto);
  }

  /// Formatea un límite numérico sin ceros sobrantes (`1`, `0.01`, `1e6`...).
  static String _numero(double valor) => valor == valor.roundToDouble()
      ? valor.toInt().toString()
      : valor.toString();

  static DateTime _soloFecha(DateTime fecha) =>
      DateTime(fecha.year, fecha.month, fecha.day);

  static String _corta(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';

  /// Filtros de entrada: dígitos, decimales con 2 cifras y longitud máxima.
  ///
  /// Evitan escribir lo que el backend va a rechazar (p. ej. `1.5` en stock
  /// o un importe de 5 decimales).
  static List<TextInputFormatter>? _filtros(CampoFormulario campo) {
    final filtros = <TextInputFormatter>[];
    if (campo.soloDigitos || campo.tipo == TipoCampo.numero) {
      filtros.add(FilteringTextInputFormatter.digitsOnly);
    } else if (campo.tipo == TipoCampo.decimal) {
      filtros.add(
        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}(\.\d{0,2})?')),
      );
    }
    if (campo.maxCaracteres != null) {
      filtros.add(LengthLimitingTextInputFormatter(campo.maxCaracteres));
    }
    return filtros.isEmpty ? null : filtros;
  }

  Future<void> _guardar() async {
    // En modo detalle no hay nada que enviar.
    final enviar = widget.onSubmit;
    if (enviar == null || widget.soloLectura) return;

    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final cuerpo = <String, Object?>{};
    for (final campo in widget.campos) {
      final crudo = campo.tipo == TipoCampo.opcion
          ? (_selecciones[campo.clave] ?? '')
          : _controladores[campo.clave]!.text.trim();

      if (crudo.isEmpty) {
        // `omitirSiVacio` deja el valor intacto (p. ej. contraseña).
        if (!campo.omitirSiVacio) cuerpo[campo.clave] = null;
        continue;
      }

      cuerpo[campo.clave] = switch (campo.tipo) {
        TipoCampo.numero => int.tryParse(crudo) ?? crudo,
        TipoCampo.decimal => double.tryParse(crudo) ?? crudo,
        _ => crudo,
      };
    }

    // Reglas entre campos (p. ej. precio de venta >= precio de compra).
    final errorGlobal = widget.validar?.call(cuerpo);
    if (errorGlobal != null) {
      if (mounted) {
        await alertaAdvertencia(
          context,
          titulo: 'Revisa el formulario',
          mensaje: errorGlobal,
        );
      }
      return;
    }

    setState(() => _enviando = true);

    try {
      await enviar(cuerpo);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _enviando = false);
      await alertaError(
        context,
        mensaje: error is Failure
            ? error.message
            : 'Error inesperado al guardar',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.titulo,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              for (final campo in widget.campos) ...[
                _construirCampo(campo),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              if (widget.soloLectura)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.cardBorder),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cerrar',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _enviando
                            ? null
                            : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.cardBorder),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _enviando ? null : _guardar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _enviando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(widget.etiquetaGuardar),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirCampo(CampoFormulario campo) {
    switch (campo.tipo) {
      case TipoCampo.opcion:
        return _desplegable(campo);
      case TipoCampo.fecha:
        return _fecha(campo);
      case TipoCampo.imagen:
        return _imagen(campo);
      case TipoCampo.texto:
      case TipoCampo.numero:
      case TipoCampo.decimal:
      case TipoCampo.clave:
        return _texto(campo);
    }
  }

  /// Campo de imagen: sube el fichero al backend y guarda su **ruta**.
  ///
  /// Se monta como [FormField] para que la validación (`obligatorio`, número,
  /// etc.) siga funcionando con el resto del formulario.
  Widget _imagen(CampoFormulario campo) {
    final controlador = _controladores[campo.clave]!;
    return FormField<String>(
      initialValue: controlador.text,
      validator: (valor) => _validar(campo, valor),
      builder: (estado) {
        return SubidorImagen(
          valor: estado.value ?? '',
          etiqueta: campo.etiqueta,
          auxiliar: estado.errorText ?? campo.auxiliar,
          tieneError: estado.hasError,
          soloLectura: widget.soloLectura,
          onSubido: (ruta) {
            controlador.text = ruta;
            estado.didChange(ruta);
            setState(() {});
          },
          onQuitar: () {
            controlador.text = '';
            estado.didChange('');
            setState(() {});
          },
        );
      },
    );
  }

  Widget _texto(CampoFormulario campo) {
    final esClave = campo.tipo == TipoCampo.clave;
    return TextFormField(
      controller: _controladores[campo.clave],
      // Vista de detalle: sin foco ni teclado, solo lectura visual.
      enabled: !widget.soloLectura,
      obscureText: esClave,
      maxLines: esClave ? 1 : campo.maximasLineas,
      keyboardType: campo.soloDigitos
          ? TextInputType.number
          : campo.tipo == TipoCampo.numero
          ? TextInputType.number
          : campo.tipo == TipoCampo.decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: esClave ? null : _filtros(campo),
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: _decoracion(campo.etiqueta, campo.auxiliar),
      validator: widget.soloLectura ? null : (valor) => _validar(campo, valor),
    );
  }

  Widget _fecha(CampoFormulario campo) {
    final controlador = _controladores[campo.clave]!;
    return TextFormField(
      controller: controlador,
      readOnly: true,
      enabled: !widget.soloLectura,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: _decoracion(campo.etiqueta, campo.auxiliar).copyWith(
        suffixIcon: widget.soloLectura
            ? null
            : const Icon(Icons.calendar_today_outlined, size: 18),
      ),
      onTap: widget.soloLectura
          ? null
          : () async {
              final hoy = _soloFecha(DateTime.now());
              final desde = campo.minFecha == null
                  ? DateTime(hoy.year - 20)
                  : _soloFecha(campo.minFecha!);
              final hasta = campo.maxFecha == null
                  ? DateTime(hoy.year + 20)
                  : _soloFecha(campo.maxFecha!);
              final guardada = DateTime.tryParse(controlador.text);
              var inicial = guardada == null ? hoy : _soloFecha(guardada);
              if (inicial.isBefore(desde)) inicial = desde;
              if (inicial.isAfter(hasta)) inicial = hasta;
              final seleccion = await showDatePicker(
                context: context,
                initialDate: inicial,
                firstDate: desde,
                lastDate: hasta,
              );
              if (seleccion == null) return;
              controlador.text = _corta(seleccion);
            },
      validator: widget.soloLectura ? null : (valor) => _validar(campo, valor),
    );
  }

  Widget _desplegable(CampoFormulario campo) {
    var opciones = List<Opccion>.from(_opciones(campo));
    var valor = _selecciones[campo.clave];

    // Si el valor actual no está en la opción cargada, se conserva a mano
    // para que el selector no quede con un valor fuera de sus opciones.
    if (valor != null &&
        valor.isNotEmpty &&
        !opciones.any((o) => o.valor == valor)) {
      opciones = [...opciones, Opccion(valor, valor)];
    }

    // Con buscador: las opciones de un módulo (categorías, empleados…) pueden
    // ser muchas y escribir es más rápido que recorrer la lista.
    final desplegable = DesplegableBuscable(
      // Clave con revisión: ver `_revisiones`.
      key: ValueKey('${campo.clave}#${_revisiones[campo.clave] ?? 0}'),
      initialValue: valor ?? (_esRequerido(campo) ? null : ''),
      opciones: [
        if (!_esRequerido(campo)) const Opccion('', '— Sin asignar —'),
        ...opciones,
      ],
      decoracion: _decoracion(campo.etiqueta, campo.auxiliar),
      validator: widget.soloLectura ? null : (valor) => _validar(campo, valor),
      // Vista de detalle: el desplegable queda fijo en el valor actual.
      habilitado: !widget.soloLectura,
      // Botón «crear opción sobre la marcha» (categorías, proveedores...).
      onCrear: widget.soloLectura ? null : campo.onCrear,
      onAlta: widget.soloLectura ? null : campo.onAlta,
      etiquetaCrear: campo.etiquetaCrear,
      onChanged: widget.soloLectura
          ? null
          : (valor) => setState(() => _selecciones[campo.clave] = valor),
    );

    // El «+» va **al lado** del campo: sin abrir el desplegable ya se ve que
    // se puede crear la categoría/presentación/proveedor que falta.
    if ((campo.onCrear == null && campo.onAlta == null) ||
        campo.etiquetaCrear == null ||
        widget.soloLectura) {
      return desplegable;
    }
    return Row(
      children: [
        Expanded(child: desplegable),
        const SizedBox(width: 4),
        IconButton(
          tooltip: campo.etiquetaCrear,
          onPressed: () => _crearOpcion(campo),
          icon: const Icon(
            Icons.add_circle_outline,
            size: 24,
            color: AppColors.brandGreen,
          ),
        ),
      ],
    );
  }

  /// Pide el nombre, crea la opción con [CampoFormulario.onCrear] y deja el
  /// desplegable con el registro recién creado ya seleccionado.
  ///
  /// Con [CampoFormulario.onAlta] no se pide nada: el flujo de alta trae su
  /// propio diálogo y devuelve directamente el valor a seleccionar.
  ///
  /// El listado de opciones se refresca solo: `RecursoController.crear`
  /// recarga antes de devolver, y el `setState` vuelve a pintar el campo con
  /// las opciones nuevas.
  Future<void> _crearOpcion(CampoFormulario campo) async {
    final altaPropia = campo.onAlta;
    if (altaPropia != null) {
      try {
        final nuevoValor = await altaPropia();
        if (nuevoValor == null || !mounted) return;
        setState(() {
          _revisiones[campo.clave] = (_revisiones[campo.clave] ?? 0) + 1;
          _selecciones[campo.clave] = nuevoValor;
        });
      } on Failure catch (failure) {
        if (!mounted) return;
        await alertaError(context, mensaje: failure.message);
      } catch (_) {
        if (!mounted) return;
        await alertaError(context, mensaje: 'No se pudo crear la opción.');
      }
      return;
    }

    final crear = campo.onCrear;
    if (crear == null) return;

    final nombre = await pedirNombreAlta(context, titulo: campo.etiquetaCrear!);
    if (nombre == null || !mounted) return;

    try {
      final nuevoValor = await crear(nombre);
      if (nuevoValor == null || !mounted) return;
      setState(() {
        _revisiones[campo.clave] = (_revisiones[campo.clave] ?? 0) + 1;
        _selecciones[campo.clave] = nuevoValor;
      });
    } on Failure catch (failure) {
      if (!mounted) return;
      await alertaError(context, mensaje: failure.message);
    } catch (_) {
      if (!mounted) return;
      await alertaError(context, mensaje: 'No se pudo crear «$nombre».');
    }
  }

  InputDecoration _decoracion(String label, [String? auxiliar]) {
    return InputDecoration(
      labelText: label,
      helperText: auxiliar,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      helperStyle: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.brandGreen),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
