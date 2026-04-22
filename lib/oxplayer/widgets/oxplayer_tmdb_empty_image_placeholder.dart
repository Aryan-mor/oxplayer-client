import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// TMDB-style grey “no image” glyph (bundled asset from themoviedb.org glyphicons).
class OxplayerTmdbEmptyImagePlaceholder extends StatelessWidget {
  const OxplayerTmdbEmptyImagePlaceholder({super.key});

  static const assetPath = 'assets/oxplayer/tmdb_picture_placeholder.svg';

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxSide = constraints.biggest.shortestSide;
            final iconSize = maxSide.isFinite ? (maxSide * 0.42).clamp(28.0, 80.0) : 48.0;
            return SvgPicture.asset(
              assetPath,
              width: iconSize,
              height: iconSize,
              fit: BoxFit.contain,
            );
          },
        ),
      ),
    );
  }
}
