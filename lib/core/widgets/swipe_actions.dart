import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_colors.dart';
import '../app_theme.dart';

/// Swipe right → edit (blue), swipe left → delete (red).
///
/// The row always springs back; the action runs instead. Live (Firestore)
/// lists then remove/refresh the item themselves, which avoids the
/// "dismissed Dismissible is still in the tree" crash.
class SwipeActions extends StatelessWidget {
  final Widget child;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final String editLabel;
  final String deleteLabel;
  final IconData deleteIcon;
  final double radius;

  const SwipeActions({
    required super.key,
    required this.child,
    this.onEdit,
    this.onDelete,
    this.editLabel = 'Edit',
    this.deleteLabel = 'Delete',
    this.deleteIcon = Icons.delete_outline_rounded,
    this.radius = AppRadius.lg,
  });

  @override
  Widget build(BuildContext context) {
    if (onEdit == null && onDelete == null) return child;
    final direction = onEdit != null && onDelete != null
        ? DismissDirection.horizontal
        : onEdit != null
            ? DismissDirection.startToEnd
            : DismissDirection.endToStart;

    return Dismissible(
      key: key!,
      direction: direction,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.28,
        DismissDirection.endToStart: 0.28,
      },
      movementDuration: AppMotion.normal,
      background: _bg(
        color: AppColors.primary,
        icon: Icons.edit_rounded,
        label: editLabel,
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _bg(
        color: AppColors.error,
        icon: deleteIcon,
        label: deleteLabel,
        alignment: Alignment.centerRight,
      ),
      confirmDismiss: (dir) async {
        HapticFeedback.mediumImpact();
        if (dir == DismissDirection.startToEnd) {
          onEdit?.call();
        } else {
          onDelete?.call();
        }
        return false; // spring back; the action decides what happens
      },
      child: child,
    );
  }

  Widget _bg({
    required Color color,
    required IconData icon,
    required String label,
    required Alignment alignment,
  }) {
    final left = alignment == Alignment.centerLeft;
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!left)
            Text(label,
                style: TextStyle(
                    color: AppColors.onPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
          if (!left) const SizedBox(width: 8),
          Icon(icon, color: AppColors.onPrimary, size: 22),
          if (left) const SizedBox(width: 8),
          if (left)
            Text(label,
                style: TextStyle(
                    color: AppColors.onPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }
}

/// Small muted hint line, e.g. "Swipe left to delete, right to edit".
class SwipeHint extends StatelessWidget {
  final String text;
  const SwipeHint({super.key, this.text = 'Swipe right to edit · left to delete'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swipe_rounded, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
