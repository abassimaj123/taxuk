import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';

/// Responsive layout helper for adapting UI to different screen sizes.
/// Mobile: < 600dp, Tablet: 600-1024dp, Desktop: > 1024dp
class ResponsiveLayout {
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 1024;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1024;

  static double getContentWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (isDesktop(context)) return 1000;
    if (isTablet(context)) return width * 0.85;
    return double.infinity;
  }

  static int getGridColumns(BuildContext context) {
    if (isDesktop(context)) return 3;
    if (isTablet(context)) return 2;
    return 1;
  }
}

/// Two-column layout for tablets/desktop showing form and results side-by-side.
class DualPaneLayout extends StatelessWidget {
  final Widget leftPane;
  final Widget rightPane;
  final BuildContext context;

  const DualPaneLayout({
    super.key,
    required this.leftPane,
    required this.rightPane,
    required this.context,
  });

  @override
  Widget build(BuildContext context) {
    if (ResponsiveLayout.isMobile(context)) {
      // Mobile: stack vertically
      return SingleChildScrollView(
        child: Column(
          children: [
            leftPane,
            const SizedBox(height: AppSpacing.lg),
            rightPane,
          ],
        ),
      );
    }

    // Tablet+: side by side with scroll
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 1,
          child: SingleChildScrollView(child: leftPane),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          flex: 1,
          child: SingleChildScrollView(child: rightPane),
        ),
      ],
    );
  }
}
