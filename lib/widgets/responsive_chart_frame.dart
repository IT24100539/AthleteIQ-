import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Chart host that shrinks height on narrow phones instead of overflowing.
class ResponsiveChartFrame extends StatelessWidget {
  final Widget Function(BuildContext context, Size size) builder;
  final double maxHeight;
  final double minHeight;
  final double heightFactor;
  final EdgeInsetsGeometry padding;

  const ResponsiveChartFrame({
    super.key,
    required this.builder,
    this.maxHeight = 240,
    this.minHeight = 150,
    this.heightFactor = 0.68,
    this.padding = const EdgeInsets.fromLTRB(4, 12, 12, 4),
  });

  static double heightFor(
    double width, {
    double maxHeight = 240,
    double minHeight = 150,
    double heightFactor = 0.68,
  }) {
    return (width * heightFactor).clamp(minHeight, maxHeight);
  }

  static double leftTitleSize(double width, {double wide = 40, double narrow = 28}) {
    return width < 360 ? narrow : wide;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = heightFor(
          width,
          maxHeight: maxHeight,
          minHeight: minHeight,
          heightFactor: heightFactor,
        );
        final size = Size(width, height);
        return RepaintBoundary(
          child: Container(
            width: width,
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: builder(context, size),
          ),
        );
      },
    );
  }
}
