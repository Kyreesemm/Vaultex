import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/format_utils.dart';
import '../../core/theme.dart';
import '../../data/models/vault_entry.dart';
import '../../logic/blocs/entries_bloc.dart';
import '../../logic/blocs/vault_bloc.dart';
import '../widgets/bento_grid.dart';
import '../widgets/password_generator_dialog.dart';
import '../widgets/vaultex_header_bar.dart';
import 'entry_detail_screen.dart';
import 'entry_edit_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isSearchVisible = false;
  EntryCategory _selectedCategory = EntryCategory.all;
  VaultEntry? _selectedEntryForDesktop;

  @override
  void initState() {
    super.initState();
    context.read<EntriesBloc>().add(const LoadEntriesEvent());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onCategoryChanged(EntryCategory cat) {
    setState(() {
      _selectedCategory = cat;
    });
    context.read<EntriesBloc>().add(LoadEntriesEvent(
          category: cat,
          query: _searchController.text.trim(),
        ));
  }

  void _onSearchChanged(String query) {
    context.read<EntriesBloc>().add(LoadEntriesEvent(
          category: _selectedCategory,
          query: query.trim(),
        ));
  }

  bool _onScrollNotification(ScrollNotification notification) {
    // Detect downward pull/overscroll to reveal search bar
    if (notification is OverscrollNotification && notification.overscroll < -10) {
      if (!_isSearchVisible) {
        setState(() => _isSearchVisible = true);
        _searchFocusNode.requestFocus();
      }
    } else if (notification is ScrollUpdateNotification) {
      if (notification.metrics.pixels <= 0 &&
          notification.scrollDelta != null &&
          notification.scrollDelta! < -14) {
        if (!_isSearchVisible) {
          setState(() => _isSearchVisible = true);
          _searchFocusNode.requestFocus();
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    final isCompact = screenWidth < 600;

    return BlocBuilder<VaultBloc, VaultState>(
      builder: (context, vaultState) {
        if (vaultState is! VaultUnlocked) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final vaultInfo = vaultState.info;
        final hasConflict = vaultState.conflictDetected;

        return Scaffold(
          // Clean header bar sitting directly at top without island container
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(isCompact ? 54 : 58),
            child: SafeArea(
              bottom: false,
              child: VaultexHeaderBar(
                vaultName: formatVaultDisplayName(vaultInfo.name ?? 'Хранилище'),
                vaultPath: vaultInfo.path,
                onOpenGenerator: () {
                  showDialog(
                    context: context,
                    builder: (_) => const PasswordGeneratorDialog(),
                  );
                },
                onOpenSettings: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        currentVaultPath: vaultInfo.path ?? '',
                        currentVaultName: formatVaultDisplayName(vaultInfo.name ?? 'Хранилище'),
                      ),
                    ),
                  );
                },
                onLockVault: () {
                  context.read<VaultBloc>().add(LockVaultEvent());
                },
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                // Syncthing Conflict Banner
                if (hasConflict)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.amber.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Внимание: Файл обновлен внешней программой (Syncthing).',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.refresh, size: 14),
                          label: const Text('Обновить', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            context.read<VaultBloc>().add(CheckConflictEvent());
                            context.read<EntriesBloc>().add(const LoadEntriesEvent());
                          },
                        ),
                      ],
                    ),
                  ),

                Expanded(
                  child: isDesktop
                      ? _buildDesktopLayout(context)
                      : _buildMobileLayout(context, isCompact),
                ),
              ],
            ),
          ),
          // Compact Floating Action Button with only "+"
          floatingActionButton: SizedBox(
            width: 48,
            height: 48,
            child: FloatingActionButton(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tooltip: 'Добавить запись',
              onPressed: () => _openCreateScreen(context),
              child: const Icon(Icons.add, size: 26),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileLayout(BuildContext context, bool isCompact) {
    final horizontalPad = isCompact ? 14.0 : 16.0;

    return BlocBuilder<EntriesBloc, EntriesState>(
      builder: (context, state) {
        if (state is EntriesLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is EntriesLoaded) {
          return NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(horizontalPad, 6, horizontalPad, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search bar revealed on swipe down
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          child: (_isSearchVisible || _searchController.text.isNotEmpty)
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _searchController,
                                          focusNode: _searchFocusNode,
                                          onChanged: _onSearchChanged,
                                          style: TextStyle(fontSize: isCompact ? 13 : 14),
                                          decoration: InputDecoration(
                                            hintText: 'Поиск по сервисам, логинам, тегам...',
                                            hintStyle: TextStyle(
                                              fontSize: isCompact ? 13 : 14,
                                              color: AppTheme.textSecondaryDark,
                                            ),
                                            prefixIcon: Icon(Icons.search, size: isCompact ? 20 : 22),
                                            contentPadding: EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: isCompact ? 10 : 12,
                                            ),
                                            suffixIcon: _searchController.text.isNotEmpty
                                                ? IconButton(
                                                    icon: const Icon(Icons.clear, size: 18),
                                                    onPressed: () {
                                                      _searchController.clear();
                                                      _onSearchChanged('');
                                                    },
                                                  )
                                                : null,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 24),
                                        tooltip: 'Скрыть поиск',
                                        onPressed: () {
                                          setState(() {
                                            _isSearchVisible = false;
                                            _searchController.clear();
                                            _onSearchChanged('');
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),

                        // Redesigned Statistics Block (Main concept, Variant 2, or Hidden)
                        BentoGrid(
                          totalAccounts: state.totalAccounts,
                          totalTokens: state.totalTokens,
                          totalSecrets: state.totalSecrets,
                          totalNotes: state.totalNotes,
                          selectedCategory: _selectedCategory,
                          onCategorySelected: _onCategoryChanged,
                        ),
                        SizedBox(height: isCompact ? 10 : 14),

                        // Category Filter Chips (without counts, purple selection, subtle borders, reduced height)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              _buildCategoryChip(EntryCategory.all, 'Все', isCompact),
                              _buildCategoryChip(EntryCategory.account, 'Аккаунты', isCompact),
                              _buildCategoryChip(EntryCategory.token, 'API Ключи', isCompact),
                              _buildCategoryChip(EntryCategory.secret, 'Секреты', isCompact),
                              _buildCategoryChip(EntryCategory.note, 'Заметки', isCompact),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
                if (state.entries.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined, size: 52, color: Colors.grey[500]),
                          const SizedBox(height: 10),
                          Text(
                            'Записей не найдено',
                            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(horizontalPad, 6, horizontalPad, 84),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final entry = state.entries[index];
                          return _buildEntryCard(context, entry, isCompact: isCompact);
                        },
                        childCount: state.entries.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildCategoryChip(EntryCategory cat, String label, bool isCompact) {
    final isSelected = _selectedCategory == cat;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => _onCategoryChanged(cat),
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 13 : 15,
            vertical: isCompact ? 5 : 6,
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor : AppTheme.cardDark,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryColor
                  : AppTheme.cardBorderDark.withOpacity(0.9),
              width: 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.32),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: isCompact ? 12 : 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : AppTheme.textSecondaryDark,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return BlocBuilder<EntriesBloc, EntriesState>(
      builder: (context, state) {
        if (state is! EntriesLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        return Row(
          children: [
            // Left Pane: Search, Bento Grid & Entries List
            SizedBox(
              width: 440,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Поиск по записям...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      _onSearchChanged('');
                                    },
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        BentoGrid(
                          totalAccounts: state.totalAccounts,
                          totalTokens: state.totalTokens,
                          totalSecrets: state.totalSecrets,
                          totalNotes: state.totalNotes,
                          selectedCategory: _selectedCategory,
                          onCategorySelected: _onCategoryChanged,
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildCategoryChip(EntryCategory.all, 'Все', false),
                              _buildCategoryChip(EntryCategory.account, 'Аккаунты', false),
                              _buildCategoryChip(EntryCategory.token, 'API Ключи', false),
                              _buildCategoryChip(EntryCategory.secret, 'Секреты', false),
                              _buildCategoryChip(EntryCategory.note, 'Заметки', false),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: state.entries.isEmpty
                        ? const Center(child: Text('Записей не найдено'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: state.entries.length,
                            itemBuilder: (context, index) {
                              final entry = state.entries[index];
                              final isSelected = _selectedEntryForDesktop?.id == entry.id;
                              return _buildEntryCard(
                                context,
                                entry,
                                isCompact: false,
                                isSelected: isSelected,
                                onSelect: () {
                                  setState(() => _selectedEntryForDesktop = entry);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            // Right Pane: Detail View
            Expanded(
              child: _selectedEntryForDesktop == null
                  ? Center(
                      child: Text(
                        'Выберите запись для просмотра',
                        style: TextStyle(color: Colors.grey[500], fontSize: 15),
                      ),
                    )
                  : EntryDetailScreen(entry: _selectedEntryForDesktop!),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEntryCard(
    BuildContext context,
    VaultEntry entry, {
    required bool isCompact,
    bool isSelected = false,
    VoidCallback? onSelect,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color color;
    IconData icon;
    switch (entry.category) {
      case EntryCategory.account:
        color = AppTheme.accountColor;
        icon = Icons.person_outline;
        break;
      case EntryCategory.token:
        color = AppTheme.tokenColor;
        icon = Icons.key_outlined;
        break;
      case EntryCategory.secret:
        color = AppTheme.secretColor;
        icon = Icons.shield_outlined;
        break;
      case EntryCategory.note:
      default:
        color = AppTheme.noteColor;
        icon = Icons.description_outlined;
        break;
    }

    return Container(
      // Slightly larger distance between cards as requested
      margin: EdgeInsets.only(bottom: isCompact ? 10 : 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (onSelect != null) {
              onSelect();
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EntryDetailScreen(entry: entry)),
              );
            }
          },
          borderRadius: BorderRadius.circular(isCompact ? 14 : 16),
          child: Container(
            // Compact padding so the card height does NOT increase
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 14,
              vertical: isCompact ? 9 : 10,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withOpacity(0.12)
                  : (isDark ? AppTheme.cardDark : Colors.white),
              borderRadius: BorderRadius.circular(isCompact ? 14 : 16),
              border: Border.all(
                color: isSelected
                    ? color
                    : (isDark ? AppTheme.cardBorderDark : const Color(0xFFE2E8F0)),
                width: isSelected ? 1.8 : 1.0,
              ),
            ),
            child: Row(
              children: [
                // Slightly larger icon container with larger icon
                Container(
                  width: isCompact ? 36 : 40,
                  height: isCompact ? 36 : 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(isCompact ? 10 : 12),
                  ),
                  child: Icon(icon, color: color, size: isCompact ? 22 : 24),
                ),
                SizedBox(width: isCompact ? 10 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: TextStyle(
                          fontSize: isCompact ? 14 : 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.textPrimaryDark : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.subtitle,
                        style: TextStyle(
                          fontSize: isCompact ? 11 : 12,
                          color: isDark ? AppTheme.textSecondaryDark : Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCreateScreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntryEditScreen(initialCategory: _selectedCategory),
      ),
    );
  }
}
