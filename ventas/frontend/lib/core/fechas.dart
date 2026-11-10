/// Utilidades de fecha compartidas por la app.
///
/// Las respuestas de la API vienen en ISO-8601 **UTC**; casi toda la UI
/// muestra fechas ya convertidas a la hora local del dispositivo.
library;

/// Parte de fecha (`yyyy-MM-dd`) de [iso] convertida a hora local.
///
/// Sin `toLocal()`, una venta de las 23:30 locales (03:30 UTC del día
/// siguiente) se mostraba como mañana en la tabla mientras la ficha —que sí
/// convertía— mostraba el día correcto. Devuelve `—` si [iso] está vacía o
/// no se puede parsear.
String fechaCortaLocal(String iso) {
  final momento = DateTime.tryParse(iso)?.toLocal();
  if (momento == null) return '—';
  return fechaCorta(momento);
}

/// Parte de fecha (`yyyy-MM-dd`) de una fecha ya **local** (los filtros del
/// informe, los atajos «Hoy»/«Ayer», las etiquetas de exportación…).
///
/// Se leen los componentes tal cual: el informe trabaja con **días**, no con
/// instantes, así que aquí tampoco hay que convertir zona horaria.
String fechaCorta(DateTime fecha) {
  return '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';
}
