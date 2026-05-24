import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../core/theme/app_theme.dart';

/// Skeleton loading widget for result cards.
/// Shows shimmer animation while data is loading.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: ct.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: ct.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ShimmerBox(width: 100, height: 12, ct: ct),
          const SizedBox(height: AppSpacing.sm),
          _ShimmerBox(width: double.infinity, height: 20, ct: ct),
          const SizedBox(height: AppSpacing.sm),
          _ShimmerBox(width: 80, height: 12, ct: ct),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double width, height;
  final CalcwiseTheme ct;
  const _ShimmerBox(
      {required this.width, required this.height, required this.ct});

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.ct.cardBorder;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: const [0.0, 0.5, 1.0],
              colors: [
                base,
                base.withValues(alpha: 0.5),
                base,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Loading skeleton for the entire calculator screen.
class CalculatorLoadingSkeleton extends StatelessWidget {
  const CalculatorLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        spacing: AppSpacing.lg,
        children: const [
          SkeletonCard(),
          SkeletonCard(),
          SkeletonCard(),
        ],
      ),
    );
  }
}
