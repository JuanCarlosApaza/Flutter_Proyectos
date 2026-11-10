import '../../core/errors/app_exception.dart';
import '../entities/ajuste.dart';
import '../repositories/ajuste_repository.dart';

/// Casos de uso de los ajustes globales de la aplicación.
///
/// Aquí vive la única validación de negocio del módulo: **qué claves
/// existen** (la lista espejo de `Ajustes.defectos` del frontend) y qué
/// forma debe tener cada valor. La elección concreta de los desplegables la
/// hace la UI; este caso de uso garantiza que un valor escrito a mano por la
/// API no pueda dejar un ajuste ininterpretable.
///
/// La escritura no comprueba el nivel de usuario: eso lo hace la capa HTTP
/// (`ajuste_routes.dart` exige `ADMIN` antes de llegar aquí).
final class Ajustes {
  const Ajustes({required this.repository});

  final AjusteRepository repository;

  /// Minutos entre respaldos automáticos de la BD (`0` = solo manual).
  ///
  /// Es la clave que lee el programador de respaldos del backend y la que
  /// muestra el desplegable «Respaldo automático» de la vista Ajustes.
  static const String claveRespaldoIntervalo = 'respaldoIntervalo';

  /// Roles que pueden usar el asistente IA (`ADMIN,CAJERO`; vacío = todos).
  ///
  /// Se guarda la lista separada por comas de los **nombres** de rol; la
  /// comprobación es case-insensitive. La aplica el backend en
  /// `POST /api/v1/chat` y la burbuja del frontend se oculta con ella.
  static const String claveIaRoles = 'iaRoles';

  /// Las claves que la aplicación sabe interpretar.
  static const Set<String> clavesConocidas = {
    'vendedorPorDefecto',
    'tipoPagoPorDefecto',
    'clientePorDefecto',
    'ordenCatalogo',
    'paginaInicial',
    'porPagina',
    'stockMinimo',
    claveRespaldoIntervalo,
    claveIaRoles,
    // Identidad del negocio (PDFs y marca de la app).
    'nombreTienda',
    // QR que se muestra al cobrar con QR (contenido editable).
    'qrPago',
    // Visibilidad de la burbuja flotante del asistente ('1' / '0').
    'burbujaIA',
    // Suscripción: las escribe `PUT /ajustes/suscripcion` con la clave
    // maestra y las lee el middleware en cada petición.
    'suscripcionVence',
    'suscripcionVista',
  };

  /// Claves donde **vacío es un valor legítimo** («sin preferencia»: cuenta
  /// conectada, cliente ocasional, Dashboard…, y en `iaRoles` = todos los
  /// roles pueden usar el asistente).
  static const Set<String> admiteVacio = {
    'vendedorPorDefecto',
    'clientePorDefecto',
    'paginaInicial',
    claveIaRoles,
    'qrPago',
  };

  /// Prefijo de los ajustes de **valor por defecto de un desplegable**
  /// (`defecto.producto.estado`, `defecto.usuario.rolId`…).
  ///
  /// Siguen el patrón `defecto.<entidad>.<campo>` y **sí admiten vacío**:
  /// `''` significa «— Sin valor por defecto —», es decir, que el campo arranca
  /// vacío y la validación del formulario pide elegirlo.
  ///
  /// No se enumeran una a una en [clavesConocidas] porque crecen con cada
  /// campo opción que se añada a un formulario: el backend valida su **forma**
  /// (prefijo, entidad en minúsculas, campo en camelCase) y deja la elección
  /// concreta a la UI. Además, la vista Ajustes reenvía en el `PUT` todo lo que
  /// encuentra en la BD, de modo que una clave huérfana de una versión anterior
  /// rompería el lote entero si estuviera fuera de una lista cerrada.
  static final RegExp _formaDefecto = RegExp(r'^defecto\.[a-z]+\.[A-Za-z]\w*$');

  /// `true` si [clave] es una clave de valor por defecto de desplegable.
  static bool esClaveDefecto(String clave) => _formaDefecto.hasMatch(clave);

  /// Ajustes numéricos y su rango admitido `(mínimo, máximo)`.
  ///
  /// El intervalo de respaldo va en minutos y admite hasta 43 200 (30 días),
  /// de modo que entran «Cada día», «Cada semana» y «Cada mes».
  static const Map<String, (int, int)> enteros = {
    'porPagina': (1, 200),
    'stockMinimo': (0, 1000),
    claveRespaldoIntervalo: (0, 43200),
  };

  /// Longitud máxima de cualquier valor (la columna es `VARCHAR(500)`).
  static const int maxValor = 500;

  Future<List<Ajuste>> listar({int limit = 200, int offset = 0}) => repository
      .findAjustes(limit: limit.clamp(1, 200), offset: offset.clamp(0, 100000));

  /// ¿Puede el rol [nivel] (`ADMIN`…) usar el asistente IA?
  ///
  /// Lee [claveIaRoles]: si nadie lo ha restringido (vacío o sin fila) lo
  /// puede usar **cualquier** rol autenticado, que es el comportamiento
  /// anterior a existir el ajuste. Con lista, el rol debe estar en ella
  /// (sin distinguir mayúsculas).
  Future<bool> puedeUsarIa(String? nivel) async {
    final items = await listar();
    var lista = '';
    for (final item in items) {
      if (item.clave == claveIaRoles) {
        lista = item.valor;
        break;
      }
    }
    final permitidos = rolesIa(lista);
    if (permitidos.isEmpty) return true;
    return permitidos.contains((nivel ?? '').trim().toUpperCase());
  }

  /// La lista de roles de un valor `iaRoles` en mayúsculas (`{'ADMIN'}`).
  /// Vacío o sin sentido → conjunto vacío (= todos los roles).
  static Set<String> rolesIa(String valor) => {
    for (final rol in valor.split(','))
      if (rol.trim().isNotEmpty) rol.trim().toUpperCase(),
  };

  /// Guarda un lote de ajustes y devuelve cuántos se escribieron.
  ///
  /// **Primero se valida todo el lote y después se escribe en una sola
  /// transacción**: si una clave o un valor no cuadra —o si algo falla a
  /// mitad de escritura—, no se guarda ni la mitad de los cambios.
  Future<int> guardar(Map<String, String> valores) async {
    if (valores.isEmpty) {
      throw const BadRequestException(
        'Indica al menos un ajuste a guardar.',
        code: 'fields_required',
      );
    }

    for (final ajuste in valores.entries) {
      _asegurarValido(ajuste.key, ajuste.value);
    }

    await repository.upsertAjustes({
      for (final ajuste in valores.entries) ajuste.key: ajuste.value.trim(),
    });
    return valores.length;
  }

  /// `400` si la clave no existe o el valor no tiene la forma esperada.
  void _asegurarValido(String clave, String valor) {
    final defecto = esClaveDefecto(clave);
    if (!clavesConocidas.contains(clave) && !defecto) {
      throw BadRequestException(
        'Ajuste desconocido: "$clave". '
        'Claves admitidas: ${clavesConocidas.join(', ')} '
        "(o con el patrón 'defecto.<entidad>.<campo>').",
        code: 'ajuste_desconocido',
      );
    }

    final limpio = valor.trim();
    if (limpio.isEmpty && !admiteVacio.contains(clave) && !defecto) {
      throw BadRequestException(
        'El ajuste "$clave" no admite valor vacío.',
        code: 'valor_requerido',
      );
    }
    if (limpio.length > maxValor) {
      throw BadRequestException(
        'El valor del ajuste "$clave" no puede superar $maxValor caracteres.',
        code: 'field_too_long',
      );
    }

    final rango = enteros[clave];
    if (rango != null) {
      final numero = int.tryParse(limpio);
      if (numero == null) {
        throw BadRequestException(
          'El ajuste "$clave" debe ser un número entero (recibido: "$limpio").',
          code: 'valor_invalido',
        );
      }
      final (minimo, maximo) = rango;
      if (numero < minimo || numero > maximo) {
        throw BadRequestException(
          'El ajuste "$clave" debe estar entre $minimo y $maximo '
          '(recibido: $numero).',
          code: 'valor_fuera_de_rango',
        );
      }
      return;
    }

    if (clave == claveIaRoles && limpio.isNotEmpty) {
      final malo = limpio
          .split(',')
          .map((rol) => rol.trim())
          .any((rol) => rol.isEmpty || !_formaRol.hasMatch(rol));
      if (malo) {
        throw BadRequestException(
          'El ajuste "$clave" debe ser una lista de roles separados por '
          'comas (p. ej. "ADMIN,CAJERO"), sin espacios ni símbolos dentro '
          'de cada nombre.',
          code: 'valor_invalido',
        );
      }
    }
  }

  /// Forma válida de un nombre de rol dentro de `iaRoles`: letras,
  /// números, guion bajo o guion (nada de comas ni espacios: la lista se
  /// separa por comas y cada rol viaja tal cual).
  static final RegExp _formaRol = RegExp(r'^[A-Za-z0-9_\-]+$');
}
