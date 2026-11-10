import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../network/api_client.dart';
import '../theme/app_colors.dart';
import 'alertas.dart';

/// Puerto del servidor web (`tool/serve_web.dart`) usado cuando la app corre
/// en escritorio, donde `Uri.base` es un `file://` sin puerto.
///
/// Se puede cambiar al compilar: `flutter run --dart-define=WEB_PORT=9000`.
const String _puertoWeb = String.fromEnvironment(
  'WEB_PORT',
  defaultValue: '8081',
);

/// Puerto al que debe apuntar el QR.
///
/// * **Web:** el de la propia página (`Uri.base`), para que el celular abra el
///   mismo origen que la PC.
/// * **Escritorio/móvil:** el de `serve_web.dart` (`WEB_PORT`, 8081 por
///   defecto), ya que `Uri.base` apunta al ejecutable.
int puertoAcceso({Uri? base, bool esWeb = kIsWeb}) {
  final uri = base ?? Uri.base;
  if (esWeb) {
    return uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  }
  return int.tryParse(_puertoWeb) ?? 8081;
}

/// URL de acceso desde el celular para [host] en el [puerto] dado.
///
/// Los puertos por defecto (80/443) se omiten para que la URL quede limpia.
String urlAcceso(String host, {required int puerto, String esquema = 'http'}) {
  final porDefecto = esquema == 'https' ? 443 : 80;
  final autoridad = puerto == porDefecto ? host : '$host:$puerto';
  return '$esquema://$autoridad';
}

/// `true` si [host] solo sirve en la propia máquina (inútil desde el celular).
bool hostEsLocal(String host) =>
    host.isEmpty ||
    host == 'localhost' ||
    host == '127.0.0.1' ||
    host == '::1' ||
    host == '0.0.0.0';

/// IP que Windows asigna al **punto de acceso** (hotspot) de la PC.
///
/// Es la subred por defecto de ICS: la misma en cualquier equipo y en
/// cualquier red, no es la IP de ninguna máquina concreta. El backend declara
/// el mismo valor (`routes.dart`), porque la API no expone una bandera por
/// interfaz y el QR la detecta solo con `GET /api/v1/network`.
const String ipPuntoAcceso = '192.168.137.1';

/// `true` si [host] es el punto de acceso de la PC: el celular conectado a él
/// solo alcanza esta IP, así que el QR debe priorizarla.
bool esPuntoAcceso(String host) => host == ipPuntoAcceso;

/// IP del punto de acceso si está encendido; `null` si está apagado o la API
/// no respondió.
///
/// Lee `GET /api/v1/network` (público, sin sesión): si entre las interfaces
/// activas aparece [ipPuntoAcceso], el hotspot está encendido. La usa la
/// pantalla «Ajustes» para mostrar el estado sin llamar a otro endpoint.
Future<String?> ipPuntoAccesoActivo() async {
  try {
    final datos = await ApiClient().get('/api/v1/network');
    if (datos is Map<String, dynamic> && datos['ipv4'] is List) {
      for (final ip in datos['ipv4'] as List) {
        if (ip is String && esPuntoAcceso(ip)) return ip;
      }
    }
  } on Exception {
    // Sin backend no hay forma de saberlo: se reporta como apagado.
  }
  return null;
}

/// Candidata de URL de acceso desde el celular.
class CandidataAcceso {
  const CandidataAcceso(this.url, {this.interfaz});

  /// URL completa (con puerto) que debe escanear el celular.
  final String url;

  /// Nombre de la interfaz de la PC que la publica (p. ej. `Wi-Fi`), si la
  /// API lo conoce: se muestra en el chip para no confundir la red activa
  /// con la de otro adaptador (p. ej. un Ethernet sin cable con la IP vieja,
  /// que el sistema sigue listando pero no sirve desde el celular).
  final String? interfaz;

  /// `true` si apunta al punto de acceso de la PC.
  ///
  /// Se deriva de la URL (y no de un parámetro) para que también se
  /// reconozca en `DialogAccesoMovil.urlsIniciales`, el camino que usan los
  /// tests y cualquier llamada que pase las URLs ya resueltas.
  bool get puntoAcceso => esPuntoAcceso(Uri.parse(url).host);
}

/// Etiqueta del chip de [candidata]: `Wi-Fi · 192.168.1.25` (o solo el host
/// si no se conoce la interfaz).
///
/// El punto de acceso se etiqueta por su función y no por el nombre del
/// adaptador (que Windows suele poner «Conexión de red local* 2»): así se
/// distingue de un vistazo de qué red tiene que conectarse el celular.
String etiquetaCandidata(CandidataAcceso candidata) {
  final host = Uri.parse(candidata.url).host;
  if (candidata.puntoAcceso) return 'Punto de acceso · $host';
  final nombre = candidata.interfaz;
  return (nombre == null || nombre.isEmpty) ? host : '$nombre · $host';
}

/// Reordena [candidatas] poniendo primero el punto de acceso, si hay, y
/// conservando el orden del resto.
///
/// Hace falta porque el backend antepone la interfaz de la ruta por defecto
/// (la Wi-Fi con internet): con el hotspot encendido, ese orden deja el QR
/// apuntando a una subred a la que el celular conectado al hotspot no llega.
List<CandidataAcceso> ordenarCandidatas(List<CandidataAcceso> candidatas) => [
  for (final candidata in candidatas)
    if (candidata.puntoAcceso) candidata,
  for (final candidata in candidatas)
    if (!candidata.puntoAcceso) candidata,
];

/// Candidatas a URL del sistema accesible desde el celular, en orden de
/// preferencia (la primera es la que se muestra en el QR por defecto).
///
/// 1. El host con el que se abrió la página, si ya es una IP de la LAN.
/// 2. Las IPs de la PC que reporta `GET /api/v1/network`, con el nombre de
///    su interfaz; el backend pone primero la red **activa** y descarta los
///    adaptadores desconectados. Si la página se abrió en `localhost`,
///    ésta es la única vía.
/// 3. El host de la página como último recurso (p. ej. `localhost` si el
///    backend no responde).
Future<List<CandidataAcceso>> candidatasAcceso() async {
  final base = Uri.base;
  final esquema = base.scheme == 'https' ? 'https' : 'http';
  final puerto = puertoAcceso(base: base);
  final hostActual = base.host;

  final nombres = <String, String>{};
  final deLaRed = <CandidataAcceso>[];
  try {
    final datos = await ApiClient().get('/api/v1/network');
    if (datos is Map<String, dynamic>) {
      // Nombre de interfaz por IP (para etiquetar los chips).
      final interfaces = datos['interfaces'];
      if (interfaces is List) {
        for (final interfaz in interfaces) {
          if (interfaz is! Map) continue;
          final nombre = interfaz['name'];
          final ips = interfaz['ipv4'];
          if (nombre is! String || ips is! List) continue;
          for (final ip in ips) {
            if (ip is String) nombres[ip] = nombre;
          }
        }
      }
      if (datos['ipv4'] is List) {
        for (final ip in (datos['ipv4'] as List)) {
          if (ip is! String) continue;
          deLaRed.add(
            CandidataAcceso(
              urlAcceso(ip, puerto: puerto, esquema: esquema),
              interfaz: nombres[ip],
            ),
          );
        }
      }
    }
  } on Exception {
    // Sin backend no hay IP: se cae al host de la página (ver orden abajo).
  }

  final hosts = <String>{};
  if (!hostEsLocal(hostActual)) hosts.add(hostActual);
  hosts.addAll([for (final candidata in deLaRed) Uri.parse(candidata.url).host]);
  if (hostEsLocal(hostActual) && hostActual.isNotEmpty) hosts.add(hostActual);

  return ordenarCandidatas([
    for (final host in hosts)
      CandidataAcceso(
        urlAcceso(host, puerto: puerto, esquema: esquema),
        interfaz: nombres[host],
      ),
  ]);
}

/// Comodidad: solo las URLs de [candidatasAcceso], en el mismo orden.
Future<List<String>> urlsAcceso() async =>
    [for (final candidata in await candidatasAcceso()) candidata.url];

/// Botón de la esquina superior derecha: abre el diálogo con el QR para que
/// el celular abra el sistema por la red local.
class QrAccesoButton extends StatelessWidget {
  const QrAccesoButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Abrir en el celular',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => const DialogAccesoMovil(),
      ),
      icon: const Icon(Icons.qr_code_2_rounded, color: AppColors.textPrimary),
    );
  }
}

/// Diálogo con el QR grande, la URL (copiable) y las IP candidatas.
class DialogAccesoMovil extends StatefulWidget {
  const DialogAccesoMovil({super.key, this.urlsIniciales});

  /// Pruebas: URLs ya resueltas, sin consultar la red.
  final List<String>? urlsIniciales;

  @override
  State<DialogAccesoMovil> createState() => _DialogAccesoMovilState();
}

class _DialogAccesoMovilState extends State<DialogAccesoMovil> {
  List<CandidataAcceso>? _candidatas;
  CandidataAcceso? _elegida;

  @override
  void initState() {
    super.initState();
    final iniciales = widget.urlsIniciales;
    if (iniciales != null) {
      final candidatas = ordenarCandidatas([
        for (final url in iniciales) CandidataAcceso(url),
      ]);
      _candidatas = candidatas;
      _elegida = candidatas.isEmpty ? null : candidatas.first;
    } else {
      candidatasAcceso().then(_asignar, onError: (_) => _asignar(const []));
    }
  }

  void _asignar(List<CandidataAcceso> candidatas) {
    if (!mounted) return;
    // El punto de acceso va primero (ver `ordenarCandidatas`): es la única
    // red a la que llega el celular conectado a él.
    final ordenadas = ordenarCandidatas(candidatas);
    setState(() {
      _candidatas = ordenadas;
      _elegida = ordenadas.isEmpty ? null : ordenadas.first;
    });
  }

  Future<void> _copiar() async {
    final elegida = _elegida;
    if (elegida == null) return;
    await Clipboard.setData(ClipboardData(text: elegida.url));
    if (!mounted) return;
    await alertaInfo(
      context,
      titulo: 'Copiada',
      mensaje: 'URL copiada al portapapeles',
    );
  }

  @override
  Widget build(BuildContext context) {
    final candidatas = _candidatas;

    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      title: const Text(
        'Abrir en el celular',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 320,
        child: candidatas == null
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            // En una ventana baja el bloque (chips + QR + avisos) no cabe y
            // el `Column` desborda: al ser scrollable se ve entero igual.
            : SingleChildScrollView(child: _contenido(candidatas)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _contenido(List<CandidataAcceso> candidatas) {
    final elegida = _elegida;
    if (elegida == null) {
      return const Text(
        'No se pudo detectar la IP de la PC. Levanta el backend para que '
        'responda GET /api/v1/network.',
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      );
    }

    final url = elegida.url;
    final host = Uri.parse(url).host;
    final esLocal = hostEsLocal(host);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (candidatas.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final candidata in candidatas)
                  ChoiceChip(
                    // Con el nombre de la interfaz (Wi-Fi/Ethernet) no se
                    // confunde la red activa con la de otro adaptador.
                    label: Text(etiquetaCandidata(candidata)),
                    selected: candidata.url == url,
                    selectedColor: AppColors.brandGreen,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: candidata.url == url
                          ? Colors.white
                          : AppColors.textPrimary,
                    ),
                    onSelected: (_) => setState(() => _elegida = candidata),
                  ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: QrImageView(data: url, size: 200),
        ),
        const SizedBox(height: 12),
        SelectableText(
          url,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Escanea con la cámara del celular (o Google Lens). La PC y el '
          'celular deben estar en la misma red (Wi-Fi de la casa o punto de '
          'acceso de la PC).',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        if (candidatas.any((candidata) => candidata.puntoAcceso))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Punto de acceso activo: si el celular no tiene internet, '
              'conéctate a esa red antes de escanear.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.brandGreen),
            ),
          ),
        if (esLocal)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '⚠ Esta URL solo funciona en la PC: el backend no respondió '
              'GET /api/v1/network.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),
        TextButton.icon(
          onPressed: _copiar,
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copiar URL'),
        ),
      ],
    );
  }
}
