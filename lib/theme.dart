import 'package:flutter/material.dart';

/// Tema tomado del diseño de Figma: fondo hueso, coral de los pines del mapa y
/// tipografía de peso alto para los títulos de tarjeta.
class AztecTheme {
  static const Color coral = Color(0xFFE8563F);
  static const Color coralOscuro = Color(0xFFC8412C);
  static const Color hueso = Color(0xFFF7F4EF);
  static const Color tinta = Color(0xFF1C1A17);
  static const Color tintaSuave = Color(0xFF6B655C);
  static const Color arena = Color(0xFFD9C39A); // tierra del mapa de 1500
  static const Color agua = Color(0xFF9EC5D8); // lago del mapa de 1500
  static const Color linea = Color(0xFFE4DED4);

  static ThemeData get claro {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: hueso,
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
          color: tinta,
          fontSize: 28,
          fontWeight: FontWeight.w800,
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
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: tinta,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: coral.withOpacity(0.12),
        labelTextStyle: MaterialStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static const tituloTarjeta = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w800,
    color: tinta,
    height: 1.15,
    letterSpacing: -0.3,
  );

  static const tagline = TextStyle(
    fontSize: 14,
    color: tintaSuave,
    height: 1.35,
  );

  static const etiqueta = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
  );
}
