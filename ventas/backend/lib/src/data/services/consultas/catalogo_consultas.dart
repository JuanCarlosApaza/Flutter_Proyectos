import 'catalogo.dart';
import 'consultas_otros.dart';
import 'consultas_stock.dart';
import 'consultas_ventas.dart';

export 'catalogo.dart';

/// El catálogo completo del asistente: todas las funciones parametrizables
/// con las que la IA puede responder (el «árbol de variables»).
CatalogoConsultas catalogoConsultas() => CatalogoConsultas([
  ...funcionesStock(),
  ...funcionesVentas(),
  ...funcionesOtras(),
]);
