import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/alertas.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/recurso_controller.dart';
import 'campo_imagen.dart';
import 'desplegable_buscable.dart';
import 'hojas_color.dart';
import 'recurso_tabla.dart';

/// Tipo de dato de un campo del formulario.
enum TipoCampo {
  texto,
  numero,
  decimal,
  fecha,
  opcion,
  clave,
  imagen,
  porcentaje,

  /// Muestra de color (`colores.codigoHex`): se elige de una paleta, sin
  /// teclear el hexadecimal. El valor que viaja es `#RRGGBB` o `null`.
  color,

  /// Filas `color · cantidad` de las variantes de un producto (migración
  /// 022): el valor que sale es una lista de mapas `colorId`/`cantidad`.
  variantes,
}

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

/// Pestaña de un formulario agrupado (p. ej. «Obligatorio» / «Opcional»).
///
/// Los campos se reparten con [CampoFormulario.pestana]. Las pestañas solo
/// organizan la vista: al guardar se validan **todas**, estén o no visibles
/// (si una pestaña oculta tiene un error, el formulario salta a ella).
final class PestanaFormulario {
  const PestanaFormulario(this.clave, this.etiqueta, {this.icono});

  /// Identificador que enlaza con [CampoFormulario.pestana].
  final String clave;

  /// Texto del botón de la pestaña.
  final String etiqueta;

  /// Icono opcional delante del texto.
  final IconData? icono;
}

/// Definición de un campo del formulario (y de su etiqueta en la tabla).
final class CampoFormulario {
  const CampoFormulario({
    required this.clave,
    required this.etiqueta,
    this.tipo = TipoCampo.texto,
    this.obligatorio = false,
    this.obligatorioSoloCreacion = false,
    this.soloEnCreacion = false,
    this.pestana,
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
    this.decimales = 2,
    this.minFecha,
    this.maxFecha,
    this.validador,
    this.porcentajeSobre,
    this.porcentajeDestino,
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

  /// Pestaña en la que se pinta el campo (ver [RecursoForm.pestanas]).
  /// `null` = sin pestaña: el campo se pinta bajo el selector y se ve
  /// siempre. Ignorado si el formulario no tiene pestañas.
  final String? pestana;

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

  /// Cifras decimales que deja escribir un campo `decimal` (2 = importes,
  /// 3 = cantidades y stock fraccionados de `NUMERIC(12, 3)`).
  final int decimales;

  /// Rango de fechas admitido en `TipoCampo.fecha`.
  final DateTime? minFecha;
  final DateTime? maxFecha;

  /// Regla adicional escrita a mano (p. ej. un teléfono con 6-15 dígitos).
  /// Devuelve `null` cuando el valor es válido.
  final String? Function(String valor)? validador;

  /// `TipoCampo.porcentaje`: clave del campo que sirve de **base** del
  /// cálculo (p. ej. `precioCompra`). Si está vacío o no es un número
  /// mayor que 0, el porcentaje no calcula nada.
  final String? porcentajeSobre;

  /// `TipoCampo.porcentaje`: clave del campo que se **recalcula** al
  /// escribir el porcentaje (p. ej. `precioVenta`). Sirve también para
  /// pintarlo en la misma fila y para reflejar en el porcentaje el margen
  /// real cuando el precio se escribe a mano.
  final String? porcentajeDestino;
}

/// Fila `color · cantidad` del editor de variantes de un producto.
///
/// El color siempre viene del catálogo (tiene id); la cantidad es el stock
/// de ESE color. Quitar la fila retira la variante; volver a agregarla
/// revive su fila original en el backend.
final class FilaVariante {
  FilaVariante({
    required this.colorId,
    required this.nombre,
    this.codigoHex,
    required this.cantidad,
  });

  final int colorId;
  final String nombre;

  /// Muestra `#RRGGBB` actual del catálogo (chip de la UI).
  final String? codigoHex;
  double cantidad;
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
    this.pestanas,
    this.validar,
  });

  final String titulo;
  final List<CampoFormulario> campos;

  /// Pestañas del formulario. `null` (por defecto) = un único bloque sin
  /// selector, como siempre. Con pestañas, cada campo se pinta en la suya
  /// ([CampoFormulario.pestana]) o, si no tiene, bajo el selector (se ve
  /// siempre). Los valores no se pierden al cambiar de pestaña: viven en
  /// los controladores, que siguen montados.
  final List<PestanaFormulario>? pestanas;

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

  /// Filas `color · cantidad` de los campos [TipoCampo.variantes], editadas
  /// en el formulario (el resto de tipos vive en [_controladores]).
  final Map<String, List<FilaVariante>> _variantesPorCampo = {};

  /// Revisiones de los desplegables que han creado una opción en línea.
  ///
  /// Un `FormField` solo toma `initialValue` al montarse (no lo sincroniza
  /// después), así que al crear una opción se sube la revisión para que la
  /// clave del campo cambie y se recree con el id nuevo: sin esto, el
  /// selector se quedaría mostrando el valor anterior.
  final Map<String, int> _revisiones = {};
  bool _enviando = false;

  /// Cierto mientras un cálculo escribe en otro campo: evita que los
  /// oyentes de precio y porcentaje se disparen entre sí y se reescriban
  /// a la mitad de lo que se está tecleando (bandera anti-bucle).
  bool _recalculando = false;

  /// Pestaña abierta; `null` mientras el formulario no tiene pestañas.
  String? _pestana;

  /// ¿El formulario organiza sus campos en pestañas?
  bool get _conPestanas =>
      widget.pestanas != null && widget.pestanas!.isNotEmpty;

  /// Campos del bloque visible: los de la pestaña abierta y los que no
  /// tienen pestaña (bajo el selector: se ven siempre).
  List<CampoFormulario> get _camposVisibles {
    if (!_conPestanas) return widget.campos;
    return [
      for (final campo in widget.campos)
        if (campo.pestana == null || campo.pestana == _pestana) campo,
    ];
  }

  @override
  void initState() {
    super.initState();
    if (_conPestanas) _pestana = widget.pestanas!.first.clave;
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
    // Filas de variantes: se leen del JSON del producto (`productos.variantes`
    // en edición; vacío al crear = unidad simple «Único»).
    for (final campo in widget.campos) {
      if (campo.tipo != TipoCampo.variantes) continue;
      _variantesPorCampo[campo.clave] = _leerVariantes(
        widget.valores[campo.clave],
      );
    }
    // Porcentaje de ganancia: precio y % se escriben el uno al otro y el
    // costo también arrastra al precio si el porcentaje ya está escrito.
    for (final campo in widget.campos) {
      if (campo.tipo != TipoCampo.porcentaje) continue;
      final destino = campo.porcentajeDestino;
      if (destino != null) {
        _controladores[destino]?.addListener(() => _precioCambio(campo));
      }
      final sobre = campo.porcentajeSobre;
      if (sobre != null) {
        _controladores[sobre]?.addListener(() => _aplicarPorcentaje(campo));
      }
      _precargarPorcentaje(campo);
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

  /// Número escrito en un campo (`25`, `25,5`…); `null` si no lo es.
  /// El parser acepta coma o punto decimal.
  static double? _aNumero(String texto) {
    final limpio = texto.trim().replaceAll(',', '.');
    if (limpio.isEmpty) return null;
    final valor = double.tryParse(limpio);
    return valor == null || valor.isNaN || valor.isInfinite ? null : valor;
  }

  /// Escribe en el precio el resultado de aplicar el porcentaje escrito
  /// sobre la base: `destino = base × (1 + %)`. Ej.: costo 80 y `25` → 100.
  void _aplicarPorcentaje(CampoFormulario campo) {
    if (_recalculando) return;
    final base = _controladores[campo.porcentajeSobre];
    final precio = _controladores[campo.porcentajeDestino];
    final porcentaje = _controladores[campo.clave];
    if (base == null || precio == null || porcentaje == null) return;
    final costo = _aNumero(base.text);
    final puntos = _aNumero(porcentaje.text);
    // Sin base > 0 no se calcula nada (la validación lo dirá después).
    if (costo == null || costo <= 0 || puntos == null) return;
    _recalculando = true;
    precio.text = _aTexto(
      double.parse((costo * (1 + puntos / 100)).toStringAsFixed(2)),
    );
    _recalculando = false;
  }

  /// Al escribir el destino a mano, el porcentaje pasa a mostrar el margen
  /// que ese precio representa sobre la base: `% = (destino − base) ÷
  /// base × 100`. Ej.: costo 80 y precio 100 → 25.
  void _precioCambio(CampoFormulario campo) {
    if (_recalculando) return;
    final costo = _aNumero(_controladores[campo.porcentajeSobre]?.text ?? '');
    final precio = _aNumero(
      _controladores[campo.porcentajeDestino]?.text ?? '',
    );
    final porcentaje = _controladores[campo.clave];
    if (costo == null || costo <= 0 || precio == null || porcentaje == null) {
      return;
    }
    final margen = ((precio - costo) / costo) * 100;
    _recalculando = true;
    porcentaje.text = _aTexto(double.parse(margen.toStringAsFixed(2)));
    _recalculando = false;
  }

  /// Al cargar un registro existente, el campo arranca con el margen que ya
  /// representa el destino vigente (solo si es mayor que la base; un
  /// producto sin margen se queda vacío).
  void _precargarPorcentaje(CampoFormulario campo) {
    final costo = _aNumero(_controladores[campo.porcentajeSobre]?.text ?? '');
    final precio = _aNumero(
      _controladores[campo.porcentajeDestino]?.text ?? '',
    );
    if (costo == null || costo <= 0 || precio == null || precio <= costo) {
      return;
    }
    final margen = ((precio - costo) / costo) * 100;
    _recalculando = true;
    _controladores[campo.clave]!.text = _aTexto(
      double.parse(margen.toStringAsFixed(2)),
    );
    _recalculando = false;
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
    if (campo.tipo == TipoCampo.numero ||
        campo.tipo == TipoCampo.decimal ||
        campo.tipo == TipoCampo.porcentaje) {
      final double numero;
      if (campo.tipo == TipoCampo.numero) {
        final entero = int.tryParse(texto);
        if (entero == null) return 'Debe ser un número entero';
        numero = entero.toDouble();
      } else {
        // El porcentaje acepta coma o punto decimal; el importe, punto.
        final decimal = campo.tipo == TipoCampo.porcentaje
            ? _aNumero(texto)
            : double.tryParse(texto);
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
      if (campo.tipo == TipoCampo.porcentaje) {
        final costo = _aNumero(
          _controladores[campo.porcentajeSobre]?.text ?? '',
        );
        if (costo == null || costo <= 0) {
          return 'Escribe el precio de compra: sobre él se calcula este %';
        }
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

  /// Filtros de entrada: dígitos, decimales y longitud máxima.
  ///
  /// Evitan escribir lo que el backend va a rechazar (p. ej. un importe de
  /// 5 decimales). [CampoFormulario.decimales] sube a 3 para las cantidades
  /// fraccionadas (`NUMERIC(12, 3)`: 1 gramo de precisión con `KG`).
  static List<TextInputFormatter>? _filtros(CampoFormulario campo) {
    final filtros = <TextInputFormatter>[];
    if (campo.soloDigitos || campo.tipo == TipoCampo.numero) {
      filtros.add(FilteringTextInputFormatter.digitsOnly);
    } else if (campo.tipo == TipoCampo.decimal ||
        campo.tipo == TipoCampo.porcentaje) {
      filtros.add(
        FilteringTextInputFormatter.allow(
          RegExp('^\\d{0,9}(\\.\\d{0,${campo.decimales}})?'),
        ),
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
    if (form == null) return;

    // Los campos de la pestaña abierta se validan con el propio `Form`.
    if (!form.validate()) return;

    // REGLA DE ORO: al guardar se validan TODOS los campos, también los de
    // las demás pestañas (no están montados y el `Form` no los ve). Si
    // alguno falla, se salta a su pestaña y, ya montada, se vuelve a
    // validar para que el error se pinte bajo su campo.
    final oculto = _errorEnOtraPestana();
    if (oculto != null) {
      setState(() => _pestana = oculto.pestana);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _formKey.currentState?.validate();
      });
      return;
    }

    final cuerpo = <String, Object?>{};
    for (final campo in widget.campos) {
      // El porcentaje de ganancia es una calculadora de la pantalla: no es
      // un dato del registro, así que no viaja al backend.
      if (campo.tipo == TipoCampo.porcentaje) continue;
      // Las filas de variantes viven en su propio mapa de edición: la
      // clave SIEMPRE viaja (lista vacía = producto unitario «Único»).
      if (campo.tipo == TipoCampo.variantes) {
        cuerpo[campo.clave] = [
          for (final fila in _variantesPorCampo[campo.clave] ?? const [])
            {'colorId': fila.colorId, 'cantidad': fila.cantidad},
        ];
        continue;
      }
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
              if (_conPestanas) ...[
                _selectorPestanas(),
                const SizedBox(height: 16),
              ],
              for (final campo in _camposEnPantalla()) ...[
                campo,
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

  /// Selector de pestañas: botones a ancho completo dentro de una pista
  /// gris, con la pestaña activa en verde de marca. Va bajo el título.
  Widget _selectorPestanas() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          for (final pestana in widget.pestanas!)
            Expanded(child: _botonPestana(pestana)),
        ],
      ),
    );
  }

  Widget _botonPestana(PestanaFormulario pestana) {
    final activa = pestana.clave == _pestana;
    final color = activa ? Colors.white : AppColors.textSecondary;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => setState(() => _pestana = pestana.clave),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: activa ? AppColors.brandGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (pestana.icono != null) ...[
              Icon(pestana.icono, size: 15, color: color),
              const SizedBox(width: 6),
            ],
            Text(
              pestana.etiqueta,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: activa ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Campos ya dispuestos para pintarlos: cada `porcentaje` va en la misma
  /// fila que el destino al que aplica (destino y % lado a lado, en vez de
  /// campo y campo), que es como se usan.
  List<Widget> _camposEnPantalla() {
    final campos = _camposVisibles;
    final salida = <Widget>[];
    for (var i = 0; i < campos.length; i++) {
      final campo = campos[i];
      final siguiente = i + 1 < campos.length ? campos[i + 1] : null;
      final pareja =
          campo.tipo != TipoCampo.porcentaje &&
          siguiente != null &&
          siguiente.tipo == TipoCampo.porcentaje &&
          siguiente.porcentajeDestino == campo.clave;
      if (!pareja) {
        salida.add(_construirCampo(campo));
        continue;
      }
      salida.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _construirCampo(campo)),
            const SizedBox(width: 10),
            SizedBox(width: 138, child: _construirCampo(siguiente)),
          ],
        ),
      );
      i++; // el porcentaje ya está pintado en esta fila
    }
    return salida;
  }

  /// Primer error de un campo que **no está en la pestaña abierta**, con
  /// la pestaña en la que vive; `null` = las demás están correctas.
  ///
  /// Los valores no se pierden al cambiar de pestaña (viven en
  /// [_controladores] y [_selecciones]), así que aquí se aplica la misma
  /// regla [_validar] que usa el `Form` para los campos visibles.
  ({String pestana, String error})? _errorEnOtraPestana() {
    if (!_conPestanas) return null;
    if (widget.soloLectura) return null;
    for (final campo in widget.campos) {
      final pestana = campo.pestana;
      if (pestana == null || pestana == _pestana) continue;
      final valor = campo.tipo == TipoCampo.opcion
          ? _selecciones[campo.clave]
          : _controladores[campo.clave]?.text;
      final error = _validar(campo, valor);
      if (error != null) return (pestana: pestana, error: error);
    }
    return null;
  }

  Widget _construirCampo(CampoFormulario campo) {
    switch (campo.tipo) {
      case TipoCampo.opcion:
        return _desplegable(campo);
      case TipoCampo.fecha:
        return _fecha(campo);
      case TipoCampo.imagen:
        return _imagen(campo);
      case TipoCampo.color:
        return _muestraColor(campo);
      case TipoCampo.porcentaje:
        return _porcentaje(campo);
      case TipoCampo.variantes:
        return _variantes(campo);
      case TipoCampo.texto:
      case TipoCampo.numero:
      case TipoCampo.decimal:
      case TipoCampo.clave:
        return _texto(campo);
    }
  }

  /// Filas iniciales del editor de variantes desde `productos.variantes`.
  ///
  /// La variante «Único» (`colorId` nulo) no es una fila: es justamente lo
  /// que hay cuando la lista está vacía.
  static List<FilaVariante> _leerVariantes(Object? crudo) {
    if (crudo is! List) return [];
    return [
      for (final fila in crudo)
        if (fila is Map && fila['colorId'] != null)
          FilaVariante(
            colorId: (fila['colorId'] as num).toInt(),
            nombre: (fila['nombreColor'] ?? 'Color').toString(),
            codigoHex: fila['codigoHex'] as String?,
            cantidad: (fila['stock'] as num?)?.toDouble() ?? 0,
          ),
    ];
  }

  /// Editor «color · cantidad» de las variantes del producto.
  ///
  /// Sin filas el producto se vende como unidad (variante «Único»); con
  /// filas, el stock del producto es la suma de ellas — por eso el stock del
  /// campo de al lado queda como respaldo.
  Widget _variantes(CampoFormulario campo) {
    final filas = _variantesPorCampo[campo.clave] ?? const <FilaVariante>[];
    return InputDecorator(
      decoration: _decoracion(campo.etiqueta, campo.auxiliar),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (filas.isEmpty)
            const Text(
              'Sin colores: se vende como unidad simple (variante «Único»).',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            )
          else
            for (var i = 0; i < filas.length; i++)
              _filaVariante(campo, filas, i),
          if (!widget.soloLectura)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _agregarColor(campo),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Añadir color'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.cardBorder),
                      foregroundColor: AppColors.textPrimary,
                    ),
                  ),
                  // Mismo patrón que «Nueva categoría»: crear el color aquí
                  // mismo y usarlo en la fila en el acto.
                  TextButton.icon(
                    onPressed: () => _nuevoColorRapido(campo),
                    icon: const Icon(Icons.palette_outlined, size: 16),
                    label: const Text('Nuevo color'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Una fila: chip del color + nombre + cantidad + botón de quitar.
  Widget _filaVariante(
    CampoFormulario campo,
    List<FilaVariante> filas,
    int indice,
  ) {
    final fila = filas[indice];
    return Padding(
      key: ValueKey('variante-${fila.colorId}'),
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          chipColor(fila.codigoHex, nombre: fila.nombre, tamano: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fila.nombre,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: TextFormField(
              key: ValueKey('cantidad-${fila.colorId}'),
              initialValue: _aTexto(fila.cantidad),
              enabled: !widget.soloLectura,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d{0,6}(\.\d{0,3})?'),
                ),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Stock',
                labelStyle: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                isDense: true,
              ),
              onChanged: (valor) => setState(
                () => fila.cantidad = double.tryParse(valor.trim()) ?? 0,
              ),
            ),
          ),
          if (!widget.soloLectura) ...[
            const SizedBox(width: 2),
            IconButton(
              tooltip: 'Quitar color',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: AppColors.negativeRed,
              ),
              onPressed: () => setState(() => filas.removeAt(indice)),
            ),
          ],
        ],
      ),
    );
  }

  /// Hoja «Elige el color» con los colores del catálogo que **no** estén ya
  /// en la fila (los `INACTIVO`/`BLOQUEADO` no aparecen).
  Future<void> _agregarColor(CampoFormulario campo) async {
    final colores = context.read<ColoresController>();
    final filas = _variantesPorCampo[campo.clave] ??= [];
    final elegido = await elegirColorDeCatalogo(
      context,
      colores: colores,
      excluidos: {for (final fila in filas) fila.colorId},
    );
    if (elegido == null || !mounted) return;
    final (id, nombre, hex) = elegido;
    if (filas.any((fila) => fila.colorId == id)) return;
    setState(() {
      filas.add(
        FilaVariante(colorId: id, nombre: nombre, codigoHex: hex, cantidad: 1),
      );
    });
  }

  /// Botón «Nuevo color»: crea el color y agrega su fila directamente.
  Future<void> _nuevoColorRapido(CampoFormulario campo) async {
    final colores = context.read<ColoresController>();
    final filas = _variantesPorCampo[campo.clave] ??= [];
    final nuevo = await pedirNuevoColor(context, colores: colores);
    if (nuevo == null || !mounted) return;
    final (id, nombre, hex) = nuevo;
    if (filas.any((fila) => fila.colorId == id)) return;
    setState(() {
      filas.add(
        FilaVariante(colorId: id, nombre: nombre, codigoHex: hex, cantidad: 1),
      );
    });
  }

  /// Muestra de color: el valor vive en el controlador del texto (como en
  /// los demás campos), pero se elige de una **paleta** en vez de teclear
  /// el hexadecimal. Vacío = sin muestra (la API recibe `null`).
  Widget _muestraColor(CampoFormulario campo) {
    final controlador = _controladores[campo.clave]!;
    return ListenableBuilder(
      listenable: controlador,
      builder: (context, _) {
        final valor = controlador.text.trim();
        return TextFormField(
          controller: controlador,
          readOnly: true,
          showCursor: false,
          validator: widget.soloLectura
              ? null
              : (texto) => _validar(campo, texto),
          onTap: widget.soloLectura ? null : () => _elegirMuestra(controlador),
          decoration: _decoracion(campo.etiqueta, campo.auxiliar).copyWith(
            prefixIcon: Padding(
              padding: const EdgeInsets.all(12),
              child: chipColor(valor.isEmpty ? null : valor, tamano: 24),
            ),
            suffixIcon: widget.soloLectura
                ? null
                : IconButton(
                    tooltip: 'Elegir color',
                    onPressed: () => _elegirMuestra(controlador),
                    icon: const Icon(Icons.palette_outlined, size: 20),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _elegirMuestra(TextEditingController controlador) async {
    final elegida = await elegirMuestraDeColor(
      context,
      actual: controlador.text.trim(),
    );
    if (elegida == null || !mounted) return;
    setState(() => controlador.text = elegida);
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

  /// Porcentaje de ganancia (p. ej. `25` = el precio de compra + 25 %).
  ///
  /// Es una calculadora de pantalla: no viaja al backend. Al escribirlo
  /// recalcula el destino y, si el destino se escribe a mano, él solo pasa
  /// a mostrar el margen real.
  Widget _porcentaje(CampoFormulario campo) => TextFormField(
    controller: _controladores[campo.clave],
    enabled: !widget.soloLectura,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: _filtros(campo),
    style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
    onChanged: (_) => _aplicarPorcentaje(campo),
    decoration: _decoracion(campo.etiqueta, campo.auxiliar).copyWith(
      suffixText: '%',
      suffixStyle: const TextStyle(color: AppColors.textSecondary),
    ),
    validator: widget.soloLectura ? null : (valor) => _validar(campo, valor),
  );

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
      // Vacío: en edición, un obligatorio arranca sin valor para que la
      // validación lo pida; en detalle (solo lectura) se enseña
      // «— Sin asignar —» también en los obligatorios: no se puede editar
      // y el hueco en blanco solo confunde.
      initialValue:
          valor ?? (widget.soloLectura || !_esRequerido(campo) ? '' : null),
      opciones: [
        if (widget.soloLectura || !_esRequerido(campo))
          const Opccion('', '— Sin asignar —'),
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
