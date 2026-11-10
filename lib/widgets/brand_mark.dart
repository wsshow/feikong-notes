import 'package:flutter/material.dart';

import '../app.dart';

/// The FKNotes elephant-and-note brand mark.
class BrandMark extends StatelessWidget {
  static const assetName = 'assets/brand/fknotes_mark.png';

  final double size;
  final bool showSurface;

  const BrandMark({super.key, required this.size, this.showSurface = true});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * .22);
    return Container(
      width: size,
      height: size,
      foregroundDecoration: showSurface
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: context.appColors.line),
            )
          : null,
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          assetName,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
