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
          // Horizontal scrolling or 2x2 grid
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.1,
            children: [
              _buildCard(
                context,
                title: 'Аккаунты',
                count: totalAccounts,
                icon: Icons.person_outline,
                color: AppTheme.accountColor,
                category: EntryCategory.account,
              ),
              _buildCard(
                context,
                title: 'API Ключи',
                count: totalTokens,
                icon: Icons.key_outlined,
                color: AppTheme.tokenColor,
                category: EntryCategory.token,
              ),
              _buildCard(
                context,
                title: 'Секреты / Сиды',
                count: totalSecrets,
                icon: Icons.shield_outlined,
                color: AppTheme.secretColor,
                category: EntryCategory.secret,
              ),
              _buildCard(
                context,
                title: 'Заметки',
                count: totalNotes,
                icon: Icons.description_outlined,
                color: AppTheme.noteColor,
                category: EntryCategory.note,
              ),
            ],
          );
        } else {
          // 4-column Bento row
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
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCard(
                  context,
                  title: 'API Ключи',
                  count: totalTokens,
                  icon: Icons.key_outlined,
                  color: AppTheme.tokenColor,
                  category: EntryCategory.token,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCard(
                  context,
                  title: 'Секреты / Сиды',
                  count: totalSecrets,
                  icon: Icons.shield_outlined,
                  color: AppTheme.secretColor,
                  category: EntryCategory.secret,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCard(
                  context,
                  title: 'Заметки',
                  count: totalNotes,
                  icon: Icons.description_outlined,
                  color: AppTheme.noteColor,
                  category: EntryCategory.note,
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
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.18)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
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
