import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failure.dart';
import '../../core/network/api_client.dart';
import '../../core/permisos.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ajustes_scope.dart';
import '../../core/widgets/alertas.dart';
import '../../core/widgets/qr_acceso.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/sesion_scope.dart';
import '../../core/widgets/sidebar.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/chat_controller.dart';
import '../controllers/load_state.dart';
import '../controllers/recurso_controller.dart';
import '../controllers/respaldos_controller.dart';
import '../widgets/activacion_suscripcion.dart';
import '../widgets/campo_imagen.dart';
import '../widgets/desplegable_buscable.dart';
import '../widgets/opciones_formulario.dart';
import '../widgets/recurso_form.dart';
import '../widgets/vistas_estado.dart';
import 'catalogo_page.dart';

/// Ajustes globales del sistema: los valores con los que arrancan ventas,
/// catálogo, tablas y avisos.
///
/// Todo son desplegables con **su valor por defecto ya puesto** (el mismo
/// comportamiento que tenía la app antes de existir esta pantalla), así que
/// entrar aquí sin tocar nada y guardar no cambia nada.
///
/// Solo una cuenta con el permiso `ajustes.editar` puede moverlos: el resto
/// ve la pantalla
/// en solo lectura para saber qué está configurado. La escritura se comprueba
/// **también** en el backend (`PUT /api/v1/ajustes` devuelve `403`).
///
/// Los valores se guardan en la tabla `Ajustes` de la BD, así que son los
/// mismos en web, en el `.exe` y en la APK, y en cualquier equipo que entre.
class AjustesPage extends StatefulWidget {
  const AjustesPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  State<AjustesPage> createState() => _AjustesPageState();
}

class _AjustesPageState extends State<AjustesPage> {
  /// Valores en pantalla: los guardados superpuestos a los de fábrica.
  final Map<String, String> _valores = Map<String, String>.of(Ajustes.defectos);

  /// ¿Ya se copió lo guardado a [_valores]?
  bool _inicializado = false;

  /// Evita guardar dos veces mientras la petición va en vuelo.
  bool _guardando = false;

  /// Evita pulsar «Respaldar ahora» dos veces mientras `pg_dump` trabaja.
  bool _respaldando = false;

  /// ¿Ya se pidió el listado de respaldos? (solo si la cuenta puede verlo)
  bool _respaldosPrecargados = false;

  /// IP del punto de acceso si está encendido; `null` = apagado o sin saberse
  /// todavía (la primera consulta se lanza al montar la pantalla).
  String? _ipPuntoAcceso;

  /// `true` mientras se intenta encender el punto de acceso.
  bool _encendiendoPuntoAcceso = false;

  /// Estado de la suscripción (`GET /ajustes/suscripcion`): `null` hasta
  /// que se lee, luego `libre` / `activa` / `bloqueada`.
  String? _estadoSuscripcion;

  /// Fecha de vencimiento guardada (`'siempre'`, `yyyy-MM-dd` o vacía).
  String _venceSuscripcion = '';

  /// Sondeo del progreso de descarga del modelo: solo mientras hay una en
  /// marcha (la descarga la lanza esta pantalla y la UI necesita verla moverse).
  Timer? _sondeoDescarga;

  @override
  void initState() {
    super.initState();
    // Los catálogos que alimentan los desplegables se piden tras el
    // primer frame (mismo criterio que el resto de páginas: sin spinner).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _precargar(context.read<AjustesController>());
      _precargar(context.read<ClientesController>());
      _precargar(context.read<EmpleadosController>());
      // Los catálogos que alimentan los desplegables de «valor por defecto»
      // (categoría, presentación, proveedor y rol de un producto o usuario).
      _precargar(context.read<CategoriasController>());
      _precargar(context.read<PresentacionesController>());
      _precargar(context.read<ProveedoresController>());
      _precargar(context.read<RolesController>());
      // Estado del punto de acceso (Windows): si ya está encendido, la
      // pantalla lo enseña sin que nadie tenga que pulsar nada.
      _consultarPuntoAcceso();
      // El estado del asistente (Ollama + modelo) también se pide aquí: la
      // burbuja lo pide al entrar en sesión, pero hay que poder refrescarlo
      // cuando se vuelve de instalar Ollama.
      context.read<ChatController>().cargarEstado();
      // Estado de la suscripción para la sección correspondiente.
      _cargarSuscripcion();
    });
  }

  @override
  void dispose() {
    _sondeoDescarga?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // El listado de respaldos depende del permiso `ajustes.ver`, que solo se
    // conoce con la sesión: se mira aquí (primer ciclo con el scope) y una
    // sola vez, para no repetir el GET en cada reconstrucción.
    if (_respaldosPrecargados) return;
    final sesion = SesionScope.de(context);
    if (sesion == null) return;
    _respaldosPrecargados = true;
    if (!sesion.puede(Modulos.ajustes, Acciones.ver)) return;
    // Tras el frame: `cargar()` avisa a sus oyentes de inmediato y eso no
    // puede pasar dentro de build (mismo motivo que los otros precargas).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _precargar(context.read<RespaldosController>());
    });
  }

  void _precargar(RecursoController controlador) {
    if (controlador.state == LoadState.initial) controlador.cargar();
  }

  /// Lee `GET /api/v1/network` y deja en [_ipPuntoAcceso] la IP del punto de
  /// acceso si está encendido.
  Future<void> _consultarPuntoAcceso() async {
    final ip = await ipPuntoAccesoActivo();
    if (!mounted) return;
    setState(() => _ipPuntoAcceso = ip);
  }

  /// Lee `GET /api/v1/ajustes/suscripcion` (vigencia de la licencia).
  Future<void> _cargarSuscripcion() async {
    try {
      final respuesta = await context
          .read<ApiClient>()
          .get('/api/v1/ajustes/suscripcion');
      if (!mounted || respuesta is! Map) return;
      setState(() {
        _estadoSuscripcion = respuesta['estado']?.toString() ?? 'libre';
        _venceSuscripcion = respuesta['vence']?.toString() ?? '';
      });
    } catch (_) {
      // Sin la vigencia la sección se queda en «Comprobando…»: no es
      // motivo para tumbar la pantalla de Ajustes.
      if (mounted) setState(() => _estadoSuscripcion = 'desconocido');
    }
  }

  /// Enciende el punto de acceso (`POST /api/v1/network/hotspot`) y refresca
  /// el estado.
  ///
  /// Si Windows no lo acepta desde aquí, la API devuelve
  /// `accion: abrir_ajustes` tras haber abierto su página de configuración:
  /// se avisa para que solo falte el interruptor.
  Future<void> _activarPuntoAcceso() async {
    if (_encendiendoPuntoAcceso) return;
    setState(() => _encendiendoPuntoAcceso = true);

    String? aviso;
    try {
      final api = context.read<ApiClient>();
      final respuesta = await api.post('/api/v1/network/hotspot');
      if (respuesta is Map && respuesta['accion'] == 'abrir_ajustes') {
        aviso =
            'Windows no pudo encenderlo desde aquí y se han abierto sus '
            'Ajustes. Solo enciende el punto de acceso si la PC está '
            'conectada a alguna red (no hace falta que haya internet): si lo '
            'muestra desactivado con un aviso rojo, conéctate a cualquier '
            'Wi-Fi o Ethernet y vuelve a pulsar «Activar punto de acceso».';
      }
    } on Failure catch (failure) {
      if (mounted) setState(() => _encendiendoPuntoAcceso = false);
      if (mounted) await alertaError(context, mensaje: failure.message);
      return;
    } catch (_) {
      if (mounted) setState(() => _encendiendoPuntoAcceso = false);
      if (mounted) {
        await alertaError(context, mensaje: 'No se pudo encender el punto de acceso');
      }
      return;
    }

    await _consultarPuntoAcceso();
    if (!mounted) return;
    setState(() => _encendiendoPuntoAcceso = false);
    if (aviso != null) {
      await alertaInfo(context, titulo: 'Punto de acceso', mensaje: aviso);
    }
  }

  /// Copia los ajustes guardados a la pantalla (una sola vez, cuando el
  /// listado ya viene de la API; en error se quedan los de fábrica).
  void _sincronizar(AjustesController controlador) {
    if (_inicializado) return;
    if (controlador.state != LoadState.loaded) {
      if (controlador.state == LoadState.error) _inicializado = true;
      return;
    }
    _valores
      ..clear()
      ..addAll(Ajustes.defectos)
      ..addAll(controlador.valores);
    _inicializado = true;
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      await context.read<AjustesController>().guardar(
        Map<String, String>.of(_valores),
      );
      if (!mounted) return;
      await alertaExito(
        context,
        titulo: 'Ajustes guardados',
        mensaje: 'El sistema usará estos valores de ahora en adelante.',
      );
    } on Failure catch (failure) {
      if (!mounted) return;
      await alertaError(context, mensaje: failure.message);
    } catch (_) {
      if (!mounted) return;
      await alertaError(context, mensaje: 'No se pudieron guardar los ajustes');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Genera un `.dump` en el servidor con `pg_dump`.
  Future<void> _respaldar() async {
    if (_respaldando) return;
    setState(() => _respaldando = true);
    try {
      await context.read<RespaldosController>().respaldar();
      if (!mounted) return;
      await alertaExito(
        context,
        titulo: 'Respaldo creado',
        mensaje:
            'La copia ya está en la carpeta de respaldos del servidor. '
            'Puedes bajártela desde la lista.',
      );
    } on Failure catch (failure) {
      if (!mounted) return;
      await alertaError(context, mensaje: failure.message);
    } catch (_) {
      if (!mounted) return;
      await alertaError(context, mensaje: 'No se pudo crear el respaldo');
    } finally {
      if (mounted) setState(() => _respaldando = false);
    }
  }

  /// Baja el respaldo al equipo: hoja de compartir en el celular, diálogo
  /// «Guardar como» en escritorio y descarga del navegador en web.
  Future<void> _descargar(String nombre) async {
    try {
      await context.read<RespaldosController>().descargar(nombre);
    } on UnsupportedError {
      if (!mounted) return;
      await alertaInfo(
        context,
        titulo: 'Descarga no disponible',
        mensaje:
            'Esta plataforma no deja guardar ficheros. El respaldo '
            '«$nombre» ya está en la carpeta de respaldos del servidor.',
      );
    } on Failure catch (failure) {
      if (!mounted) return;
      await alertaError(context, mensaje: failure.message);
    } catch (_) {
      if (!mounted) return;
      await alertaError(context, mensaje: 'No se pudo descargar el respaldo');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      title: 'Ajustes',
      contentBuilder: (context, constraints) => _contenido(context),
    );
  }

  Widget _contenido(BuildContext context) {
    final ajustes = context.watch<AjustesController>();
    final respaldos = context.watch<RespaldosController>();
    final clientes = context.watch<ClientesController>();
    final empleados = context.watch<EmpleadosController>();
    final categorias = context.watch<CategoriasController>();
    final presentaciones = context.watch<PresentacionesController>();
    final proveedores = context.watch<ProveedoresController>();
    final roles = context.watch<RolesController>();
    _sincronizar(ajustes);

    // Estado 1: cargando.
    if (ajustes.cargando) return const VistaCargando();

    // Estado 2: error + Reintentar.
    if (ajustes.state == LoadState.error) {
      return VistaError(
        mensaje: ajustes.errorMessage ?? 'Error desconocido',
        onReintentar: ajustes.recargar,
      );
    }

    final sesion = SesionScope.de(context);
    final puedeEditar =
        sesion?.puede(Modulos.ajustes, Acciones.editar) ?? false;
    // El listado de respaldos se pide solo a quien tenga `ajustes.ver`: sin
    // permiso, la API respondería 403 y la sección se llenaría de errores.
    final verRespaldos = sesion?.puede(Modulos.ajustes, Acciones.ver) ?? false;

    // Si se entra con una descarga ya en marcha (p. ej. lanzada desde la
    // burbuja), el panel vuelve a sondearla desde aquí.
    if (context.read<ChatController>().estado.descargando) {
      _iniciarSondeoDescarga();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Ajustes del sistema',
          buttonLabel: puedeEditar ? 'Guardar' : null,
          buttonIcon: Icons.save_rounded,
          onButtonPressed: puedeEditar ? _guardar : null,
        ),
        const SizedBox(height: 8),
        const Text(
          'Valores con los que arranca cada módulo. Están guardados en la '
          'base de datos: valen igual en web, escritorio y móvil.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        if (!puedeEditar) _avisoSoloLectura(),
        _grupo('Uso diario'),
        _seccion(
          titulo: 'Ventas por defecto',
          icono: Icons.point_of_sale_rounded,
          auxiliar: 'Cómo arrancan el carrito del catálogo y «Nueva Orden».',
          hijos: [
            _campo(
              clave: Ajustes.vendedorPorDefecto,
              etiqueta: 'Vendedor por defecto *',
              auxiliar: 'Vacío = la cuenta conectada.',
              opciones: _opcionesVendedores(empleados, sesion),
              habilitado: puedeEditar,
            ),
            _campo(
              clave: Ajustes.clientePorDefecto,
              etiqueta: 'Cliente por defecto',
              auxiliar: 'Vacío = «— Cliente ocasional —».',
              opciones: _opcionesClientes(clientes),
              habilitado: puedeEditar,
            ),
            _campo(
              clave: Ajustes.tipoPagoPorDefecto,
              etiqueta: 'Tipo de pago por defecto *',
              auxiliar: 'El que aparece marcado en los dos formularios.',
              opciones: tiposPago,
              habilitado: puedeEditar,
            ),
            SubidorImagen(
              valor: _valores[Ajustes.qrPago] ?? '',
              etiqueta: 'Imagen del QR de pago',
              auxiliar:
                  'PNG o JPG del QR de tu billetera: es el que se muestra '
                  'al cobrar con QR (se comprime si pesa más de 3 MB).',
              soloLectura: !puedeEditar,
              onSubido: (ruta) => setState(() => _valores[Ajustes.qrPago] = ruta),
              onQuitar: () => setState(() => _valores[Ajustes.qrPago] = ''),
            ),
          ],
        ),
        _seccion(
          titulo: 'Identidad del negocio',
          icono: Icons.local_pharmacy_rounded,
          auxiliar:
              'Nombre del negocio que aparece en los PDF (recibos y '
              'cotizaciones) y en el cierre de sesión.',
          hijos: [
            _campoTexto(
              clave: Ajustes.nombreFarmacia,
              etiqueta: 'Nombre de la farmacia',
              auxiliar: 'Ej.: Farmacia San Rafael.',
              habilitado: puedeEditar,
            ),
          ],
        ),
        _seccion(
          titulo: 'Catálogo y tablas',
          icono: Icons.storefront_rounded,
          auxiliar: 'Orden de la vitrina y densidad de los listados.',
          hijos: [
            _campo(
              clave: Ajustes.ordenCatalogo,
              etiqueta: 'Orden por defecto del catálogo',
              auxiliar: 'Con el que se abre la vitrina.',
              opciones: [
                for (final (clave, etiqueta) in ordenesCatalogo)
                  Opccion(clave, etiqueta),
              ],
              habilitado: puedeEditar,
            ),
            _campo(
              clave: Ajustes.porPagina,
              etiqueta: 'Filas por página (tablas)',
              auxiliar: 'Afecta a todos los listados del sistema.',
              opciones: _opcionesNumeros([
                '5',
                '10',
                '20',
                '30',
                '50',
              ], sufijo: ' filas'),
              habilitado: puedeEditar,
            ),
          ],
        ),
        _seccion(
          titulo: 'Valores por defecto de los formularios',
          icono: Icons.edit_note_rounded,
          auxiliar:
              'Con lo que arranca cada campo al dar de alta un registro. '
              '«— Sin valor por defecto —» deja el campo vacío y, si es '
              'obligatorio, lo pide el formulario antes de guardar.',
          hijos: _camposDefecto(
            puedeEditar: puedeEditar,
            categorias: categorias,
            presentaciones: presentaciones,
            proveedores: proveedores,
            roles: roles,
            empleados: empleados,
          ),
        ),
        _seccion(
          titulo: 'Avisos del dashboard',
          icono: Icons.notifications_active_rounded,
          auxiliar:
              'Umbrales de la tarjeta «Alertas» y del gráfico de '
              'vencimientos.',
          hijos: [
            _campo(
              clave: Ajustes.stockMinimo,
              etiqueta: 'Stock mínimo',
              auxiliar: 'Por debajo de estas unidades se marca «Stock bajo».',
              opciones: _opcionesNumeros([
                '0',
                '1',
                '3',
                '5',
                '10',
                '15',
                '20',
              ], sufijo: ' unidades'),
              habilitado: puedeEditar,
            ),
            _campo(
              clave: Ajustes.diasVencimiento,
              etiqueta: 'Días de aviso de vencimiento',
              auxiliar: 'Antelación con la que se cuenta «por vencer».',
              opciones: _opcionesNumeros([
                '7',
                '15',
                '30',
                '60',
                '90',
                '180',
              ], sufijo: ' días'),
              habilitado: puedeEditar,
            ),
          ],
        ),
        _seccion(
          titulo: 'Navegación',
          icono: Icons.explore_rounded,
          auxiliar: 'Módulo que se abre al entrar en la aplicación.',
          hijos: [
            _campo(
              clave: Ajustes.paginaInicial,
              etiqueta: 'Página inicial',
              auxiliar: 'Se aplica la próxima vez que se inicie sesión.',
              opciones: [
                for (var i = 0; i < navItems.length; i++)
                  Opccion('$i', navItems[i].label),
              ],
              habilitado: puedeEditar,
            ),
          ],
        ),
        _grupo('Sistema'),
        _seccion(
          titulo: 'Asistente IA',
          icono: Icons.smart_toy_outlined,
          auxiliar:
              'Burbuja de ayuda en todas las pantallas. Funciona en local: '
              'ni los datos ni las preguntas salen de tu equipo.',
          hijos: [
            _campoRoles(habilitado: puedeEditar, roles: roles),
            _campo(
              clave: Ajustes.burbujaIA,
              etiqueta: 'Burbuja del asistente',
              auxiliar:
                  'El botón flotante en todas las pantallas (en celular '
                  'ocupa pantalla).',
              opciones: const [
                Opccion('1', 'Visible'),
                Opccion('0', 'Oculta'),
              ],
              habilitado: puedeEditar,
            ),
            _panelAsistente(puedeEditar: puedeEditar),
          ],
        ),
        _seccion(
          titulo: 'Punto de acceso (celular sin internet)',
          icono: Icons.wifi_tethering_rounded,
          auxiliar:
              'Si no hay internet, la PC puede compartir su propia red y el '
              'celular entra por el QR. Solo en Windows, y exige que la PC '
              'esté conectada a alguna red (no hace falta internet).',
          hijos: [_panelPuntoAcceso(puedeEditar: puedeEditar)],
        ),
        if (verRespaldos)
          _seccion(
            titulo: 'Respaldos de la base de datos',
            icono: Icons.save_alt_rounded,
            auxiliar:
                'Copia de seguridad en formato .dump (se restaura con '
                'pg_restore). Se guarda en la carpeta de respaldos del '
                'servidor.',
            hijos: [
              _campo(
                clave: Ajustes.respaldoIntervalo,
                etiqueta: 'Respaldo automático',
                auxiliar:
                    'Cada cuánto se crea una copia sin que nadie lo pida.',
                opciones: const [
                  Opccion('0', '— Solo manual —'),
                  Opccion('1440', 'Cada día'),
                  Opccion('10080', 'Cada semana'),
                  Opccion('43200', 'Cada mes'),
                ],
                habilitado: puedeEditar,
              ),
              _panelRespaldos(respaldos, puedeEditar: puedeEditar),
            ],
          ),
        _seccion(
          titulo: 'Suscripción',
          icono: Icons.verified_user_rounded,
          auxiliar:
              'Licencia de uso de este equipo. Con la clave del programador '
              'se activa por 1 semana, 1 mes o para siempre.',
          hijos: [_panelSuscripcion()],
        ),
      ],
    );
  }

  // --- Opciones -------------------------------------------------------------

  List<Opccion> _opcionesVendedores(
    EmpleadosController empleados,
    DatosSesion? sesion,
  ) {
    final vendedores = vendedoresDe(
      empleados.items,
      sesion: sesion?.usuario.empleadoId,
    );
    return [
      const Opccion('', '— Usar la cuenta conectada —'),
      ...opcionesDe(vendedores),
    ];
  }

  List<Opccion> _opcionesClientes(ClientesController clientes) => [
    const Opccion('', '— Cliente ocasional —'),
    ...opcionesDe(clientes.items),
  ];

  /// Desplegables de la sección «Valores por defecto de los formularios».
  ///
  /// Cada uno abre con «— Sin valor por defecto —» y después las mismas
  /// opciones que su campo en el formulario (compartidas con las páginas vía
  /// `opciones_formulario.dart`), de modo que lo que se puede elegir aquí es
  /// exactamente lo que se puede elegir allí.
  ///
  /// Las opciones dinámicas (categoría, presentación, proveedor, rol y
  /// empleado) llegan con los catálogos precargados en `initState`; el
  /// `ValueKey` de [_campo] con la longitud de la lista hace que el
  /// desplegable se remonte cuando entran, así que un valor guardado que
  /// todavía no estaba en la lista no se pisa ni se pierde al guardar.
  List<Widget> _camposDefecto({
    required bool puedeEditar,
    required CategoriasController categorias,
    required PresentacionesController presentaciones,
    required ProveedoresController proveedores,
    required RolesController roles,
    required EmpleadosController empleados,
  }) {
    // Todas empiezan por la opción vacía = «sin valor por defecto».
    List<Opccion> con(List<Opccion> base) => [
      const Opccion('', '— Sin valor por defecto —'),
      ...base,
    ];

    Widget campo(
      String entidad,
      String idCampo,
      String etiqueta,
      List<Opccion> opciones,
    ) => _campo(
      clave: Ajustes.claveDefecto(entidad, idCampo),
      etiqueta: etiqueta,
      auxiliar: 'Vacío = elegirlo en cada alta.',
      opciones: opciones,
      habilitado: puedeEditar,
    );

    return [
      // --- Productos ---
      campo('producto', 'estado', 'Estado · Producto', con(estadosProducto)),
      campo(
        'producto',
        'categoriaId',
        'Categoría · Producto',
        con(opcionesDe(categorias.items)),
      ),
      campo(
        'producto',
        'presentacionId',
        'Presentación · Producto',
        con(opcionesDe(presentaciones.items)),
      ),
      campo(
        'producto',
        'proveedorId',
        'Proveedor · Producto',
        con(opcionesDe(proveedores.items)),
      ),
      // --- Usuarios ---
      campo('usuario', 'estado', 'Estado · Usuario', con(estadosGenerales)),
      campo('usuario', 'rolId', 'Rol · Usuario', con(opcionesDe(roles.items))),
      campo(
        'usuario',
        'empleadoId',
        'Empleado · Usuario',
        con(opcionesDe(empleados.items)),
      ),
      // --- Catálogos ---
      campo('categoria', 'estado', 'Estado · Categoría', con(estadosGenerales)),
      campo(
        'presentacion',
        'estado',
        'Estado · Presentación',
        con(estadosGenerales),
      ),
      campo(
        'proveedor',
        'estado',
        'Estado · Proveedor',
        con(estadosGenerales),
      ),
      // --- Personas ---
      campo('cliente', 'estado', 'Estado · Cliente', con(estadosGenerales)),
      campo('cliente', 'genero', 'Género · Cliente', con(generos)),
      campo('empleado', 'estado', 'Estado · Empleado', con(estadosEmpleados)),
    ];
  }

  /// Números con su unidad (`10 filas`, `90 días`…), en el orden dado.
  List<Opccion> _opcionesNumeros(
    List<String> valores, {
    required String sufijo,
  }) => [for (final valor in valores) Opccion(valor, '$valor$sufijo')];

  /// Valor mostrado en un desplegable: lo que hay en pantalla si sigue
  /// siendo una opción válida; si no, el de fábrica (y si tampoco, la
  /// primera). Así un valor guardado con una versión antigua no se enseña
  /// como texto suelto.
  String _elegido(String clave, List<Opccion> opciones) {
    final actual = _valores[clave] ?? '';
    if (opciones.any((opcion) => opcion.valor == actual)) return actual;
    final defecto = Ajustes.defectos[clave] ?? '';
    if (opciones.any((opcion) => opcion.valor == defecto)) return defecto;
    return opciones.isEmpty ? '' : opciones.first.valor;
  }

  // --- Pintura --------------------------------------------------------------

  Widget _campo({
    required String clave,
    required String etiqueta,
    required String auxiliar,
    required List<Opccion> opciones,
    required bool habilitado,
  }) {
    return SizedBox(
      width: 320,
      child: DesplegableBuscable(
        // Las claves `defecto.*` traen opciones dinámicas que llegan con los
        // catálogos: si el desplegable no se remonta al crecer la lista, se
        // quedaría con el `initialValue` del primer pintado (vacío) y un
        // «Guardar» reescribiría el valor guardado. La longitud de las
        // opciones identifica cada versión.
        key: clave.startsWith('defecto.')
            ? ValueKey('$clave#${opciones.length}')
            : null,
        initialValue: _elegido(clave, opciones),
        opciones: opciones,
        habilitado: habilitado,
        decoracion: InputDecoration(
          labelText: etiqueta,
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
        ),
        onChanged: habilitado
            ? (valor) => setState(
                () => _valores[clave] = valor ?? Ajustes.defectos[clave] ?? '',
              )
            : null,
      ),
    );
  }

  /// Campo de texto libre (mismo aspecto que [_campo], para valores como el
  /// nombre de la farmacia que no son un desplegable).
  Widget _campoTexto({
    required String clave,
    required String etiqueta,
    required String auxiliar,
    required bool habilitado,
  }) {
    return SizedBox(
      width: 320,
      child: TextFormField(
        initialValue: _valores[clave] ?? Ajustes.defectos[clave] ?? '',
        enabled: habilitado,
        onChanged: (valor) => setState(() => _valores[clave] = valor),
        decoration: InputDecoration(
          labelText: etiqueta,
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
        ),
      ),
    );
  }

  /// Vigencia de la licencia + formulario de activación (la clave se
  /// valida en el servidor; aquí solo se pinta lo que devuelve la API).
  Widget _panelSuscripcion() {
    final texto = switch (_estadoSuscripcion) {
      null => 'Comprobando la suscripción…',
      'libre' => 'Sin suscripción activa: este equipo está en uso libre.',
      'activa' => _venceSuscripcion == 'siempre'
          ? 'Suscripción activa: para siempre.'
          : 'Suscripción activa: vence el $_venceSuscripcion.',
      'bloqueada' => 'Suscripción bloqueada: plazo vencido o fecha incorrecta.',
      _ => 'No se pudo leer el estado de la suscripción.',
    };
    final color = switch (_estadoSuscripcion) {
      'activa' => AppColors.brandGreen,
      'bloqueada' => Colors.red,
      _ => AppColors.textSecondary,
    };

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _estadoSuscripcion == 'activa'
                    ? Icons.verified_rounded
                    : Icons.schedule_rounded,
                size: 17,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  texto,
                  style: TextStyle(fontSize: 13, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 320,
            child: ActivacionSuscripcion(onActivado: _cargarSuscripcion),
          ),
        ],
      ),
    );
  }

  /// Bloque del punto de acceso: estado actual, aviso de uso y botón para
  /// encenderlo.
  ///
  /// El estado se lee de `GET /api/v1/network` ([_ipPuntoAcceso]) y el botón
  /// llama a `POST /api/v1/network/hotspot`; al terminar se vuelve a leer, de
  /// modo que sirve también para refrescar si se encendió a mano desde
  /// Windows.
  Widget _panelPuntoAcceso({required bool puedeEditar}) {
    final activo = _ipPuntoAcceso != null;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                activo
                    ? Icons.wifi_tethering_rounded
                    : Icons.wifi_tethering_off_rounded,
                size: 17,
                color: activo ? AppColors.brandGreen : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  activo
                      ? 'Punto de acceso activo · $_ipPuntoAcceso'
                      : 'Punto de acceso apagado',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Conecta el celular a esa red y pulsa el botón QR de la barra: '
            'la dirección del punto de acceso sale como «Punto de acceso» '
            'y es la única que el celular conectado a ella alcanza.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: puedeEditar && !_encendiendoPuntoAcceso
                ? _activarPuntoAcceso
                : null,
            icon: _encendiendoPuntoAcceso
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering_rounded, size: 17),
            label: Text(
              _encendiendoPuntoAcceso
                  ? 'Encendiendo…'
                  : 'Activar punto de acceso',
            ),
          ),
        ],
      ),
    );
  }

  /// Bloque de respaldos: botón «Respaldar ahora», aviso del último y la
  /// lista de los `.dump` existentes con su descarga.
  Widget _panelRespaldos(
    RespaldosController respaldos, {
    required bool puedeEditar,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: puedeEditar && !_respaldando ? _respaldar : null,
                icon: _respaldando
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt_rounded, size: 18),
                label: Text(_respaldando ? 'Respaldando…' : 'Respaldar ahora'),
              ),
              Text(
                _ultimoRespaldo(respaldos),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._filasRespaldos(respaldos, puedeEditar: puedeEditar),
        ],
      ),
    );
  }

  /// Bloque del asistente: estado de Ollama y del modelo, y el botón de
  /// descarga con su progreso.
  Widget _panelAsistente({required bool puedeEditar}) {
    final chat = context.watch<ChatController>();
    final estado = chat.estado;

    final List<Widget> filas;
    if (estado.ollamaActivo && estado.modeloListo) {
      filas = [
        _filaEstado(
          icono: Icons.check_circle_rounded,
          color: AppColors.positiveGreen,
          texto: 'Listo: ${estado.modelo} está instalado en Ollama.',
        ),
        const Text(
          'Pregunta lo que quieras desde la burbuja de la esquina inferior '
          'derecha.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      ];
    } else if (!estado.ollamaActivo) {
      filas = [
        _filaEstado(
          icono: Icons.error_outline,
          color: AppColors.negativeRed,
          texto: 'No detecto Ollama.',
        ),
        const Text(
          'Instálalo desde ollama.com, arráncalo con «ollama serve» y vuelve '
          'a entrar en esta pantalla.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      ];
    } else {
      filas = [
        _filaEstado(
          icono: Icons.download_outlined,
          color: AppColors.warningOrange,
          texto:
              'Ollama está activo, pero falta el modelo '
              '(${estado.modelo}).',
        ),
      ];
    }

    final descargando = estado.descargando;
    final fallo = estado.fase == 'error';

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...filas,
          const SizedBox(height: 12),
          if (descargando) ...[
            // Sin total conocido la barra pasa a indeterminada: el backend
            // no siempre sabe el `content-length` tras las redirecciones.
            LinearProgressIndicator(
              value: estado.porcentaje != null
                  ? (estado.porcentaje! / 100)
                  : null,
              color: AppColors.brandGreen,
              backgroundColor: AppColors.trackGrey,
              minHeight: 6,
            ),
            const SizedBox(height: 6),
            Text(
              estado.fase == 'creando'
                  ? 'Creando el modelo en Ollama… (puede tardar un par de '
                        'minutos)'
                  : 'Descargando… ${estado.porcentaje ?? '—'}% '
                        '(${_tamanoLegible(estado.bytes)})',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            // Un problema cada vez: si Ollama no está, su aviso es lo único
            // accionable, y el error o el botón de descarga (que terminan en
            // `ollama create`) solo añadirían un segundo aviso del mismo
            // origen. La barra de progreso sí se pinta siempre, porque una
            // descarga en marcha sigue siendo información real.
          ] else if (estado.ollamaActivo && fallo) ...[
            _filaEstado(
              icono: Icons.error_outline,
              color: AppColors.negativeRed,
              texto: estado.descargaError ?? 'La descarga falló.',
            ),
            const SizedBox(height: 8),
            _botonDescarga(chat, puedeEditar: puedeEditar, texto: 'Reintentar'),
          ] else if (estado.ollamaActivo && !estado.modeloListo) ...[
            _botonDescarga(
              chat,
              puedeEditar: puedeEditar,
              texto: 'Descargar Qwen2.5-1.5B (~1 GB, HuggingFace)',
            ),
          ],
        ],
      ),
    );
  }

  Widget _filaEstado({
    required IconData icono,
    required Color color,
    required String texto,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonDescarga(
    ChatController chat, {
    required bool puedeEditar,
    required String texto,
  }) {
    return OutlinedButton.icon(
      onPressed: puedeEditar ? () => _descargarModelo(chat) : null,
      icon: const Icon(Icons.download_rounded, size: 18),
      label: Text(texto),
    );
  }

  /// Lanza la descarga del GGUF y arranca el sondeo de progreso; el error
  /// legible, si lo hay, lo pinta el panel (y además se avisa con un diálogo).
  Future<void> _descargarModelo(ChatController chat) async {
    await chat.descargarModelo();
    if (!mounted) return;
    if (chat.error != null) {
      await alertaError(context, mensaje: chat.error!);
      chat.limpiarError();
      return;
    }
    await alertaInfo(
      context,
      titulo: 'Descarga en marcha',
      mensaje:
          'Está bajando el modelo de HuggingFace (~1 GB). Deja esta ventana '
          'abierta: verás el progreso aquí mismo y, al terminar, Ollama lo '
          'tendrá listo.',
    );
    _iniciarSondeoDescarga();
  }

  /// Mientras la descarga esté en marcha, se pide el progreso cada poco y
  /// se para sola en cuanto termina (o si la pantalla se cierra).
  void _iniciarSondeoDescarga() {
    if (_sondeoDescarga != null) return;
    _sondeoDescarga = Timer.periodic(const Duration(milliseconds: 700), (t) {
      if (!mounted) {
        t.cancel();
        _sondeoDescarga = null;
        return;
      }
      final chat = context.read<ChatController>();
      chat.sondearDescarga();
      if (!chat.estado.descargando) {
        t.cancel();
        _sondeoDescarga = null;
        chat.refrescarModelo();
      }
    });
  }

  /// Estados del listado: vacío, cargando, error con reintento o filas.
  List<Widget> _filasRespaldos(
    RespaldosController respaldos, {
    required bool puedeEditar,
  }) {
    if (respaldos.state == LoadState.loading) {
      return const [SizedBox(height: 4)];
    }
    if (respaldos.state == LoadState.error) {
      return [
        Row(
          children: [
            Expanded(
              child: Text(
                respaldos.errorMessage ?? 'No se pudieron leer los respaldos',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.negativeRed,
                ),
              ),
            ),
            TextButton(
              onPressed: respaldos.recargar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ];
    }
    if (respaldos.vacio) {
      return const [
        Text(
          'Aún no hay respaldos. Pulsa «Respaldar ahora» para crear el primero.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ];
    }
    return [
      for (final respaldo in respaldos.items)
        _filaRespaldo(respaldo, puedeEditar: puedeEditar),
    ];
  }

  Widget _filaRespaldo(Recurso respaldo, {required bool puedeEditar}) {
    final nombre = respaldo.texto('nombre', vacio: '');
    if (nombre.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 16,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nombre,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_tamanoLegible((respaldo.numero('bytes') ?? 0).round())}'
            ' · ${_fechaLegible(respaldo.texto('creado', vacio: ''))}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          IconButton(
            tooltip: 'Descargar',
            icon: const Icon(Icons.download_rounded, size: 18),
            onPressed: puedeEditar ? () => _descargar(nombre) : null,
          ),
        ],
      ),
    );
  }

  /// «Último: 30/09 15:30» (o el aviso de que todavía no hay ninguno).
  String _ultimoRespaldo(RespaldosController respaldos) {
    if (respaldos.state != LoadState.loaded || respaldos.items.isEmpty) {
      return 'Sin respaldos todavía';
    }
    final ultimo = respaldos.items.first;
    return 'Último: ${_fechaLegible(ultimo.texto('creado', vacio: ''))}';
  }

  static String _tamanoLegible(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  /// `2026-09-30T15:30:00.000Z` → `30/09 15:30` (hora local).
  static String _fechaLegible(String iso) {
    final momento = DateTime.tryParse(iso)?.toLocal();
    if (momento == null) return '—';
    String p(int valor) => valor.toString().padLeft(2, '0');
    return '${p(momento.day)}/${p(momento.month)} '
        '${p(momento.hour)}:${p(momento.minute)}';
  }

  Widget _seccion({
    required String titulo,
    required String auxiliar,
    required List<Widget> hijos,
    IconData icono = Icons.tune_rounded,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.brandGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icono, size: 18, color: AppColors.brandGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            auxiliar,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          // `Wrap` en vez de `Row`: en pantallas estrechas los campos
          // saltan de línea en lugar de desbordar.
          Wrap(spacing: 24, runSpacing: 20, children: hijos),
        ],
      ),
    );
  }

  /// Rótulo de grupo: separa los bloques de secciones («Uso diario» /
  /// «Sistema») para que la página se lea por zonas y no como un muro
  /// infinito de tarjetas.
  Widget _grupo(String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 14),
      child: Text(
        texto.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  /// Roles elegidos para usar la IA (`iaRoles`): vacío = todos.
  Set<String> _rolesIaElegidos() => {
    for (final rol in (_valores[Ajustes.iaRoles] ?? '').split(','))
      if (rol.trim().isNotEmpty) rol.trim(),
  };

  /// Selección múltiple de roles con chips: «Todos» (lista vacía) o los
  /// marcados, guardados como `ADMIN,CAJERO`.
  ///
  /// Muestra también un rol elegido que ya no exista en la tabla (rol
  /// borrado): así «Guardar» no lo pierde en silencio.
  Widget _campoRoles({required bool habilitado, required RolesController roles}) {
    final elegidos = _rolesIaElegidos();
    final nombres = <String>{
      for (final rol in roles.items) rol.texto('nombre', vacio: ''),
      ...elegidos,
    }..remove('');

    void alternar(String rol, bool marcar) {
      setState(() {
        final actuales = _rolesIaElegidos();
        marcar ? actuales.add(rol) : actuales.remove(rol);
        _valores[Ajustes.iaRoles] = actuales.join(',');
      });
    }

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Roles que pueden usar el asistente',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sin ninguno marcado puede usarlo cualquier rol. La burbuja se '
            'oculta en los roles que no estén en la lista.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('Todos'),
                selected: elegidos.isEmpty,
                onSelected: habilitado
                    ? (_) => setState(() => _valores[Ajustes.iaRoles] = '')
                    : null,
                selectedColor: AppColors.brandGreen.withValues(alpha: 0.16),
                checkmarkColor: AppColors.brandGreen,
              ),
              for (final rol in nombres)
                FilterChip(
                  label: Text(rol),
                  selected: elegidos.contains(rol),
                  onSelected: habilitado
                      ? (marcar) => alternar(rol, marcar)
                      : null,
                  selectedColor: AppColors.brandGreen.withValues(alpha: 0.16),
                  checkmarkColor: AppColors.brandGreen,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avisoSoloLectura() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoBlue),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.infoBlue),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Solo una cuenta con el permiso ajustes.editar puede modificar '
              'los ajustes. '
              'Se muestran en solo lectura.',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
