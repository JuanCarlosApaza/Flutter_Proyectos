/// Formatos numéricos compartidos por la UI (informes, tablas, PDF).
///
/// Reglas de la casa:
///
/// * dinero → `Bs 1234.50` (siempre dos decimales, punto decimal);
/// * unidades → sin decimales cuando son enteras (`3`), y hasta tres
///   decimales recortados cuando son fraccionarias (`12.75`, `2.125`);
/// * porcentaje → un decimal y `%`.
library;

/// Dinero en bolivianos (`Bs 1234.50`).
String bs(double valor) => 'Bs ${valor.toStringAsFixed(2)}';

/// Solo el número de [bs], para celdas numéricas (CSV, PDF, exportaciones).
String bsNumero(double valor) => valor.toStringAsFixed(2);

/// Cantidad de unidades: entera sin decimales, fraccionaria con los
/// necesarios (máximo 3).
String unidadesTexto(double valor) {
  if (valor == valor.truncateToDouble()) return valor.toStringAsFixed(0);
  final texto = valor.toStringAsFixed(3);
  return texto
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// Porcentaje con un decimal (`75.0%`).
String porcentajeTexto(double valor) => '${valor.toStringAsFixed(1)}%';

/// Fracción → porcentaje sobre [total] (0 si el total es 0).
double porcentajeDe(double valor, double total) =>
    total == 0 ? 0 : valor / total * 100;
