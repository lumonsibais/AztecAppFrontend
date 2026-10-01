import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../services/session_scope.dart';
import '../theme.dart';
import 'auth/auth_screen.dart' show pedirEntrar;

/// Ficha de un sitio, según el diseño (HU6).
///
/// Dónde cae la línea del paywall, que no es la obvia: la **logística** —cómo
/// llegar, taquilla, horarios, cuánto dura la visita— se pinta siempre, porque
/// son datos del mundo real que cualquiera puede buscar. Lo que va detrás del
/// candado es lo que escribimos nosotros: el *por qué ir* y el contexto
/// histórico.
///
/// La forma viene del archivo: foto de 280, badges, título en Playfair, los
/// atributos como chips con emoji, el tagline como **cita en itálica**, y la
/// logística **plegada en filas** con su chevron. Antes estaba todo desplegado
/// uno debajo de otro, que se lee bien pero convierte la ficha en un muro.
class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen({
    super.key,
    required this.api,
    required this.placeId,
  });

  final ApiClient api;
  final String placeId;

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  late Future<Place> _futuro;

  /// Lo que se sabía del acceso la última vez que se construyó.
  ///
  /// Qué se pinta aquí lo decide el SERVIDOR: el contenido de pago no viaja en
  /// la respuesta si la cuenta no lo tiene. Por eso, cuando el acceso cambia,
  /// no basta con repintar: hay que volver a pedir la ficha, o el candado
  /// desaparecería y debajo no habría nada.
  bool? _accesoAnterior;

  @override
  void initState() {
    super.initState();
    _futuro = widget.api.sitio(widget.placeId);
  }

  @override
  Widget build(BuildContext context) {
    final sesion = SessionScope.of(context);

    if (_accesoAnterior != null &&
        _accesoAnterior != sesion.tieneAccesoCompleto) {
      _futuro = widget.api.sitio(widget.placeId);
    }
    _accesoAnterior = sesion.tieneAccesoCompleto;

    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<Place>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('${snap.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AztecTheme.tintaSuave)),
              ),
            );
          }

          final p = snap.data!;
          return Column(
            children: [
              Expanded(child: _contenido(p)),
              // Barra fija abajo, como en el diseño.
              _BarraAccion(place: p),
            ],
          );
        },
      ),
    );
  }

  /// El corazón de la foto. Mismo trato que en Explore: sin sesión no se queda
  /// quieto sin explicar nada, se pide la cuenta diciendo para qué.
  Future<void> _alternarGuardado(Place p) async {
    final sesion = SessionScope.sin(context);

    if (!sesion.haySesion) {
      final entro = await pedirEntrar(
        context,
        motivo: 'Sign in to save ${p.name} and find it again later.',
        registro: true,
      );
      if (!entro || !mounted) return;
      setState(() => _futuro = widget.api.sitio(widget.placeId));
      return;
    }

    try {
      if (p.isSaved == true) {
        await widget.api.quitarSitio(p.id);
      } else {
        await widget.api.guardarSitio(p.id);
      }
      if (mounted) {
        setState(() => _futuro = widget.api.sitio(widget.placeId));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Widget _contenido(Place p) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Hero(place: p, onToggleSaved: () => _alternarGuardado(p)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _Etiquetas(place: p),
              const SizedBox(height: 4),
              Text(p.name, style: AztecTheme.h3),
              const SizedBox(height: 11),
              _Atributos(badges: p.badges),

              if (p.tagline != null) ...[
                const SizedBox(height: 18),
                // El tagline es la CITA del diseño: Playfair en itálica, no un
                // subtítulo gris cualquiera.
                Text(p.tagline!, style: AztecTheme.cita),
              ],

              // `description` no aparece en el marco que leí, pero el servidor
              // la manda y es el resumen del sitio. Va como párrafo suelto, sin
              // encabezado, para no inventarme una sección que el diseño no
              // tiene.
              if (p.description != null) ...[
                const SizedBox(height: 14),
                Text(p.description!, style: AztecTheme.texto),
              ],

              const SizedBox(height: 18),
              if (p.whyVisit != null) ...[
                Text('Why you should go?',
                    style: AztecTheme.h4.copyWith(color: AztecTheme.coral)),
                const SizedBox(height: 7),
                Text(p.whyVisit!, style: AztecTheme.texto),
              ] else if (p.muestraCandado)
                const _Candado(),

              const SizedBox(height: 10),
              _Plegables(place: p),
            ]),
          ),
        ),
      ],
    );
  }
}

/// El carrusel de fotos, con los dos botones encima.
///
/// Los puntos de paso solo salen cuando hay MÁS DE UNA foto: un punto solo no
/// informa de nada y sugiere que hay algo más que deslizar.
class _Hero extends StatefulWidget {
  const _Hero({required this.place, required this.onToggleSaved});

  final Place place;
  final VoidCallback onToggleSaved;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  final _paginas = PageController();
  int _actual = 0;

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final fotos = place.images;

    return SizedBox(
      height: 280,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (fotos.isEmpty)
            Container(
              color: AztecTheme.arena.withOpacity(0.5),
              alignment: Alignment.center,
              child: Icon(Icons.photo_outlined,
                  size: 54, color: Colors.white.withOpacity(0.7)),
            )
          else
            PageView.builder(
              controller: _paginas,
              itemCount: fotos.length,
              onPageChanged: (i) => setState(() => _actual = i),
              itemBuilder: (_, i) => Image.network(
                fotos[i].url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: AztecTheme.arena.withOpacity(0.5)),
              ),
            ),

          // Degradado de arriba: sin él, los botones blancos desaparecen sobre
          // una foto clara.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x4D000000), Color(0x00000000)],
                stops: [0, 0.6],
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _BotonRedondo(
                    icono: Icons.arrow_back,
                    onPulsar: () => Navigator.of(context).pop(),
                  ),
                  _BotonRedondo(
                    icono: place.isSaved == true
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: place.isSaved == true ? AztecTheme.coral : null,
                    onPulsar: widget.onToggleSaved,
                  ),
                ],
              ),
            ),
          ),

          if (fotos.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: _Puntos(total: fotos.length, actual: _actual),
            ),

          // El pie de la foto actual, si lo tiene.
          if (fotos.isNotEmpty && fotos[_actual].caption != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: fotos.length > 1 ? 30 : 14,
              child: Text(
                fotos[_actual].caption!,
                style: const TextStyle(
                  fontFamily: AztecTheme.grotesca,
                  fontSize: 12,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Los puntos de paso del carrusel. El activo es una barrita alargada, como en
/// el diseño, no un círculo más grande.
class _Puntos extends StatelessWidget {
  const _Puntos({required this.total, required this.actual});

  final int total;
  final int actual;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 8,
            width: i == actual ? 22 : 8,
            decoration: BoxDecoration(
              color: i == actual ? AztecTheme.coral : AztecTheme.linea,
              borderRadius: BorderRadius.circular(50),
            ),
          ),
      ],
    );
  }
}

class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo({required this.icono, required this.onPulsar, this.color});

  final IconData icono;
  final VoidCallback onPulsar;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPulsar,
        child: SizedBox(
          height: 36,
          width: 36,
          child: Icon(icono, size: 19, color: color ?? AztecTheme.tinta),
        ),
      ),
    );
  }
}

/// MUST SEE / QUICK STOP y FREE, encima del título.
class _Etiquetas extends StatelessWidget {
  const _Etiquetas({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final etiquetas = <Widget>[
      if (place.esMustSee)
        const _Capsula(texto: 'MUST SEE', fondo: AztecTheme.mustSee),
      if (place.esQuickStop)
        const _Capsula(texto: 'QUICK STOP', fondo: AztecTheme.quickStop),
      if (place.badges.freeEntry)
        const _Capsula(
            texto: 'FREE',
            fondo: AztecTheme.gratis,
            colorTexto: AztecTheme.tinta),
    ];

    if (etiquetas.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 6, children: etiquetas);
  }
}

class _Capsula extends StatelessWidget {
  const _Capsula({
    required this.texto,
    required this.fondo,
    this.colorTexto = Colors.white,
  });

  final String texto;
  final Color fondo;
  final Color colorTexto;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(texto,
            style: AztecTheme.capsula.copyWith(color: colorTexto)),
      );
}

/// Los tres chips con emoji. Salen tal cual de `badges`, que el backend ya
/// manda con exactamente estos tres campos — señal de que se construyó contra
/// este mismo diseño.
class _Atributos extends StatelessWidget {
  const _Atributos({required this.badges});

  final Badges badges;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (badges.freeEntry) const _Chip(texto: '🆓 Free Entry'),
      if (badges.outdoor) const _Chip(texto: '🌿 Outdoor View'),
      if (badges.archaeological) const _Chip(texto: '🏺 Archaeological Site'),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 6),
        decoration: BoxDecoration(
          color: AztecTheme.chipFondo,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AztecTheme.chipBorde),
        ),
        child: Text(texto,
            style: const TextStyle(
              fontFamily: AztecTheme.grotesca,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            )),
      );
}

/// La logística, plegada.
///
/// El diseño la lista en cuatro filas con chevron en vez de volcarla entera.
/// Tiene sentido para lo que es: cuando alguien está decidiendo si ir, el
/// titular le basta; los horarios los mira el día que va.
///
/// Hay una quinta, "Good to know", que el marco no trae: son las
/// recomendaciones de seguridad que el backend manda en
/// `safetyRecommendations`. Es logística y tirarla sería perder información, así
/// que va al final con la misma forma.
class _Plegables extends StatelessWidget {
  const _Plegables({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final filas = <Widget>[];

    if (place.howToGetThere != null || place.location.neighborhood != null) {
      filas.add(_Fila(
        titulo: 'How to get there',
        cuerpo: [
          if (place.location.neighborhood != null) place.location.neighborhood!,
          if (place.howToGetThere != null) place.howToGetThere!,
        ].join('\n\n'),
      ));
    }

    final tarifas = _tarifas();
    if (tarifas != null) filas.add(_Fila(titulo: 'Fees and times', cuerpo: tarifas));

    final duracion = place.visitDurationText ??
        (place.estimatedVisitDuration != null
            ? '${place.estimatedVisitDuration} minutes'
            : null);
    if (duracion != null) {
      filas.add(_Fila(titulo: 'Estimated visit time', cuerpo: duracion));
    }

    final historia = [
      if (place.historicalSignificance != null) place.historicalSignificance!,
      if (place.historicalContext?.tenochtitlanName != null)
        'In Tenochtitlan: ${place.historicalContext!.tenochtitlanName}',
      if (place.historicalContext?.eraDescription != null)
        place.historicalContext!.eraDescription!,
    ].join('\n\n');
    if (historia.isNotEmpty) {
      filas.add(_Fila(titulo: 'Historic information', cuerpo: historia));
    } else if (place.muestraCandado) {
      // El contexto histórico es contenido de pago: si no viaja, la fila se
      // queda pero dice por qué está vacía, en vez de desaparecer sin más.
      filas.add(const _Fila(
        titulo: 'Historic information',
        cuerpo: 'Part of the full guide.',
        bloqueada: true,
      ));
    }

    if (place.safetyRecommendations != null) {
      filas.add(_Fila(
          titulo: 'Good to know', cuerpo: place.safetyRecommendations!));
    }

    if (filas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(color: AztecTheme.separador, height: 24),
        for (final f in filas) f,
      ],
    );
  }

  String? _tarifas() {
    final fee = place.entryFee;
    final partes = <String>[];

    if (fee != null) {
      if (fee.isFree) {
        partes.add(fee.text ?? 'Free entry');
      } else {
        final importes = <String>[
          if (fee.mxn != null) '${fee.mxn!.toStringAsFixed(0)} MXN',
          if (fee.usd != null) '\$${fee.usd!.toStringAsFixed(2)} USD',
        ];
        if (importes.isNotEmpty) partes.add(importes.join('  ·  '));
        if (fee.text != null) partes.add(fee.text!);
      }
    }
    if (place.openingHours != null) partes.add(place.openingHours!);

    return partes.isEmpty ? null : partes.join('\n');
  }
}

class _Fila extends StatefulWidget {
  const _Fila({
    required this.titulo,
    required this.cuerpo,
    this.bloqueada = false,
  });

  final String titulo;
  final String cuerpo;
  final bool bloqueada;

  @override
  State<_Fila> createState() => _FilaState();
}

class _FilaState extends State<_Fila> {
  bool _abierta = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _abierta = !_abierta),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Expanded(child: Text(widget.titulo, style: AztecTheme.h4)),
                if (widget.bloqueada)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.lock_outline,
                        size: 15, color: AztecTheme.tintaSuave),
                  ),
                // El chevron gira al abrir: es la única pista de que la fila se
                // despliega, porque el título no cambia.
                AnimatedRotation(
                  turns: _abierta ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const Icon(Icons.chevron_right,
                      size: 22, color: AztecTheme.coral),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(widget.cuerpo, style: AztecTheme.texto),
          ),
          crossFadeState:
              _abierta ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 150),
        ),
        const Divider(color: AztecTheme.separador, height: 1),
      ],
    );
  }
}

/// La barra fija de abajo.
class _BarraAccion extends StatelessWidget {
  const _BarraAccion({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: 216,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AztecTheme.coral,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
            ),
            // Agendar la visita en el calendario quedó para fase 2, y el botón
            // está en el diseño de esta pantalla. Se pinta, y al tocarlo dice
            // la verdad en vez de no hacer nada.
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Scheduling lands in a later sprint.'),
              ),
            ),
            child: Text('Schedule a visit',
                style: AztecTheme.textoBoton.copyWith(color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

/// El teaser. Lo que se ofrece a cambio de los 15 dólares.
class _Candado extends StatelessWidget {
  const _Candado();

  /// La mitad de este botón ya funciona y la otra todavía no, y la diferencia
  /// importa: sin sesión no hay a quién concederle el desbloqueo, así que ese
  /// paso —pedir la cuenta— se hace aquí y ahora. La compra en sí espera a que
  /// los productos estén dados de alta en App Store Connect y en Play Console;
  /// el backend ya tiene los endpoints (`/payments/confirm`, `/payments/restore`)
  /// y lo que falta es la parte del cliente con `in_app_purchase`.
  Future<void> _pulsarDesbloquear(BuildContext context) async {
    final sesion = SessionScope.sin(context);

    if (!sesion.haySesion) {
      final entro = await pedirEntrar(
        context,
        motivo: 'The unlock is tied to your account, so it follows you to any '
            'device. Create one to continue.',
        registro: true,
      );
      if (!entro) return;
      // Con sesión nueva puede que la cuenta YA tuviera el desbloqueo comprado
      // en otro dispositivo. `refrescarUsuario` lo trae y la ficha se repinta
      // sin candado.
      await sesion.refrescarUsuario();
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'In-app purchase is not wired up yet — the store products still need '
          'to be created.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AztecTheme.tinta,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.lock_outline, color: Colors.white, size: 20),
            SizedBox(width: 9),
            Text('Unlock the full story',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          Text(
            'One payment unlocks every site, every article and every audio '
            'tour. No subscription — it never expires.',
            style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 14.5,
                height: 1.5),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AztecTheme.coral,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => _pulsarDesbloquear(context),
              child: Text(
                SessionScope.of(context).haySesion
                    ? 'Unlock for \$15'
                    : 'Sign in to unlock',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
