import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/models/vault_entry.dart';

class BentoGrid extends StatelessWidget {
  final int totalAccounts;
  final int totalTokens;
  final int totalSecrets;
  final int totalNotes;
  final EntryCategory selectedCategory;
  final ValueChanged<EntryCategory> onCategorySelected;

  const BentoGrid({
    super.key,
    required this.totalAccounts,
    required this.totalTokens,
    required this.totalSecrets,
    required this.totalNotes,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;

        if (isNarrow) {
          // Compact 2x2 grid for mobile phones
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.35,
            children: [
              _buildCard(
                context,
                title: 'Аккаунты',
                count: totalAccounts,
                icon: Icons.person_outline,
                color: AppTheme.accountColor,
                category: EntryCategory.account,
                isNarrow: true,
              ),
              _buildCard(
                context,
                title: 'API Ключи',
                count: totalTokens,
                icon: Icons.key_outlined,
                color: AppTheme.tokenColor,
                category: EntryCategory.token,
                isNarrow: true,
              ),
              _buildCard(
                context,
                title: 'Секреты / Сиды',
                count: totalSecrets,
                icon: Icons.shield_outlined,
                color: AppTheme.secretColor,
                category: EntryCategory.secret,
                isNarrow: true,
              ),
              _buildCard(
                context,
                title: 'Заметки',
                count: totalNotes,
                icon: Icons.description_outlined,
                color: AppTheme.noteColor,
                category: EntryCategory.note,
                isNarrow: true,
              ),
            ],
          );
        } else {
          // 4-column Bento row for desktop/tablet
          return Row(
            children: [
              Expanded(
                child: _buildCard(
                  context,
                  title: 'Аккаунты',
                  count: totalAccounts,
                  icon: Icons.person_outline,
                  color: AppTheme.accountColor,
                  category: EntryCategory.account,
                  isNarrow: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCard(
                  context,
                  title: 'API Ключи',
                  count: totalTokens,
                  icon: Icons.key_outlined,
                  color: AppTheme.tokenColor,
                  category: EntryCategory.token,
                  isNarrow: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCard(
                  context,
                  title: 'Секреты / Сиды',
                  count: totalSecrets,
                  icon: Icons.shield_outlined,
                  color: AppTheme.secretColor,
                  category: EntryCategory.secret,
                  isNarrow: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCard(
                  context,
                  title: 'Заметки',
                  count: totalNotes,
                  icon: Icons.description_outlined,
                  color: AppTheme.noteColor,
                  category: EntryCategory.note,
                  isNarrow: false,
                ),
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required EntryCategory category,
    required bool isNarrow,
  }) {
    final isSelected = selectedCategory == category;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        if (isSelected) {
          onCategorySelected(EntryCategory.all);
        } else {
          onCategorySelected(category);
        }
      },
      borderRadius: BorderRadius.circular(isNarrow ? 14 : 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 10 : 12,
          vertical: isNarrow ? 7 : 10,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.18)
              : (isDark ? AppTheme.cardDark : Colors.white),
          borderRadius: BorderRadius.circular(isNarrow ? 14 : 16),
          border: Border.all(
            color: isSelected
                ? color
                : (isDark ? AppTheme.cardBorderDark : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isNarrow ? 6 : 7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(isNarrow ? 9 : 11),
              ),
              child: Icon(icon, color: color, size: isNarrow ? 16 : 18),
            ),
            SizedBox(width: isNarrow ? 8 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: isNarrow ? 15 : 17,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppTheme.textPrimaryDark : Colors.black87,
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isNarrow ? 10 : 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppTheme.textSecondaryDark : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
