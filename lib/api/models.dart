/// Modelos de la API.
///
/// Escritos a mano contra `AztecApp/openapi.json`, no generados: el generador
/// de OpenAPI para Dart arrastra build_runner y unos ciento cincuenta archivos
/// para un contrato de treinta y seis operaciones. Esto se lee entero en cinco
/// minutos.
///
/// A cambio de escribirlos a mano hace falta una red de seguridad, y la hay:
/// `tools/check_dart_contract.py` compara las claves que lee cada `fromJson`
/// con las que el spec declara, y se queja si alguna no existe o si un campo
/// que el servidor puede mandar nulo se está leyendo sin admitir nulo.
///
/// Regla de oro al tocar este archivo: **todo campo que el spec marca nullable
/// se declara nullable aquí**. El backend manda null de verdad —una imagen que
/// falta, la distancia cuando no hubo coordenadas, `isSaved` sin sesión— y en
/// Dart eso es un crash, no un aviso.
library;

// ---------------------------------------------------------------------------
// helpers de lectura
// ---------------------------------------------------------------------------

double? _asDouble(dynamic v) => v == null ? null : (v as num).toDouble();
int? _asInt(dynamic v) => v == null ? null : (v as num).toInt();
String? _asString(dynamic v) => v as String?;
bool _asBool(dynamic v, {bool fallback = false}) => v as bool? ?? fallback;

// ---------------------------------------------------------------------------
// sitios
// ---------------------------------------------------------------------------

class PlaceLocation {
  final double latitude;
  final double longitude;
  final String? neighborhood;

  /// Kilómetros hasta el punto que mandó la petición. Lo calcula PostGIS con
  /// ST_Distance; null cuando la petición no llevó coordenadas. No lo
  /// recalcules en el cliente: el servidor ya lo hizo bien.
  final double? distanceKm;

  const PlaceLocation({
    required this.latitude,
    required this.longitude,
    this.neighborhood,
    this.distanceKm,
  });

  factory PlaceLocation.fromJson(Map<String, dynamic> j) => PlaceLocation(
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        neighborhood: _asString(j['neighborhood']),
        distanceKm: _asDouble(j['distanceKm']),
      );
}

class Badges {
  final bool freeEntry;
  final bool outdoor;
  final bool archaeological;

  const Badges({
    required this.freeEntry,
    required this.outdoor,
    required this.archaeological,
  });

  factory Badges.fromJson(Map<String, dynamic> j) => Badges(
        freeEntry: _asBool(j['freeEntry']),
        outdoor: _asBool(j['outdoor']),
        archaeological: _asBool(j['archaeological']),
      );
}

class ContentAccess {
  /// El sitio es de pago.
  final bool isLocked;

  /// ...y ADEMÁS, si quien mira lo tiene desbloqueado. Son dos cosas
  /// distintas: un sitio bloqueado que ya compraste llega con isLocked=true y
  /// unlockedForViewer=true. El candado se pinta con el segundo.
  final bool unlockedForViewer;

  const ContentAccess({required this.isLocked, required this.unlockedForViewer});

  factory ContentAccess.fromJson(Map<String, dynamic> j) => ContentAccess(
        isLocked: _asBool(j['isLocked']),
        unlockedForViewer: _asBool(j['unlockedForViewer'], fallback: true),
      );
}

class NearbyServices {
  final bool bathrooms;
  final bool cafes;
  final bool hotels;

  const NearbyServices({
    required this.bathrooms,
    required this.cafes,
    required this.hotels,
  });

  factory NearbyServices.fromJson(Map<String, dynamic> j) => NearbyServices(
        bathrooms: _asBool(j['bathrooms']),
        cafes: _asBool(j['cafes']),
        hotels: _asBool(j['hotels']),
      );
}

/// Lo que cobra el museo en su taquilla. **No** es el precio de la app.
///
/// Viaja siempre, esté el sitio bloqueado o no: es información del mundo real.
class EntryFee {
  final double? mxn;
  final double? usd;

  /// El matiz que ningún importe sabe decir: "gratis los domingos para
  /// residentes", "gratis desde el mirador".
  final String? text;
  final bool isFree;

  const EntryFee({this.mxn, this.usd, this.text, required this.isFree});

  factory EntryFee.fromJson(Map<String, dynamic> j) => EntryFee(
        mxn: _asDouble(j['mxn']),
        usd: _asDouble(j['usd']),
        text: _asString(j['text']),
        isFree: _asBool(j['isFree']),
      );
}

class HistoricalContext {
  final String? tenochtitlanName;
  final String? eraDescription;

  const HistoricalContext({this.tenochtitlanName, this.eraDescription});

  factory HistoricalContext.fromJson(Map<String, dynamic> j) => HistoricalContext(
        tenochtitlanName: _asString(j['tenochtitlanName']),
        eraDescription: _asString(j['eraDescription']),
      );
}

class Place {
  final String id;
  final String name;
  final String? tagline;

  /// null cuando el sitio está bloqueado para quien mira.
  final String? description;

  final PlaceLocation location;
  final String? placeType;

  /// "must_see" | "quick_stop" | null. Catálogo editorial nuestro.
  final String? curation;

  /// Valoración editorial nuestra, no media de usuarios.
  final double? rating;

  final String? historicalSignificance;
  final int? estimatedVisitDuration;
  final String? visitDurationText;
  final String? imageUrl;
  final Badges badges;
  final ContentAccess access;
  final NearbyServices services;

  /// El corazón. **null sin sesión**: no es "no guardado", es "no aplica".
  final bool? isSaved;

  // --- logística: llega siempre en la ficha, se haya pagado o no ---
  final String? openingHours;
  final String? howToGetThere;
  final EntryFee? entryFee;
  final String? safetyRecommendations;

  // --- contenido nuestro: solo con el desbloqueo ---
  final String? whyVisit;
  final HistoricalContext? historicalContext;

  const Place({
    required this.id,
    required this.name,
    required this.location,
    required this.badges,
    required this.access,
    required this.services,
    this.tagline,
    this.description,
    this.placeType,
    this.curation,
    this.rating,
    this.historicalSignificance,
    this.estimatedVisitDuration,
    this.visitDurationText,
    this.imageUrl,
    this.isSaved,
    this.openingHours,
    this.howToGetThere,
    this.entryFee,
    this.safetyRecommendations,
    this.whyVisit,
    this.historicalContext,
  });

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        id: j['id'] as String,
        name: j['name'] as String,
        tagline: _asString(j['tagline']),
        description: _asString(j['description']),
        location: PlaceLocation.fromJson(j['location'] as Map<String, dynamic>),
        placeType: _asString(j['placeType']),
        curation: _asString(j['curation']),
        rating: _asDouble(j['rating']),
        historicalSignificance: _asString(j['historicalSignificance']),
        estimatedVisitDuration: _asInt(j['estimatedVisitDuration']),
        visitDurationText: _asString(j['visitDurationText']),
        imageUrl: _asString(j['imageUrl']),
        badges: Badges.fromJson(j['badges'] as Map<String, dynamic>),
        access: ContentAccess.fromJson(j['contentAccess'] as Map<String, dynamic>),
        services: NearbyServices.fromJson(
            j['nearbyServices'] as Map<String, dynamic>),
        isSaved: j['isSaved'] as bool?,
        openingHours: _asString(j['openingHours']),
        howToGetThere: _asString(j['howToGetThere']),
        entryFee: j['entryFee'] == null
            ? null
            : EntryFee.fromJson(j['entryFee'] as Map<String, dynamic>),
        safetyRecommendations: _asString(j['safetyRecommendations']),
        whyVisit: _asString(j['whyVisit']),
        historicalContext: j['historicalContext'] == null
            ? null
            : HistoricalContext.fromJson(
                j['historicalContext'] as Map<String, dynamic>),
      );

  bool get esMustSee => curation == 'must_see';
  bool get esQuickStop => curation == 'quick_stop';

  /// Se pinta el candado cuando el sitio es de pago y quien mira no lo tiene.
  bool get muestraCandado => access.isLocked && !access.unlockedForViewer;
}

// ---------------------------------------------------------------------------
// guía histórica
// ---------------------------------------------------------------------------

class HistoricalArticle {
  final String id;
  final String title;
  final String? description;
  final String? topic;
  final String? era;
  final int? readingTimeMinutes;
  final int? sortOrder;
  final bool isLocked;
  final bool unlockedForViewer;

  /// null sin sesión.
  final bool? isRead;

  /// Solo en el detalle, y solo con el desbloqueo.
  final String? content;

  /// Alimenta el botón "Next" de la cronología. Solo en el detalle.
  final String? nextContentId;

  const HistoricalArticle({
    required this.id,
    required this.title,
    required this.isLocked,
    required this.unlockedForViewer,
    this.description,
    this.topic,
    this.era,
    this.readingTimeMinutes,
    this.sortOrder,
    this.isRead,
    this.content,
    this.nextContentId,
  });

  factory HistoricalArticle.fromJson(Map<String, dynamic> j) => HistoricalArticle(
        id: j['id'] as String,
        title: j['title'] as String,
        description: _asString(j['description']),
        topic: _asString(j['topic']),
        era: _asString(j['era']),
        readingTimeMinutes: _asInt(j['readingTimeMinutes']),
        sortOrder: _asInt(j['sortOrder']),
        isLocked: _asBool(j['isLocked']),
        unlockedForViewer: _asBool(j['unlockedForViewer'], fallback: true),
        isRead: j['isRead'] as bool?,
        content: _asString(j['content']),
        nextContentId: _asString(j['nextContentId']),
      );

  bool get muestraCandado => isLocked && !unlockedForViewer;
}

class Topic {
  final String topic;
  final int count;

  const Topic({required this.topic, required this.count});

  factory Topic.fromJson(Map<String, dynamic> j) => Topic(
        topic: j['topic'] as String,
        count: (j['count'] as num).toInt(),
      );
}

// ---------------------------------------------------------------------------
// overlay del lago
// ---------------------------------------------------------------------------

/// Un polígono del mapa histórico.
///
/// `surfaceType` decide el color: `water` azul, `land` arena. **No lo deduzcas
/// del nombre** — el backend lo declara justamente para no tener que hacerlo.
class LakeFeature {
  final String id;
  final String name;
  final String surfaceType;
  final int? yearEstimate;
  final String? tenochtitlanName;
  final String? description;

  /// Anillos de coordenadas en formato GeoJSON: [longitud, latitud].
  /// Ojo con el orden, va al revés de como se dice "lat, lon" en voz alta.
  final List<List<List<double>>> rings;

  const LakeFeature({
    required this.id,
    required this.name,
    required this.surfaceType,
    required this.rings,
    this.yearEstimate,
    this.tenochtitlanName,
    this.description,
  });

  bool get esAgua => surfaceType == 'water';

  factory LakeFeature.fromJson(Map<String, dynamic> j) {
    final props = j['properties'] as Map<String, dynamic>;
    final geom = j['geometry'] as Map<String, dynamic>;
    final coords = geom['coordinates'] as List<dynamic>?;

    return LakeFeature(
      id: j['id'] as String,
      name: props['name'] as String,
      surfaceType: props['surfaceType'] as String,
      yearEstimate: _asInt(props['yearEstimate']),
      tenochtitlanName: _asString(props['tenochtitlanName']),
      description: _asString(props['description']),
      rings: (coords ?? const [])
          .map<List<List<double>>>((anillo) => (anillo as List<dynamic>)
              .map<List<double>>((punto) => (punto as List<dynamic>)
                  .map<double>((n) => (n as num).toDouble())
                  .toList())
              .toList())
          .toList(),
    );
  }
}

class LakeOverlay {
  final List<LakeFeature> features;

  /// Los años que tienen geometría. Con esto se construye el conmutador en vez
  /// de llevar 1500 y 2026 escritos a fuego en la app.
  final List<int> availableYears;

  const LakeOverlay({required this.features, required this.availableYears});

  factory LakeOverlay.fromJson(Map<String, dynamic> j) => LakeOverlay(
        features: (j['features'] as List<dynamic>)
            .map((f) => LakeFeature.fromJson(f as Map<String, dynamic>))
            .toList(),
        availableYears: ((j['availableYears'] as List<dynamic>?) ?? const [])
            .map((y) => (y as num).toInt())
            .toList(),
      );
}

// ---------------------------------------------------------------------------
// cuenta y acceso
// ---------------------------------------------------------------------------

class AccessState {
  final bool hasFullAccess;
  final String? since;
  final String product;
  final double price;
  final String currency;

  const AccessState({
    required this.hasFullAccess,
    required this.product,
    required this.price,
    required this.currency,
    this.since,
  });

  factory AccessState.fromJson(Map<String, dynamic> j) => AccessState(
        hasFullAccess: _asBool(j['hasFullAccess']),
        since: _asString(j['since']),
        product: j['product'] as String,
        price: (j['price'] as num).toDouble(),
        currency: j['currency'] as String,
      );
}

class UserStats {
  final int toursCompleted;
  final int placesVisited;

  const UserStats({required this.toursCompleted, required this.placesVisited});

  factory UserStats.fromJson(Map<String, dynamic> j) => UserStats(
        toursCompleted: (j['toursCompleted'] as num).toInt(),
        placesVisited: (j['placesVisited'] as num).toInt(),
      );
}

class User {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? preferredLocale;
  final bool hasFullAccess;
  final UserStats stats;

  const User({
    required this.id,
    required this.email,
    required this.hasFullAccess,
    required this.stats,
    this.firstName,
    this.lastName,
    this.preferredLocale,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        email: j['email'] as String,
        firstName: _asString(j['firstName']),
        lastName: _asString(j['lastName']),
        preferredLocale: _asString(j['preferredLocale']),
        hasFullAccess: _asBool(j['hasFullAccess']),
        stats: UserStats.fromJson(j['stats'] as Map<String, dynamic>),
      );
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final User user;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> j) => AuthTokens(
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
        user: User.fromJson(j['user'] as Map<String, dynamic>),
      );
}
