/// Reglas de la suscripción del sistema (licencia offline).
///
/// Diseño para un producto que se instala en equipos de clientes sin
/// conexión: la clave maestra del programador **activa** una duración y la
/// fecha de vencimiento vive en la BD del cliente. El backend la comprueba
/// en cada petición (misma lógica en APK y escritorio).
///
/// Antitrampa: además de la fecha, se recuerda la **última fecha vista** del
/// equipo. Si el cliente retrocede el reloj del dispositivo/PC más de un día
/// respecto a lo registrado, la suscripción se bloquea (`fecha_atrasada`):
/// para «alargarla» tendría que borrar datos o restaurar respaldos viejos,
/// perdiendo sus ventas.
library;

import '../../core/errors/app_exception.dart';
import 'contrasenas.dart';

/// Hash bcrypt de la clave maestra (`qwerty2424`). El texto claro no vive
/// en el código, igual que la cuenta del programador.
const String _claveSuscripcionHash =
    r'$2a$10$bH.Vs53bUI8/M93OfaaEyu3/FTkjWBAb9ARIDHx3UpSlY1qcC8IYK';

/// Duraciones que se pueden activar (`minuto` es la prueba rápida).
const List<String> suscripcionesDuracion = [
  'minuto',
  'semana',
  'mes',
  'siempre',
];

/// Ajustes que componen la suscripción (clave → valor en la tabla `Ajustes`).
const String ajusteSuscripcionVence = 'suscripcionVence';
const String ajusteSuscripcionVista = 'suscripcionVista';

/// ¿[clave] es la clave maestra? (bcrypt, sin revelar cuál falló).
bool suscripcionClaveValida(String clave) =>
    verificarContrasena(guardada: _claveSuscripcionHash, recibida: clave);

/// `yyyy-MM-dd` local de [momento] (formato de las fechas de suscripción).
String suscripcionFecha(DateTime momento) =>
    '${momento.year.toString().padLeft(4, '0')}-'
    '${(momento.month).toString().padLeft(2, '0')}-'
    '${momento.day.toString().padLeft(2, '0')}';

/// `yyyy-MM-dd HH:mm:ss` local de [momento]: lo usa el plazo de prueba de
/// 1 minuto, que necesita hora para vencer dentro del mismo día.
String suscripcionFechaHora(DateTime momento) =>
    '${suscripcionFecha(momento)} '
    '${momento.hour.toString().padLeft(2, '0')}:'
    '${momento.minute.toString().padLeft(2, '0')}:'
    '${momento.second.toString().padLeft(2, '0')}';

/// Fecha de vencimiento para [duracion] desde [hoy]:
/// `'minuto'` → +1 minuto (con hora), `'semana'` → +7 días,
/// `'mes'` → +30 días, `'siempre'` → literal.
String suscripcionVence(String duracion, DateTime hoy) => switch (duracion) {
  'minuto' => suscripcionFechaHora(hoy.add(const Duration(minutes: 1))),
  'semana' => suscripcionFecha(hoy.add(const Duration(days: 7))),
  'mes' => suscripcionFecha(hoy.add(const Duration(days: 30))),
  'siempre' => 'siempre',
  _ => throw BadRequestException(
    'Duración no válida: usa "minuto", "semana", "mes" o "siempre".',
    code: 'duracion_invalida',
  ),
};

/// Resultado de la comprobación de la suscripción.
///
/// * [permitir] → `false` = la app debe mostrar la pantalla de bloqueo.
/// * [motivo] → `vencida` o `fecha_atrasada` (para el texto del bloqueo).
/// * [refrescarVista] → hay que guardar la fecha actual como vista.
({bool permitir, String? motivo, bool refrescarVista}) comprobarSuscripcion({
  required String vence,
  required String vista,
  required DateTime hoy,
}) {
  // Sin activación previa no se exige nada (las versiones actuales siguen
  // libres hasta que el programador activa una suscripción).
  if (vence.trim().isEmpty) {
    return (permitir: true, motivo: null, refrescarVista: false);
  }

  final hoyTexto = suscripcionFecha(hoy);

  // Reloj retrocedido más de un día respecto a lo ya visto: trampa.
  // (Una `vista` corrupta no bloquea: simplemente no aporta señal.)
  if (vista.trim().isNotEmpty && hoyTexto.compareTo(vista) < 0) {
    try {
      final retraso = DateTime.parse(vista)
          .difference(DateTime.parse(hoyTexto));
      if (retraso.inDays > 1) {
        return (
          permitir: false,
          motivo: 'fecha_atrasada',
          refrescarVista: false,
        );
      }
    } on FormatException {
      // Fecha ilegible: se ignora el antitrampa.
    }
  }

  final refrescar = hoyTexto.compareTo(vista) > 0;
  if (vence != 'siempre') {
    // Plazo con hora (prueba de 1 minuto): se compara con hora; los plazos
    // normales solo llevan fecha y se comparan día a día.
    final ahoraTexto = vence.length > 10 ? suscripcionFechaHora(hoy) : hoyTexto;
    if (ahoraTexto.compareTo(vence) > 0) {
      return (permitir: false, motivo: 'vencida', refrescarVista: refrescar);
    }
  }
  return (permitir: true, motivo: null, refrescarVista: refrescar);
}
