import 'package:flutter/material.dart';

/// The carousel's default edge vignette.
///
/// The hero darkens its own edges by default — a left-to-right wash for text
/// contrast and a bottom wash that dissolves it into the page. The card is
/// therefore *darker at the edges than its own artwork*, and a flight that
/// carried the bare artwork would swap a vignetted picture for an unvignetted
/// one at one end: a brightness step at the edges, on both directions.
///
/// Both washes are alignment-based, so they scale with whatever rectangle the
/// flight is passing through; the hero keeps its extra 120 px top band for the
/// header badges, which is left out here on purpose — it is fixed height and
/// would not scale.
class HomeHeroVignette extends StatelessWidget {
  const HomeHeroVignette({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Color(0xF5080B12),
                  Color(0xD8080B12),
                  Color(0x75080B12),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.38, 0.65, 1.0],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: const [Color(0xD0080B12), Colors.transparent],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
