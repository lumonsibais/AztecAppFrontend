import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';

/// Tarjeta de sitio del listado de Explore.
///
/// Enseña lo que el diseño pide: imagen, la etiqueta MUST SEE cuando la
/// curaduría lo marca, título, tagline, valoración, duración y —cuando la
/// petición llevó coordenadas— la distancia que calculó el servidor.
class PlaceCard extends StatelessWidget {
  const PlaceCard({
    super.key,
    required this.place,
    required this.onTap,
    this.onToggleSaved,
  });

  final Place place;
  final VoidCallback onTap;

  /// null cuando no hay sesión: sin cuenta no hay corazón que pintar.
  final VoidCallback? onToggleSaved;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Portada(place: place, onToggleSaved: onToggleSaved),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(place.name, style: AztecTheme.tituloTarjeta),
                  if (place.tagline != null) ...[
                    const SizedBox(height: 5),
                    Text(place.tagline!, style: AztecTheme.tagline),
                  ],
                  const SizedBox(height: 11),
                  _Metadatos(place: place),
                ],
              ),
            ),
          ],
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
    return Stack(
      children: [
        SizedBox(
          height: 168,
          width: double.infinity,
          child: place.imageUrl == null
              ? Container(
                  color: AztecTheme.arena.withOpacity(0.35),
                  alignment: Alignment.center,
                  child: Icon(
                    _icono(place.placeType),
                    size: 46,
                    color: AztecTheme.tintaSuave.withOpacity(0.5),
                  ),
                )
              : Image.network(
                  place.imageUrl!,
                  fit: BoxFit.cover,
                  // Una imagen rota no puede tumbar el listado.
                  errorBuilder: (_, __, ___) => Container(
                    color: AztecTheme.arena.withOpacity(0.35),
                  ),
                ),
        ),
        if (place.esMustSee)
          const Positioned(
            left: 12,
            top: 12,
            child: _Etiqueta(texto: 'MUST SEE', fondo: AztecTheme.coral),
          ),
        if (place.esQuickStop)
          const Positioned(
            left: 12,
            top: 12,
            child: _Etiqueta(texto: 'QUICK STOP', fondo: AztecTheme.tinta),
          ),
        if (place.muestraCandado)
          const Positioned(
            right: 12,
            top: 12,
            child: CircleAvatar(
              radius: 15,
              backgroundColor: Colors.black54,
              child: Icon(Icons.lock, size: 16, color: Colors.white),
            ),
          ),
        if (onToggleSaved != null && !place.muestraCandado)
          Positioned(
            right: 8,
            top: 8,
            child: IconButton(
              onPressed: onToggleSaved,
              icon: Icon(
                place.isSaved == true ? Icons.favorite : Icons.favorite_border,
                color: place.isSaved == true ? AztecTheme.coral : Colors.white,
                shadows: const [Shadow(blurRadius: 6, color: Colors.black45)],
              ),
            ),
          ),
      ],
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

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.fondo});

  final String texto;
  final Color fondo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texto,
        style: AztecTheme.etiqueta.copyWith(color: Colors.white),
      ),
    );
  }
}

class _Metadatos extends StatelessWidget {
  const _Metadatos({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final trozos = <Widget>[];

    if (place.rating != null) {
      trozos.add(Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, size: 17, color: AztecTheme.coral),
        const SizedBox(width: 3),
        Text(place.rating!.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ]));
    }

    // La distancia solo existe si la petición llevó coordenadas.
    final km = place.location.distanceKm;
    if (km != null) {
      trozos.add(_Dato(
        icono: Icons.near_me_outlined,
        texto: km < 1
            ? '${(km * 1000).round()} m'
            : '${km.toStringAsFixed(1)} km',
      ));
    }

    if (place.visitDurationText != null) {
      trozos.add(_Dato(
        icono: Icons.schedule,
        texto: place.visitDurationText!.split('.').first,
      ));
    } else if (place.estimatedVisitDuration != null) {
      trozos.add(_Dato(
        icono: Icons.schedule,
        texto: '${place.estimatedVisitDuration} min',
      ));
    }

    if (place.badges.freeEntry) {
      trozos.add(const _Dato(icono: Icons.payments_outlined, texto: 'Free'));
    }

    return Wrap(spacing: 14, runSpacing: 6, children: trozos);
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icono, size: 15, color: AztecTheme.tintaSuave),
      const SizedBox(width: 4),
      Text(texto,
          style: const TextStyle(fontSize: 13, color: AztecTheme.tintaSuave)),
    ]);
  }
}
