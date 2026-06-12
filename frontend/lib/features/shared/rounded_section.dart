import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';

class RoundedSection extends StatelessWidget {
  const RoundedSection({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(MetaSpacing.xxl),
    this.radius = MetaRadii.xxxl,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MetaColors.canvas,
        border: Border.all(color: MetaColors.hairlineSoft),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
