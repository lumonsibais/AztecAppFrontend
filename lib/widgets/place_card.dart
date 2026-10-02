import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';

/// Tarjeta de sitio, tal como la define el diseño (HU 2 y HU3).
///
/// La forma importa y antes estaba al revés: **la foto manda**. 200 px de
/// imagen con un degradado hacia abajo, y encima de la foto van los badges, el
/// candado, el corazón y el título en blanco. Lo único que vive fuera de la
/// imagen es la descripción, en gris.
///
/// La versión anterior ponía el título y todos los metadatos debajo, sobre
/// fondo blanco, con la foto como mera ilustración. Se leía bien pero no era el
/// producto: en el diseño, lo primero es el sitio.
///
/// Medidas del archivo: tarjeta de 170×274 con radio 24, foto de 200,
/// degradado desde `rgba(26,16,8,0.72)` hasta transparente al 55%.
class PlaceCard extends StatelessWidget {
  const PlaceCard({
    super.key,
    required this.place,
    required this.onTap,
    this.onToggleSaved,
  });

  final Place place;
  final VoidCallback onTap;

  /// Siempre conectado: sin sesión, quien llama se encarga de pedir la cuenta.
  final VoidCallback? onToggleSaved;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AztecTheme.radioTarjeta),
        boxShadow: AztecTheme.sombraTarjeta,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AztecTheme.radioTarjeta),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Portada(place: place, onToggleSaved: onToggleSaved),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Text(
                      place.tagline ?? place.description ?? '',
                      style: AztecTheme.descripcion,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Portada extends StatelessWidget {
  const _Portada({required this.place, this.onToggleSaved});

  final Place place;
  final VoidCallback? onToggleSaved;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _imagen(),

          // El degradado existe para que el título blanco se lea sobre
          // cualquier foto. Sin él, una imagen clara deja el nombre invisible.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xB81A1008), Color(0x001A1008)],
                stops: [0, 0.55],
              ),
            ),
          ),

          // Badges y título, abajo a la izquierda.
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Badges(place: place),
                const SizedBox(height: 6),
                Text(
                  place.name,
                  style: AztecTheme.tituloSitio,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          if (onToggleSaved != null)
            Positioned(top: 10, right: 10, child: _Corazon(
              guardado: place.isSaved == true,
              onPulsar: onToggleSaved!,
            )),
        ],
      ),
    );
  }

  Widget _imagen() {
    if (place.imageUrl == null) {
      return Container(
        color: AztecTheme.arena.withOpacity(0.5),
        alignment: Alignment.center,
        child: Icon(
          _icono(place.placeType),
          size: 46,
          color: Colors.white.withOpacity(0.7),
        ),
      );
    }
    return Image.network(
      place.imageUrl!,
      fit: BoxFit.cover,
      // Una imagen rota no puede tumbar el listado.
      errorBuilder: (_, __, ___) =>
          Container(color: AztecTheme.arena.withOpacity(0.5)),
    );
  }

  static IconData _icono(String? tipo) => switch (tipo) {
        'museum' => Icons.account_balance,
        'ruin' => Icons.temple_buddhist,
        'monument' => Icons.tour,
        'park' => Icons.park,
        _ => Icons.place,
      };
}

/// La fila de etiquetas sobre la foto: curaduría, entrada gratis y candado.
class _Badges extends StatelessWidget {
  const _Badges({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final etiquetas = <Widget>[];

    if (place.esMustSee) {
      etiquetas.add(const _Pildora(
          texto: 'MUST SEE', fondo: AztecTheme.mustSee, colorTexto: Colors.white));
    } else if (place.esQuickStop) {
      etiquetas.add(const _Pildora(
          texto: 'QUICK STOP',
          fondo: AztecTheme.quickStop,
          colorTexto: Colors.white));
    }

    // FREE va en claro con texto oscuro, al revés que las otras dos.
    if (place.badges.freeEntry) {
      etiquetas.add(const _Pildora(
          texto: 'FREE', fondo: AztecTheme.gratis, colorTexto: AztecTheme.tinta));
    }

    if (place.muestraCandado) {
      etiquetas.add(_Pildora(
        fondo: place.esQuickStop ? AztecTheme.quickStop : AztecTheme.mustSee,
        colorTexto: Colors.white,
        icono: Icons.lock,
      ));
    }

    if (etiquetas.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 6, runSpacing: 4, children: etiquetas);
  }
}

class _Pildora extends StatelessWidget {
  const _Pildora({
    required this.fondo,
    required this.colorTexto,
    this.texto,
    this.icono,
  });

  final String? texto;
  final IconData? icono;
  final Color fondo;

  final Color colorTexto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icono == null ? 6 : 5,
          vertical: 2),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: icono != null
          ? Icon(icono, size: 11, color: colorTexto)
          : Text(texto!,
              style: AztecTheme.capsulaPequena.copyWith(color: colorTexto)),
    );
  }
}

/// El corazón: círculo oscuro translúcido arriba a la derecha de la foto.
class _Corazon extends StatelessWidget {
  const _Corazon({required this.guardado, required this.onPulsar});

  final bool guardado;
  final VoidCallback onPulsar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x661A1008),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPulsar,
        child: SizedBox(
          height: 36,
          width: 36,
          child: Icon(
            guardado ? Icons.favorite : Icons.favorite_border,
            size: 18,
            color: guardado ? AztecTheme.coral : Colors.white,
          ),
        ),
      ),
    );
  }
}
