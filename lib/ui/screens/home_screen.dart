import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../data/models/vault_entry.dart';
import '../../logic/blocs/entries_bloc.dart';
import '../../logic/blocs/vault_bloc.dart';
import '../widgets/bento_grid.dart';
import '../widgets/password_generator_dialog.dart';
import '../widgets/vaultex_header_bar.dart';
import 'entry_detail_screen.dart';
import 'entry_edit_screen.dart';
import 'settings_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  EntryCategory _selectedCategory = EntryCategory.all;
  VaultEntry? _selectedEntryForDesktop;

  @override
  void initState() {
    super.initState();
    context.read<EntriesBloc>().add(const LoadEntriesEvent());
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
          // Floating custom Vaultex header bar replacing generic appbar
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(isCompact ? 60 : 66),
            child: SafeArea(
              bottom: false,
              child: VaultexHeaderBar(
                vaultName: vaultInfo.name ?? 'Хранилище',
                vaultPath: vaultInfo.path,
                onOpenGenerator: () {
                  showDialog(
                    context: context,
                    builder: (_) => const PasswordGeneratorDialog(),
                  );
                },
                onOpenSettings: () {
                  showDialog(
                    context: context,
                    builder: (_) => SettingsDialog(
                      currentVaultPath: vaultInfo.path ?? '',
                      currentVaultName: vaultInfo.name ?? 'Хранилище',
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
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            elevation: 4,
            icon: const Icon(Icons.add),
            label: const Text('Добавить', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _openCreateScreen(context),
          ),
        );
      },
    );
  }

  Widget _buildMobileLayout(BuildContext context, bool isCompact) {
    final horizontalPad = isCompact ? 12.0 : 16.0;

    return BlocBuilder<EntriesBloc, EntriesState>(
      builder: (context, state) {
        if (state is EntriesLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is EntriesLoaded) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(horizontalPad, 6, horizontalPad, 8),
                  child: Column(
                    children: [
                      // Search bar
                      TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: TextStyle(fontSize: isCompact ? 13 : 14),
                        decoration: InputDecoration(
                          hintText: 'Поиск по сервисам, логинам, тегам...',
                          hintStyle: TextStyle(fontSize: isCompact ? 13 : 14),
                          prefixIcon: Icon(Icons.search, size: isCompact ? 20 : 22),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: isCompact ? 11 : 14,
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
                      SizedBox(height: isCompact ? 8 : 12),

                      // Bento Grid
                      BentoGrid(
                        totalAccounts: state.totalAccounts,
                        totalTokens: state.totalTokens,
                        totalSecrets: state.totalSecrets,
                        totalNotes: state.totalNotes,
                        selectedCategory: _selectedCategory,
                        onCategorySelected: _onCategoryChanged,
                      ),
                      SizedBox(height: isCompact ? 8 : 12),

                      // Category Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip(EntryCategory.all, 'Все (${state.totalAll})', isCompact),
                            const SizedBox(width: 6),
                            _filterChip(EntryCategory.account, 'Аккаунты (${state.totalAccounts})', isCompact),
                            const SizedBox(width: 6),
                            _filterChip(EntryCategory.token, 'API (${state.totalTokens})', isCompact),
                            const SizedBox(width: 6),
                            _filterChip(EntryCategory.secret, 'Секреты (${state.totalSecrets})', isCompact),
                            const SizedBox(width: 6),
                            _filterChip(EntryCategory.note, 'Заметки (${state.totalNotes})', isCompact),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (state.entries.isEmpty)
                SliverFillRemaining(
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
                  padding: EdgeInsets.fromLTRB(horizontalPad, 2, horizontalPad, 80),
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
          );
        }

        return const Center(child: CircularProgressIndicator());
      },
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
                            hintText: 'Поиск...',
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
                        const SizedBox(height: 10),
                        BentoGrid(
                          totalAccounts: state.totalAccounts,
                          totalTokens: state.totalTokens,
                          totalSecrets: state.totalSecrets,
                          totalNotes: state.totalNotes,
                          selectedCategory: _selectedCategory,
                          onCategorySelected: _onCategoryChanged,
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
      margin: EdgeInsets.only(bottom: isCompact ? 7 : 9),
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
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 12 : 14,
            vertical: isCompact ? 10 : 12,
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
              Container(
                padding: EdgeInsets.all(isCompact ? 7 : 9),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(isCompact ? 10 : 12),
                ),
                child: Icon(icon, color: color, size: isCompact ? 17 : 20),
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
    );
  }

  Widget _filterChip(EntryCategory cat, String label, bool isCompact) {
    final isSelected = _selectedCategory == cat;
    return ChoiceChip(
      selected: isSelected,
      label: Text(
        label,
        style: TextStyle(
          fontSize: isCompact ? 11 : 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 8, vertical: isCompact ? 2 : 4),
      onSelected: (_) => _onCategoryChanged(cat),
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
