import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';

class RoundedSection extends StatelessWidget {
  const RoundedSection({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(MetaSpacing.lg),
    this.radius = MetaRadii.xl,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MetaColors.surface,
        border: Border.all(color: MetaColors.hairline),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: MetaColors.primaryDeep.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
