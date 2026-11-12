import 'package:flutter/material.dart';
import '../../core/settings_service.dart';
import '../../core/theme.dart';
import '../../data/models/vault_entry.dart';

class BentoGrid extends StatelessWidget {
  final int totalAccounts;
  final int totalTokens;
  final int totalSecrets;
  final int totalNotes;
  final EntryCategory selectedCategory;
  final ValueChanged<EntryCategory> onCategorySelected;
  final StatsDisplayMode? overrideMode;

  const BentoGrid({
    super.key,
    required this.totalAccounts,
    required this.totalTokens,
    required this.totalSecrets,
    required this.totalNotes,
    required this.selectedCategory,
    required this.onCategorySelected,
    this.overrideMode,
  });

  @override
  Widget build(BuildContext context) {
    if (overrideMode != null) {
      return _buildForMode(context, overrideMode!);
    }

    return ValueListenableBuilder<StatsDisplayMode>(
      valueListenable: SettingsService().statsDisplayMode,
      builder: (context, mode, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1.0,
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey(mode),
            child: _buildForMode(context, mode),
          ),
        );
      },
    );
  }

  Widget _buildForMode(BuildContext context, StatsDisplayMode mode) {
    switch (mode) {
      case StatsDisplayMode.compact:
        return _buildCompactMainVariant(context);
      case StatsDisplayMode.progressBar:
        return _buildProgressBarVariant(context);
      case StatsDisplayMode.hidden:
        return const SizedBox.shrink();
    }
  }

  // ==========================================
  // Concept 1: stats_block_main.png (Compact 4-column card)
  // ==========================================
  Widget _buildCompactMainVariant(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.cardBorderDark,
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _buildMainColumn(
              context,
              category: EntryCategory.account,
              label: 'Аккаунты',
              count: totalAccounts,
              icon: Icons.person_outline,
              color: AppTheme.accountColor,
            ),
          ),
          _buildVerticalDivider(),
          Expanded(
            child: _buildMainColumn(
              context,
              category: EntryCategory.token,
              label: 'Ключи',
              count: totalTokens,
              icon: Icons.key_outlined,
              color: AppTheme.tokenColor,
            ),
          ),
          _buildVerticalDivider(),
          Expanded(
            child: _buildMainColumn(
              context,
              category: EntryCategory.secret,
              label: 'Секреты',
              count: totalSecrets,
              icon: Icons.shield_outlined,
              color: AppTheme.secretColor,
            ),
          ),
          _buildVerticalDivider(),
          Expanded(
            child: _buildMainColumn(
              context,
              category: EntryCategory.note,
              label: 'Заметки',
              count: totalNotes,
              icon: Icons.description_outlined,
              color: AppTheme.noteColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      width: 1,
      height: 36,
      color: AppTheme.cardBorderDark.withOpacity(0.6),
    );
  }

  Widget _buildMainColumn(
    BuildContext context, {
    required EntryCategory category,
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = selectedCategory == category;

    return InkWell(
      onTap: () {
        if (isSelected) {
          onCategorySelected(EntryCategory.all);
        } else {
          onCategorySelected(category);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon badge in rounded box
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 6),
                // Count number
                Text(
                  count.toString(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? color : AppTheme.textSecondaryDark,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // Concept 2: stats_block_variant_2.png (With Progress Bar)
  // ==========================================
  Widget _buildProgressBarVariant(BuildContext context) {
    final total = totalAccounts + totalTokens + totalSecrets + totalNotes;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.cardBorderDark,
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: "Всего записей в сейфе" and total count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Всего записей в сейфе',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondaryDark,
                ),
              ),
              Text(
                total.toString(),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Middle row: Multi-segment colored progress bar
          _buildSegmentedProgressBar(total),
          const SizedBox(height: 14),

          // Bottom 2x2 items
          Row(
            children: [
              Expanded(
                child: _buildVariant2Item(
                  category: EntryCategory.account,
                  label: 'Аккаунты',
                  count: totalAccounts,
                  icon: Icons.person_outline,
                  color: AppTheme.accountColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVariant2Item(
                  category: EntryCategory.token,
                  label: 'API Ключи',
                  count: totalTokens,
                  icon: Icons.key_outlined,
                  color: AppTheme.tokenColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildVariant2Item(
                  category: EntryCategory.secret,
                  label: 'Секреты',
                  count: totalSecrets,
                  icon: Icons.shield_outlined,
                  color: AppTheme.secretColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVariant2Item(
                  category: EntryCategory.note,
                  label: 'Заметки',
                  count: totalNotes,
                  icon: Icons.description_outlined,
                  color: AppTheme.noteColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedProgressBar(int total) {
    if (total <= 0) {
      return Container(
        height: 6,
        decoration: BoxDecoration(
          color: AppTheme.cardBorderDark,
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }

    // Build segments proportionally
    final segments = <_ProgressSegment>[
      _ProgressSegment(count: totalAccounts, color: AppTheme.accountColor),
      _ProgressSegment(count: totalTokens, color: AppTheme.tokenColor),
      _ProgressSegment(count: totalSecrets, color: AppTheme.secretColor),
      _ProgressSegment(count: totalNotes, color: AppTheme.noteColor),
    ];

    final nonZeroSegments = segments.where((s) => s.count > 0).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Row(
          children: nonZeroSegments.map((segment) {
            final isLast = segment == nonZeroSegments.last;
            return Expanded(
              flex: segment.count,
              child: Container(
                margin: EdgeInsets.only(right: isLast ? 0 : 4),
                decoration: BoxDecoration(
                  color: segment.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildVariant2Item({
    required EntryCategory category,
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = selectedCategory == category;

    return InkWell(
      onTap: () {
        if (isSelected) {
          onCategorySelected(EntryCategory.all);
        } else {
          onCategorySelected(category);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? color : AppTheme.textPrimaryDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              count.toString(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressSegment {
  final int count;
  final Color color;

  const _ProgressSegment({required this.count, required this.color});
}
