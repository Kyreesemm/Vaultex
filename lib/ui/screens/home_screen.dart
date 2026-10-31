import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../data/models/vault_entry.dart';
import '../../logic/blocs/entries_bloc.dart';
import '../../logic/blocs/vault_bloc.dart';
import '../widgets/bento_grid.dart';
import '../widgets/password_generator_dialog.dart';
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

    return BlocBuilder<VaultBloc, VaultState>(
      builder: (context, vaultState) {
        if (vaultState is! VaultUnlocked) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final vaultInfo = vaultState.info;
        final hasConflict = vaultState.conflictDetected;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shield, color: AppTheme.primaryColor, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vaultInfo.name ?? 'Хранилище',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'AES-256-GCM • Argon2id',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.vpn_key_outlined),
                tooltip: 'Генератор паролей',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const PasswordGeneratorDialog(),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Настройки',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => SettingsDialog(
                      currentVaultPath: vaultInfo.path ?? '',
                      currentVaultName: vaultInfo.name ?? 'Хранилище',
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.lock_outline, color: Colors.amber),
                tooltip: 'Заблокировать (Затереть RAM)',
                onPressed: () {
                  context.read<VaultBloc>().add(LockVaultEvent());
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              // Syncthing Conflict Banner
              if (hasConflict)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Colors.amber.withOpacity(0.2),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Внимание: Файл хранилища обновлен внешней программой (Syncthing).',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Перезагрузить'),
                        onPressed: () {
                          context.read<VaultBloc>().add(CheckConflictEvent());
                          context.read<EntriesBloc>().add(const LoadEntriesEvent());
                        },
                      ),
                    ],
                  ),
                ),

              Expanded(
                child: isDesktop ? _buildDesktopLayout(context) : _buildMobileLayout(context),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Добавить'),
            onPressed: () => _openCreateScreen(context),
          ),
        );
      },
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    children: [
                      // Search bar
                      TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Поиск по сервисам, логинам, тегам...',
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
                      const SizedBox(height: 14),
                      // Bento Grid
                      BentoGrid(
                        totalAccounts: state.totalAccounts,
                        totalTokens: state.totalTokens,
                        totalSecrets: state.totalSecrets,
                        totalNotes: state.totalNotes,
                        selectedCategory: _selectedCategory,
                        onCategorySelected: _onCategoryChanged,
                      ),
                      const SizedBox(height: 14),
                      // Category Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip(EntryCategory.all, 'Все (${state.totalAll})'),
                            const SizedBox(width: 8),
                            _filterChip(EntryCategory.account, 'Аккаунты (${state.totalAccounts})'),
                            const SizedBox(width: 8),
                            _filterChip(EntryCategory.token, 'API Ключи (${state.totalTokens})'),
                            const SizedBox(width: 8),
                            _filterChip(EntryCategory.secret, 'Секреты (${state.totalSecrets})'),
                            const SizedBox(width: 8),
                            _filterChip(EntryCategory.note, 'Заметки (${state.totalNotes})'),
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
                        Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'Записей не найдено',
                          style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final entry = state.entries[index];
                        return _buildEntryCard(context, entry);
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
                    padding: const EdgeInsets.all(16),
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
                        const SizedBox(height: 12),
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
                        style: TextStyle(color: Colors.grey[500], fontSize: 16),
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
      margin: const EdgeInsets.only(bottom: 10),
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withOpacity(0.12)
                : (isDark ? const Color(0xFF1E293B) : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? color
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(EntryCategory cat, String label) {
    final isSelected = _selectedCategory == cat;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label),
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
