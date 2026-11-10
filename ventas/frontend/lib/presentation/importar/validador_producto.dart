import '../../core/validation/reglas.dart';
import '../widgets/recurso_form.dart';
import 'lector_excel.dart';

/// Relación que no existía en su catálogo y que se creará al importar
/// (mismo comportamiento que el botón «+» del formulario).
class RelacionPendiente {
  const RelacionPendiente({required this.clave, required this.nombre});

  final String clave;
  final String nombre;
}

/// Una fila del Excel ya validada, con el cuerpo listo para la API.
class FilaValidada {
  const FilaValidada({
    required this.fila,
    required this.cuerpo,
    this.motivo,
    this.pendientes = const [],
    this.duplicada = false,
  });

  /// Número real de fila en el Excel.
  final int fila;

  /// Motivo del fallo; `null` = la fila está bien.
  final String? motivo;

  /// Relaciones por crear antes de mandar el cuerpo.
  final List<RelacionPendiente> pendientes;

  /// Repetida dentro del propio archivo (se omite con aviso).
  final bool duplicada;

  /// Cuerpo JSON para `POST /products/importar` (relaciones a ID).
  final Map<String, Object?> cuerpo;

  bool get valida => motivo == null;
  bool get debeImportar => valida && !duplicada;
}

/// Valida las filas con **exactamente las mismas reglas del formulario**:
/// los límites salen de las propias declaraciones [campos] (la lista de
/// `ProductosPage`, única fuente de verdad) y las reglas entre campos son
/// las de `reglas.dart`, con los mismos mensajes que pinta el formulario.
///
/// Los duplicados se marcan dentro del propio archivo: por `Código` o, sin
/// código, por `Nombre + Categoría + Presentación`.
List<FilaValidada> validarFilas({
  required List<FilaExcel> filas,
  required List<CampoFormulario> campos,
}) {
  // Claves ya vistas en ESTE archivo (una sola pasada, sin estado global).
  final vistos = <String>{};
  return [
    for (final fila in filas)
      _validarFila(fila, campos: campos, vistos: vistos),
  ];
}

FilaValidada _validarFila(
  FilaExcel fila, {
  required List<CampoFormulario> campos,
  required Set<String> vistos,
}) {
  // Calculadora de ganancia: si el precio de venta viene vacío y hay %, se
  // calcula ANTES de validar — el resultado es el mismo que en el form.
  final efectiva = _conGananciaCalculada(fila, campos);

  final valores = <String, Object?>{};
  final pendientes = <RelacionPendiente>[];
  String? error;

  for (final campo in campos) {
    // La calculadora no viaja al backend (tampoco en el formulario).
    if (campo.tipo == TipoCampo.porcentaje) {
      error = _validarPorcentaje(campo, efectiva, campos);
      if (error != null) break;
      continue;
    }
    // Imágenes: fuera de la v1 (decisión 3 del patrón).
    if (campo.tipo == TipoCampo.imagen) continue;

    final texto = efectiva.valor(campo.clave);
    switch (campo.tipo) {
      case TipoCampo.variantes:
        error = _validarVariantes(campo, texto, valores);
      case TipoCampo.fecha:
        error = _validarFecha(campo, texto, valores);
      case TipoCampo.opcion:
        error = _validarOpcion(campo, texto, valores, pendientes);
      case TipoCampo.numero:
      case TipoCampo.decimal:
        error = _validarNumero(campo, texto, valores);
      default:
        error = _validarTexto(campo, texto, valores);
    }
    if (error != null) break;
  }
  if (error != null) {
    return FilaValidada(fila: fila.fila, cuerpo: const {}, motivo: error);
  }

  // ── Reglas entre campos (mismas que el formulario) ──────────────────
  // Con colores, el stock del producto es la suma de las filas: el valor
  // de la celda «Stock» se ignora, igual que en la ficha.
  final variantes = valores['variantes'] as List<Map<String, Object?>>? ?? [];
  if (variantes.isNotEmpty) {
    valores['stock'] = variantes.fold<double>(
      0,
      (suma, fila) => suma + (fila['cantidad']! as double),
    );
  }

  final cruzada =
      rebajaNoMayorQueVenta(valores['precioRebaja'], valores['precioVenta']) ??
      ventaNoMenorQueCoste(valores['precioVenta'], valores['precioCompra']);
  if (cruzada != null) {
    return FilaValidada(fila: fila.fila, cuerpo: const {}, motivo: cruzada);
  }

  // ── Duplicada dentro del propio archivo ──────────────────────────────
  // Se registran AMBAS claves de cada fila: la del código (si trae) y la
  // de nombre + categoría + presentación. Así se detecta el mismo producto
  // aunque una fila venga con código y la repetida sin él.
  final codigo = (valores['codigo'] as String? ?? '').trim();
  final claves = <String>{
    if (codigo.isNotEmpty) 'c:${encabezadoComparable(codigo)}',
    'n:${encabezadoComparable(valores['nombre'] as String? ?? '')}'
        '|${valores['categoriaId'] ?? _pendiente(valores, 'categoriaId') ?? ''}'
        '|${valores['presentacionId'] ?? _pendiente(valores, 'presentacionId') ?? ''}',
  };
  if (claves.any(vistos.contains)) {
    return FilaValidada(
      fila: fila.fila,
      cuerpo: const {},
      duplicada: true,
      motivo: 'Ya está repetida en el archivo (se omite).',
    );
  }
  vistos.addAll(claves);

  return FilaValidada(
    fila: fila.fila,
    pendientes: pendientes,
    cuerpo: _cuerpo(valores),
  );
}

// ── Validación por tipo de campo ────────────────────────────────────────

String? _validarTexto(
  CampoFormulario campo,
  String texto,
  Map<String, Object?> valores,
) {
  if (texto.isEmpty) {
    if (campo.obligatorio) return 'Este campo es obligatorio';
    valores[campo.clave] = null;
    return null;
  }
  if (campo.maxCaracteres != null && texto.length > campo.maxCaracteres!) {
    return 'No puede superar ${campo.maxCaracteres} caracteres';
  }
  if (campo.minCaracteres != null && texto.length < campo.minCaracteres!) {
    return 'Debe tener al menos ${campo.minCaracteres} caracteres';
  }
  if (campo.patron != null && !campo.patron!.hasMatch(texto)) {
    return campo.mensajePatron ?? 'Formato no válido';
  }
  valores[campo.clave] = texto;
  return null;
}

String? _validarNumero(
  CampoFormulario campo,
  String texto,
  Map<String, Object?> valores,
) {
  if (texto.isEmpty) {
    if (campo.obligatorio) return 'Este campo es obligatorio';
    valores[campo.clave] = null;
    return null;
  }
  final numero = aNumeroExcel(texto);
  if (numero == null) return 'Debe ser un número';
  final fueraDeRango = _rango(campo, numero);
  if (fueraDeRango != null) return fueraDeRango;
  // Mismo recorte que el campo del formulario (3 decimales en cantidades).
  valores[campo.clave] = redondearCantidad(numero, campo.decimales);
  return null;
}

String? _rango(CampoFormulario campo, double numero) {
  if (campo.min != null && numero < campo.min!) {
    return campo.min! <= 0
        ? 'No puede ser negativo'
        : 'Debe ser mayor o igual a ${_limite(campo.min!)}';
  }
  if (campo.max != null && numero > campo.max!) {
    return 'No puede superar ${_limite(campo.max!)}';
  }
  return null;
}

String? _validarFecha(
  CampoFormulario campo,
  String texto,
  Map<String, Object?> valores,
) {
  if (texto.isEmpty) {
    if (campo.obligatorio) return 'Este campo es obligatorio';
    valores[campo.clave] = null;
    return null;
  }
  final fecha = fechaDeCelda(texto);
  if (fecha == null) return 'Debe ser una fecha válida';
  final desde = campo.minFecha;
  if (desde != null && _soloFecha(fecha).isBefore(_soloFecha(desde))) {
    return 'No puede ser anterior a ${_corta(desde)}';
  }
  final hasta = campo.maxFecha;
  if (hasta != null && _soloFecha(fecha).isAfter(_soloFecha(hasta))) {
    return 'No puede ser posterior a ${_corta(hasta)}';
  }
  valores[campo.clave] = fecha;
  return null;
}

String? _validarOpcion(
  CampoFormulario campo,
  String texto,
  Map<String, Object?> valores,
  List<RelacionPendiente> pendientes,
) {
  if (texto.isEmpty) {
    if (campo.obligatorio) return 'Este campo es obligatorio';
    valores[campo.clave] = null;
    return null;
  }
  final opciones =
      campo.opcionesDinamicas?.call() ?? campo.opciones ?? const <Opccion>[];
  final elegida = buscarOpcion(opciones, texto);
  if (elegida != null) {
    valores[campo.clave] = elegida.valor;
    return null;
  }
  // Catálogos con botón «+» (categoría, marca, presentación, proveedor):
  // si no existe, se crea al importar. Sin botón (unidad) → error.
  if (campo.onCrear != null) {
    pendientes.add(RelacionPendiente(clave: campo.clave, nombre: texto));
    valores['${campo.clave}PorCrear'] = texto;
    valores[campo.clave] = null;
    return null;
  }
  return 'No existe «$texto» en «${campo.etiqueta}»';
}

String? _validarVariantes(
  CampoFormulario campo,
  String texto,
  Map<String, Object?> valores,
) {
  if (texto.isEmpty) {
    valores[campo.clave] = <Map<String, Object?>>[];
    return null;
  }
  final filas = <Map<String, Object?>>[];
  final vistos = <String>{};
  for (final trozo in texto.split(';')) {
    final parte = trozo.trim();
    if (parte.isEmpty) continue;
    // `Color|cantidad`: `|` y `;` no pueden aparecer dentro de un color
    // (si aparecen, se rechaza la fila: no se parte el valor a medias).
    if (!parte.contains('|')) {
      return 'En «Colores» cada fila es Color|cantidad (falta «|» en «$parte»)';
    }
    final trozos = parte.split('|');
    if (trozos.length != 2) {
      return 'En «Colores» la fila «$parte» tiene más de un «|»';
    }
    final color = trozos[0].trim();
    final cantidad = aNumeroExcel(trozos[1].trim());
    if (color.isEmpty) return 'En «Colores» falta el nombre del color';
    if (cantidad == null) {
      return 'En «Colores» la fila «$parte» necesita una cantidad numérica';
    }
    if (cantidad < 0) {
      return 'En «Colores» la cantidad de «$color» no puede ser negativa';
    }
    if (color.contains(';')) {
      return 'En «Colores» el nombre «$color» no puede contener «;»';
    }
    if (!vistos.add(encabezadoComparable(color))) {
      return 'El color «$color» aparece más de una vez';
    }
    filas.add({
      'color': color,
      // Las cantidades son fraccionadas: 3 decimales, como el stock.
      'cantidad': redondearCantidad(cantidad, 3),
    });
  }
  valores[campo.clave] = filas;
  return null;
}

/// Validación del campo calculadora: solo su propio número y la base sobre
/// la que calcula (los mismos mensajes que pinta el formulario).
String? _validarPorcentaje(
  CampoFormulario campo,
  FilaExcel fila,
  List<CampoFormulario> campos,
) {
  final texto = fila.valor(campo.clave);
  if (texto.isEmpty) return null;
  final numero = aNumeroExcel(texto);
  if (numero == null) return 'Debe ser un número';
  final fueraDeRango = _rango(campo, numero);
  if (fueraDeRango != null) return fueraDeRango;
  final base = campo.porcentajeSobre;
  if (base == null) return null;
  final celdaBase = campos.firstWhere(
    (c) => c.clave == base,
    orElse: () => campo,
  );
  final coste = aNumeroExcel(fila.valor(celdaBase.clave));
  if (coste == null || coste <= 0) {
    return 'Escribe el precio de compra: sobre él se calcula este %';
  }
  return null;
}

// ── Auxiliares ──────────────────────────────────────────────────────────

/// Si una columna es calculadora (`Ganancia %`) y su destino
/// (`Precio de venta`) viene vacío, el destino se rellena con el resultado
/// antes de validar, igual que al escribir el % en el formulario.
FilaExcel _conGananciaCalculada(FilaExcel fila, List<CampoFormulario> campos) {
  final calculadoras = campos.where((c) => c.tipo == TipoCampo.porcentaje);
  final calculadas = <String, String>{};
  for (final campo in calculadoras) {
    final destino = campo.porcentajeDestino;
    final base = campo.porcentajeSobre;
    if (destino == null || base == null) continue;
    if (fila.valor(destino).isNotEmpty) continue; // precio escrito → se ignora
    final texto = fila.valor(campo.clave);
    if (texto.isEmpty) continue;
    final porcentaje = aNumeroExcel(texto);
    final coste = aNumeroExcel(fila.valor(base));
    if (porcentaje == null || coste == null || coste <= 0) continue;
    // La validación propia del % y la del precio ya dirán lo que toque.
    final precio = redondearCantidad(coste * (1 + porcentaje / 100), 2);
    if (precio <= 0) continue;
    calculadas[destino] = precio.toString();
  }
  if (calculadas.isEmpty) return fila;
  return FilaExcel(fila: fila.fila, celdas: {...fila.celdas, ...calculadas});
}

/// Cuerpo JSON: igual que el formulario manda `null` en lo que quede vacío
/// (la API aplica sus valores por defecto) y nunca la calculadora de %.
Map<String, Object?> _cuerpo(Map<String, Object?> valores) => {
  for (final entrada in valores.entries)
    if (!_esClaveInterna(entrada.key))
      entrada.key: entrada.value is DateTime
          ? _fechaApi(entrada.value as DateTime)
          : entrada.value,
  'variantes': valores['variantes'] as List<Map<String, Object?>>? ?? const [],
};

bool _esClaveInterna(String clave) =>
    clave.endsWith('PorCrear') || clave == 'gananciaPct';

String? _pendiente(Map<String, Object?> valores, String clave) =>
    valores['${clave}PorCrear'] as String?;

String _fechaApi(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';

/// `59,90` y `1.234,56` (miles): coma o punto decimal, sin ambigüedad
/// cuando el valor trae los dos separadores.
double? aNumeroExcel(String texto) {
  final limpio = texto.trim().replaceAll(' ', '').replaceAll(' ', '');
  if (limpio.isEmpty) return null;
  var normal = limpio;
  if (normal.contains(',') && normal.contains('.')) {
    normal = normal.lastIndexOf(',') > normal.lastIndexOf('.')
        ? normal.replaceAll('.', '').replaceAll(',', '.')
        : normal.replaceAll(',', '');
  } else {
    normal = normal.replaceAll(',', '.');
  }
  final valor = double.tryParse(normal);
  return valor == null || valor.isNaN || valor.isInfinite ? null : valor;
}

/// `30/06/2027`, `2027-06-30` o el serial de Excel (`45123`).
DateTime? fechaDeCelda(String texto) {
  final t = texto.trim();
  if (t.isEmpty) return null;
  final iso = DateTime.tryParse(t);
  if (iso != null) return _soloFecha(iso);
  final partes = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$')
      .firstMatch(t);
  if (partes != null) {
    return DateTime(
      int.parse(partes.group(3)!),
      int.parse(partes.group(2)!),
      int.parse(partes.group(1)!),
    );
  }
  final serie = aNumeroExcel(t);
  if (serie != null && serie >= 1 && serie <= 200000) {
    return fechaDeSerial(serie);
  }
  return null;
}

/// Busca una opción por valor o por etiqueta, sin importar mayúsculas ni
/// acentos («kg», «KG» y «Kilogramo (KG)» valen lo mismo).
Opccion? buscarOpcion(List<Opccion> opciones, String texto) {
  final buscado = encabezadoComparable(texto);
  if (buscado.isEmpty) return null;
  for (final opcion in opciones) {
    if (encabezadoComparable(opcion.valor) == buscado) return opcion;
    if (encabezadoComparable(opcion.etiqueta) == buscado) return opcion;
  }
  return null;
}

/// Límite numérico sin ceros sobrantes (`1`, `0.01`), igual que el form.
String _limite(double valor) => valor == valor.roundToDouble()
    ? valor.toInt().toString()
    : valor.toString();

DateTime _soloFecha(DateTime fecha) =>
    DateTime(fecha.year, fecha.month, fecha.day);

String _corta(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';

/// Recuento de la vista previa (una línea).
({int validas, int conError, int repetidas}) resumenImportacion(
  List<FilaValidada> filas,
) {
  var validas = 0;
  var conError = 0;
  var repetidas = 0;
  for (final fila in filas) {
    // Las repetidas van ANTES que las erróneas: traen motivo, pero no son
    // un error de validación.
    if (fila.duplicada) {
      repetidas++;
    } else if (!fila.valida) {
      conError++;
    } else {
      validas++;
    }
  }
  return (validas: validas, conError: conError, repetidas: repetidas);
}
