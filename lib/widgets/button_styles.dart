import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../core/theme/app_theme.dart';

/// Centralized button styling for the app.
/// Provides consistent elevation, focus states, and disabled states.
class AppButtonStyles {
  AppButtonStyles._();

  /// Primary action button (solid, elevated)
  static ButtonStyle primaryButton({
    double? width,
    double height = 48,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    );
  }

  /// Secondary action button (outlined)
  static ButtonStyle secondaryButton({
    double? width,
    double height = 48,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: AppTheme.primary,
      side: const BorderSide(color: AppTheme.primary, width: 1.5),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    );
  }

  /// Tertiary action button (ghost/text only)
  static ButtonStyle tertiaryButton({
    double? width,
    double height = 48,
  }) {
    return TextButton.styleFrom(
      foregroundColor: AppTheme.primary,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    );
  }

  /// Danger button (for destructive actions)
  static ButtonStyle dangerButton({
    double? width,
    double height = 48,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: AppTheme.errorRed,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    );
  }
}

/// Animated button with scale feedback on press.
class AnimatedPressButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final bool enabled;
  final Duration duration;
  final double scale;

  const AnimatedPressButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.enabled = true,
    this.duration = AppDuration.fast,
    this.scale = 0.95,
  });

  @override
  State<AnimatedPressButton> createState() => _AnimatedPressButtonState();
}

class _AnimatedPressButtonState extends State<AnimatedPressButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerDown(_) {
    if (!widget.enabled) return;
    _controller.forward();
  }

  void _onPointerUp(_) {
    _controller.reverse();
    if (widget.enabled) widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        child: ScaleTransition(
          scale: Tween<double>(begin: 1.0, end: widget.scale)
              .animate(CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOut,
          )),
          child: Opacity(
            opacity: widget.enabled ? 1.0 : 0.5,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
