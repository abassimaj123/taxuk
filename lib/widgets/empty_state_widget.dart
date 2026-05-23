import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Generic empty state widget for when there's no data to display.
/// Shows illustration area, title, description, and optional CTA.
class EmptyStateWidget extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final String? ctaLabel;
  final VoidCallback? onCTA;
  final Color? iconColor;

  const EmptyStateWidget({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.ctaLabel,
    this.onCTA,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxxl, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon illustration area
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: iconColor ?? AppTheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Title
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ct.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),

              // Description
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: ct.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxxl),

              // CTA Button
              if (ctaLabel != null && onCTA != null)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onCTA,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                    ),
                    child: Text(
                      ctaLabel!,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
