/// Utilidades para leer columnas de una fila devuelta por PostgreSQL.
///
/// Capa `data/`: centraliza las peculiaridades del driver para que cada modelo
/// solo tenga que mapear sus campos:
///
/// * `BIGINT`/`INT` llegan como [int];
/// * `NUMERIC` llega como `Decimal` (se pasa por texto, no es `num`);
/// * los enums propios se seleccionan con `::text` y llegan como [String];
/// * `TIMESTAMP WITH TIME ZONE` llega como [DateTime].
final class RowUtils {
  const RowUtils._();

  /// Entero obligatorio (`0` si es nulo, lo inesperado no revienta).
  static int intValue(Object? value) => switch (value) {
    null => 0,
    final int number => number,
    final num number => number.toInt(),
    _ => int.tryParse(value.toString()) ?? 0,
  };

  /// Entero opcional.
  static int? intOrNull(Object? value) => switch (value) {
    null => null,
    final int number => number,
    final num number => number.toInt(),
    _ => int.tryParse(value.toString()),
  };

  /// Decimal (`NUMERIC`) obligatorio.
  static double doubleValue(Object? value) => doubleOrNull(value) ?? 0;

  /// Decimal (`NUMERIC`) opcional.
  static double? doubleOrNull(Object? value) => switch (value) {
    null => null,
    final double number => number,
    final int number => number.toDouble(),
    _ => double.tryParse(value.toString()),
  };

  /// Booleano (`BOOLEAN`): PostgreSQL lo entrega como [bool] y SQLite como
  /// `0`/`1`, así que se normaliza aquí y no en cada modelo.
  static bool boolValue(Object? value) => switch (value) {
    null => false,
    final bool flag => flag,
    final int number => number != 0,
    final num number => number != 0,
    final String text =>
      text == 'true' || text == 't' || text == 'y' || text == '1',
    _ => false,
  };

  /// Texto (incluidos los enums seleccionados con `::text`).
  static String text(Object? value, {String fallback = ''}) =>
      value?.toString() ?? fallback;

  /// Texto opcional.
  static String? textOrNull(Object? value) => value?.toString();

  /// Fecha y hora (`TIMESTAMP WITH TIME ZONE`).
  static DateTime dateTime(Object? value) => dateTimeOrNull(value)!.toUtc();

  /// Fecha y hora opcional.
  static DateTime? dateTimeOrNull(Object? value) => switch (value) {
    null => null,
    final DateTime date => date.toUtc(),
    final String text => DateTime.tryParse(text)?.toUtc(),
    _ => null,
  };

  /// Fecha (`DATE`): se conserva solo el día (`2027-06-30`).
  static DateTime? dateOrNull(Object? value) {
    final date = switch (value) {
      null => null,
      final DateTime date => date,
      final String text => DateTime.tryParse(text),
      _ => null,
    };
    return date == null ? null : DateTime(date.year, date.month, date.day);
  }

  /// Fecha como `yyyy-MM-dd` (formato de la API para columnas `DATE`).
  static String? dateToJson(Object? value) {
    final date = dateOrNull(value);
    if (date == null) return null;
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// Fecha y hora como ISO-8601 en UTC (`2026-09-26T09:10:34.808Z`).
  static String dateTimeToJson(Object? value) =>
      dateTimeOrNull(value)?.toIso8601String() ?? '';
}
