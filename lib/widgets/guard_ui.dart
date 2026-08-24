import 'package:flutter/material.dart';

import 'package:flutter_application_1/theme/app_colors.dart';

/// Shared presentation pieces for the Guard mobile experience.
/// They intentionally contain no business or navigation logic.
class SentinelBrandMark extends StatelessWidget {
  const SentinelBrandMark({
    super.key,
    this.size = 48,
    this.framed = true,
    this.semanticLabel,
  });

  final double size;
  final bool framed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      'assets/branding/sentinel_link_mark.png',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
    if (!framed) return SizedBox.square(dimension: size, child: mark);

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .14),
      decoration: BoxDecoration(
        color: const Color(0xFF25071C),
        borderRadius: BorderRadius.circular(size * .27),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7F1230).withValues(alpha: .26),
            blurRadius: size * .28,
            offset: Offset(0, size * .08),
          ),
        ],
      ),
      child: mark,
    );
  }
}

class GuardSurfaceCard extends StatelessWidget {
  const GuardSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 20,
    this.color = AppColors.surface,
    this.borderColor = AppColors.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: AppColors.card(
      radius: radius,
      color: color,
      borderColor: borderColor,
    ),
    child: child,
  );
}

class GuardAmbientBackground extends StatelessWidget {
  const GuardAmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), AppColors.scaffold],
            ),
          ),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: -18, end: 0),
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, offset, _) => Positioned(
            left: -92 + offset,
            top: 42 + offset,
            child: Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.12),
                    AppColors.primary.withValues(alpha: 0.01),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: -120,
          bottom: -70,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class GuardPageTopBar extends StatelessWidget {
  const GuardPageTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.leadingIcon = Icons.arrow_back_ios_new_rounded,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final IconData leadingIcon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
    child: Row(
      children: [
        if (onBack != null) ...[
          GuardIconButton(
            icon: leadingIcon,
            tooltip: leadingIcon == Icons.close_rounded ? 'Close' : 'Back',
            onPressed: onBack,
            color: AppColors.text,
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    ),
  );
}

class GuardStatusBanner extends StatelessWidget {
  const GuardStatusBanner({
    super.key,
    required this.message,
    required this.color,
    required this.icon,
    this.title,
  });

  final String? title;
  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.24)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(
                  title!,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              Text(
                message,
                style: TextStyle(
                  color: title == null ? color : AppColors.textMuted,
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: title == null ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class GuardBusyLabel extends StatelessWidget {
  const GuardBusyLabel({
    super.key,
    required this.busy,
    required this.label,
    this.busyLabel,
    this.icon,
  });

  final bool busy;
  final String label;
  final String? busyLabel;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (busy)
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
      else if (icon != null)
        Icon(icon, size: 19),
      if (busy || icon != null) const SizedBox(width: 9),
      Flexible(child: Text(busy ? (busyLabel ?? label) : label)),
    ],
  );
}

class GuardPageHeader extends StatelessWidget {
  const GuardPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
      if (trailing != null) trailing!,
    ],
  );
}

class GuardLoadingView extends StatelessWidget {
  const GuardLoadingView({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 12),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class GuardEmptyState extends StatelessWidget {
  const GuardEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: AppColors.primary, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

Future<bool> showGuardConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Continue',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        destructive ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
        color: destructive ? AppColors.error : AppColors.primary,
      ),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.error)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

class GuardIconButton extends StatelessWidget {
  const GuardIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = AppColors.primary,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(12),
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 20),
    ),
  );
}
