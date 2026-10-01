import 'package:flutter/material.dart';

/// El sistema de diseño, tomado del archivo de Figma (*The Az App*).
///
/// Los valores de aquí NO se afinan a ojo: salen de los estilos nombrados y de
/// los colores del archivo. Si algo no cuadra con el diseño se arregla aquí, no
/// en la pantalla que lo use.
///
/// Antes esto tenía una paleta parecida pero ninguna igual —el coral era
/// `#E8563F` en vez de `#e8613a`, el gris de texto `#6B655C` en vez de
/// `#8a8a9a`— y, sobre todo, **no declaraba ninguna fuente**: la app usaba la
/// del sistema. Toda la personalidad del diseño está en esa pareja de
/// tipografías, así que sin ellas no se parecía por mucho que los colores
/// anduvieran cerca.
class AztecTheme {
  // ---------------------------------------------------------------------------
  // Color
  // ---------------------------------------------------------------------------

  /// El coral de la marca: botones, acentos, el filtro activo.
  static const Color coral = Color(0xFFE8613A);
  static const Color coralOscuro = Color(0xFFC8412C);

  /// Fondo de la app y de la barra inferior.
  static const Color hueso = Color(0xFFFAF7F4);

  /// Texto principal.
  static const Color tinta = Color(0xFF1A1A1A);

  /// Texto secundario: descripciones, metadatos, etiquetas de la barra.
  static const Color tintaSuave = Color(0xFF8A8A9A);

  /// Cuerpo de la ficha de sitio. Es un gris MÁS AZULADO que `tintaSuave`, y en
  /// el diseño se usa solo ahí.
  static const Color cuerpo = Color(0xFF6B7A8D);

  /// Separadores y bordes.
  static const Color linea = Color(0xFFEDE8E1);

  // --- badges del catálogo ---
  /// "MUST SEE".
  static const Color mustSee = Color(0xFFD24B1A);

  /// "QUICK STOP".
  static const Color quickStop = Color(0xFF26CDF1);

  /// "FREE" — fondo claro con texto en tinta, al revés que los otros dos.
  static const Color gratis = Color(0xFFF5C4B5);

  // --- chips de atributo de la ficha (🆓 Free Entry, 🌿 Outdoor View…) ---
  static const Color chipFondo = Color(0xFFFFF0EB);
  static const Color chipBorde = Color(0xFFFFBDAA);

  /// El elemento activo de la barra inferior.
  ///
  /// OJO: en el diseño es AZUL, no coral, y sale así en las dos pantallas que
  /// hemos leído. Puede ser intencional o un descuido repetido; está pendiente
  /// de confirmar con quien diseñó. Mientras tanto se respeta el archivo.
  static const Color navActivo = Color(0xFF0066FF);

  // --- mapa de 1500 ---
  static const Color arena = Color(0xFFD9C39A); // tierra
  static const Color agua = Color(0xFF9EC5D8); // lago

  // ---------------------------------------------------------------------------
  // Forma
  // ---------------------------------------------------------------------------

  /// Tarjeta de sitio.
  static const double radioTarjeta = 24;

  /// Parada de tour.
  static const double radioParada = 18;

  /// Píldoras: chips de filtro, badges, botones.
  static const double radioPildora = 50;

  static const List<BoxShadow> sombraTarjeta = [
    BoxShadow(
      color: Color(0x1A2C1C12), // rgba(44,28,18,0.1)
      blurRadius: 24,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> sombraParada = [
    BoxShadow(
      color: Color(0x1A2C1C12),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  // ---------------------------------------------------------------------------
  // Tipografía
  // ---------------------------------------------------------------------------
  //
  // Dos familias y una regla sencilla: **Playfair Display para los títulos,
  // Inter para todo lo demás**. Los nombres de abajo son los del archivo de
  // Figma a propósito —`H1 content`, `Quote`, `Capsule text`— para que al mirar
  // el diseño y el código se hable del mismo estilo.

  static const String serif = 'PlayfairDisplay';
  static const String grotesca = 'Inter';

  /// `H1 content` — "Start exploring".
  static const h1 = TextStyle(
    fontFamily: serif,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: tinta,
  );

  /// `H2 Content` — "Aztec Sites in Mexico City".
  static const h2 = TextStyle(
    fontFamily: serif,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: tinta,
  );

  /// `H3 content` — el título de una ficha, "Tour Stops".
  static const h3 = TextStyle(
    fontFamily: serif,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
    color: Colors.black,
  );

  /// `Quote` — el tagline de un sitio, en itálica.
  static const cita = TextStyle(
    fontFamily: serif,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    fontStyle: FontStyle.italic,
    color: tinta,
  );

  /// `Site Title` — el nombre del sitio sobre la foto de la tarjeta.
  static const tituloSitio = TextStyle(
    fontFamily: grotesca,
    fontSize: 20,
    height: 23 / 20,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  /// `Caption/Site description` — la descripción bajo la tarjeta.
  static const descripcion = TextStyle(
    fontFamily: grotesca,
    fontSize: 14,
    height: 18 / 14,
    fontWeight: FontWeight.w500,
    color: tintaSuave,
  );

  /// `TEXT` — el cuerpo de la ficha.
  static const texto = TextStyle(
    fontFamily: grotesca,
    fontSize: 16,
    height: 20 / 16,
    color: cuerpo,
  );

  /// `Button text`.
  static const textoBoton = TextStyle(
    fontFamily: grotesca,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  /// `Capsule text` — el texto de un badge. Va en mayúsculas y muy espaciado.
  static const capsula = TextStyle(
    fontFamily: grotesca,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
  );

  /// `Capsule text 2` — la versión pequeña, la que va sobre la foto.
  static const capsulaPequena = TextStyle(
    fontFamily: grotesca,
    fontSize: 9,
    fontWeight: FontWeight.w600,
  );

  /// `H4 site text` — el encabezado de una fila de logística.
  static const h4 = TextStyle(
    fontFamily: grotesca,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: tinta,
  );

  // --- nombres anteriores, conservados ---
  // Las pantallas ya construidas los usan en unos setenta sitios. Renombrarlos
  // sería un cambio grande que no mejora nada por sí solo, así que apuntan a
  // los estilos nuevos y se retiran cuando cada pantalla se rehaga contra el
  // diseño.

  /// El título de tarjeta de las pantallas que todavía lo pintan fuera de la
  /// foto. El diseño lo quiere encima: ver `tituloSitio`.
  static const tituloTarjeta = TextStyle(
    fontFamily: grotesca,
    fontSize: 19,
    fontWeight: FontWeight.w800,
    color: tinta,
    height: 1.15,
    letterSpacing: -0.3,
  );

  static const tagline = descripcion;
  static const etiqueta = capsula;

  // ---------------------------------------------------------------------------
  // ThemeData
  // ---------------------------------------------------------------------------

  static ThemeData get claro {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: hueso,
      // Inter como fuente por defecto: lo que NO lleve estilo explícito tiene
      // que salir en Inter, no en la del sistema.
      textTheme: base.textTheme.apply(fontFamily: grotesca),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: grotesca),
      colorScheme: base.colorScheme.copyWith(
        primary: coral,
        secondary: coralOscuro,
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: hueso,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: serif,
          color: tinta,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: linea),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.white,
        side: const BorderSide(color: linea),
        labelStyle: const TextStyle(
          fontFamily: grotesca,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: tinta,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: hueso,
        indicatorColor: coral.withOpacity(0.12),
        labelTextStyle: MaterialStateProperty.all(
          const TextStyle(
            fontFamily: grotesca,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
