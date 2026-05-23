import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../core/theme/app_theme.dart';

/// Error state widget for displaying errors to the user.
class ErrorStateWidget extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  const ErrorStateWidget({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    final ct = CalcwiseTheme.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Error icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: AppTheme.errorRed,
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

              // Message
              Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  color: ct.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxxl),

              // Action button
              if (actionLabel != null && onAction != null)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                    ),
                    child: Text(
                      actionLabel!,
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

/// Dialog for displaying errors.
Future<void> showErrorDialog(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = 'OK',
}) async {
  final ct = CalcwiseTheme.of(context);
  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: ct.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: ct.cardBorder),
      ),
      icon: const Icon(
        Icons.error_outline,
        color: AppTheme.errorRed,
        size: 32,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: ct.textPrimary,
        ),
      ),
      content: Text(
        message,
        style: TextStyle(
          fontSize: 14,
          color: ct.textSecondary,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            actionLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ),
      ],
    ),
  );
}
