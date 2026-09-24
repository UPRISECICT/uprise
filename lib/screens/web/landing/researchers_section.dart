import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'landing_common.dart';
import 'landing_motion.dart';
import 'landing_palette.dart';

// "The researchers" band shared by the admin and org About pages:
// an acknowledgment of the capstone adviser first, then the team.

class Researcher {
  final String name;
  final String role;
  final String imagePath;

  const Researcher(this.name, this.role, this.imagePath);
}

// Drop the adviser's photo at assets/images/team/adviser.jpg — until it
// exists a placeholder silhouette is shown.
const kCapstoneAdviser = Researcher(
  'Jayson A. Batoon, DIT',
  'Capstone Thesis Adviser',
  'assets/images/team/adviser.jpg',
);

const kResearchTeam = [
  Researcher(
    'Claudine Joy San Jose',
    'Leader · Web Developer · Documentation',
    'assets/images/team/claudine.jpg',
  ),
  Researcher(
    'Jayson Labor',
    'Assistant Leader · Web Developer · Documentation',
    'assets/images/team/jayson.jpg',
  ),
  Researcher(
    'Paul Arvin Castro',
    'UI/UX · Mobile Developer',
    'assets/images/team/paul.jpg',
  ),
  Researcher(
    'Arvin Joseph De Honor',
    'UI/UX · Mobile Developer',
    'assets/images/team/arvin.jpg',
  ),
  Researcher(
    'Carl Adrian Rivera',
    'UI/UX · Mobile Developer',
    'assets/images/team/carl.jpg',
  ),
];

class ResearchersSection extends StatelessWidget {
  final LandingPalette palette;

  /// Section label, e.g. "02 · THE RESEARCHERS".
  final String eyebrow;

  /// Band color; defaults to the palette's dark band.
  final Color? background;

  const ResearchersSection({
    required this.palette,
    this.eyebrow = 'THE RESEARCHERS',
    this.background,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final p = palette;
    final cardW = w < 420 ? (w - 16 * 2 - 16) / 2 : (w < 900 ? 180.0 : 188.0);

    return Container(
      width: double.infinity,
      // Solid (not a gradient) so it meets the About pages' section seams
      // cleanly on both edges.
      color: background ?? p.bandTop,
      child: LandingContainer(
        padding: EdgeInsets.symmetric(vertical: w < 600 ? 64 : 96),
        child: Column(
          children: [
            Reveal(
              child: Eyebrow(palette: p, text: eyebrow, dark: true),
            ),
            const SizedBox(height: 14),
            Reveal(
              delay: const Duration(milliseconds: 80),
              child: Text(
                'The people behind UPRISE',
                textAlign: TextAlign.center,
                style: GoogleFonts.beVietnamPro(
                  fontSize: w < 600 ? 28 : 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Reveal(
              delay: const Duration(milliseconds: 160),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Text(
                  'Developed as a capstone project of the College of '
                  'Information and Communications Technology, Bulacan State '
                  'University.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15,
                    height: 1.6,
                    color: Colors.white.withAlpha(170),
                  ),
                ),
              ),
            ),
            SizedBox(height: w < 600 ? 40 : 56),
            Reveal(
              delay: const Duration(milliseconds: 200),
              dy: 40,
              child: _AdviserCard(palette: p, adviser: kCapstoneAdviser),
            ),
            SizedBox(height: w < 600 ? 48 : 72),
            Reveal(child: _Divider(label: 'THE RESEARCH TEAM')),
            const SizedBox(height: 36),
            Wrap(
              spacing: 24,
              runSpacing: 36,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < kResearchTeam.length; i++)
                  Reveal(
                    delay: Duration(milliseconds: 90 * i),
                    dy: 48,
                    scaleFrom: 0.94,
                    child: SizedBox(
                      width: cardW,
                      child: _MemberCard(palette: p, person: kResearchTeam[i]),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Portrait in a rounded-square frame. The photos are shot on white, so a
/// soft brand gradient is multiplied over them: the white backdrop takes
/// on the gradient (like a branded studio background) while faces, which
/// sit over the near-white middle of the gradient, stay natural.
class _Portrait extends StatelessWidget {
  final LandingPalette palette;
  final String imagePath;
  final double size;
  final bool hover;

  const _Portrait({
    required this.palette,
    required this.imagePath,
    required this.size,
    this.hover = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final radius = size * 0.13;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hover
              ? [p.accent, p.primary]
              : [Colors.white.withAlpha(70), Colors.white.withAlpha(25)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(hover ? 90 : 60),
            blurRadius: hover ? 34 : 24,
            offset: Offset(0, hover ? 18 : 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ShaderMask(
              blendMode: BlendMode.multiply,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(p.primary, Colors.white, 0.72)!,
                  const Color(0xFFF7F7FA),
                  Color.lerp(p.accent, Colors.white, 0.68)!,
                ],
                stops: const [0, 0.5, 1],
              ).createShader(r),
              child: AnimatedScale(
                scale: hover ? 1.06 : 1,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.white,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.person_rounded,
                      size: size * 0.45,
                      color: p.inkFaint,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberCard extends StatefulWidget {
  final LandingPalette palette;
  final Researcher person;

  const _MemberCard({required this.palette, required this.person});

  @override
  State<_MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<_MemberCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedSlide(
        offset: Offset(0, _hover ? -0.03 : 0),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: LayoutBuilder(
          builder: (context, c) => Column(
            children: [
              _Portrait(
                palette: widget.palette,
                imagePath: widget.person.imagePath,
                size: c.maxWidth,
                hover: _hover,
              ),
              const SizedBox(height: 16),
              Text(
                widget.person.name,
                textAlign: TextAlign.center,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                widget.person.role,
                textAlign: TextAlign.center,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  height: 1.45,
                  color: Colors.white.withAlpha(160),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdviserCard extends StatelessWidget {
  final LandingPalette palette;
  final Researcher adviser;

  const _AdviserCard({required this.palette, required this.adviser});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final narrow = MediaQuery.of(context).size.width < 760;

    final text = Column(
      crossAxisAlignment: narrow
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: p.accent.withAlpha(36),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_rounded, size: 14, color: p.accent),
              const SizedBox(width: 6),
              Text(
                'WITH GRATITUDE TO OUR ADVISER',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                  color: p.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          adviser.name,
          textAlign: narrow ? TextAlign.center : TextAlign.start,
          style: GoogleFonts.beVietnamPro(
            fontSize: narrow ? 24 : 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          adviser.role,
          style: GoogleFonts.beVietnamPro(
            fontSize: 14,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
            color: Colors.white.withAlpha(185),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Our sincere gratitude for your invaluable guidance, support, '
          'and encouragement throughout the development of UPRISE. Your '
          'insights and expertise have played an important role in shaping '
          'this project and guiding our team from its early stages to '
          'completion.',
          textAlign: narrow ? TextAlign.center : TextAlign.start,
          style: GoogleFonts.beVietnamPro(
            fontSize: 14.5,
            height: 1.7,
            color: Colors.white.withAlpha(175),
          ),
        ),
      ],
    );

    final portrait = _Portrait(
      palette: p,
      imagePath: adviser.imagePath,
      size: narrow ? 180 : 210,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: Container(
        padding: EdgeInsets.all(narrow ? 24 : 34),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withAlpha(28)),
        ),
        child: narrow
            ? Column(children: [portrait, const SizedBox(height: 22), text])
            : Row(
                children: [
                  portrait,
                  const SizedBox(width: 36),
                  Expanded(child: text),
                ],
              ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final String label;

  const _Divider({required this.label});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(height: 1, color: Colors.white.withAlpha(30)),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: Colors.white.withAlpha(150),
            ),
          ),
        ),
        line,
      ],
    );
  }
}
