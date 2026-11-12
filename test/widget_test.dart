import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultex/core/settings_service.dart';
import 'package:vaultex/data/models/vault_entry.dart';
import 'package:vaultex/ui/widgets/bento_grid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ParsedAccountData json serialization and category test', () {
    final acc = ParsedAccountData(
      service: 'GitHub',
      username: 'octocat',
      email: 'octo@github.com',
      password: 'password123',
    );
    final json = acc.toJson();
    final restored = ParsedAccountData.fromJson(json);

    expect(restored.service, 'GitHub');
    expect(restored.username, 'octocat');
    expect(restored.email, 'octo@github.com');
    expect(restored.password, 'password123');
  });

  test('VaultEntry category resolution test', () {
    const entry = VaultEntry(
      id: 'abc123',
      kind: 'api_token',
      title: 'OpenAI Key',
      subtitle: 'Production',
      tags: ['ai', 'prod'],
      revision: 1,
      payloadJson: '{"name":"OpenAI Key","token":"sk-12345"}',
    );

    expect(entry.category, EntryCategory.token);
    expect(entry.tokenData?.token, 'sk-12345');
  });

  test('ParsedAccountData handles 2FA TOTP secret key', () {
    final acc = ParsedAccountData(
      service: 'Google',
      username: 'user@gmail.com',
      email: 'user@gmail.com',
      password: 'password123',
      twoFactorSecret: 'JBSWY3DPEHPK3PXP',
    );
    final json = acc.toJson();
    final restored = ParsedAccountData.fromJson(json);

    expect(restored.twoFactorSecret, 'JBSWY3DPEHPK3PXP');
  });

  test('StatsDisplayMode resolution and defaults', () {
    expect(StatsDisplayMode.fromId('compact'), StatsDisplayMode.compact);
    expect(StatsDisplayMode.fromId('progressBar'), StatsDisplayMode.progressBar);
    expect(StatsDisplayMode.fromId('hidden'), StatsDisplayMode.hidden);
    expect(StatsDisplayMode.fromId('unknown'), StatsDisplayMode.compact);
    expect(StatsDisplayMode.fromId(null), StatsDisplayMode.compact);
  });

  testWidgets('BentoGrid renders compact mode correctly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BentoGrid(
            totalAccounts: 24,
            totalTokens: 8,
            totalSecrets: 5,
            totalNotes: 14,
            selectedCategory: EntryCategory.all,
            onCategorySelected: (_) {},
            overrideMode: StatsDisplayMode.compact,
          ),
        ),
      ),
    );

    expect(find.text('24'), findsOneWidget);
    expect(find.text('Аккаунты'), findsOneWidget);
    expect(find.text('Ключи'), findsOneWidget);
    expect(find.text('Секреты'), findsOneWidget);
    expect(find.text('Заметки'), findsOneWidget);
  });

  testWidgets('BentoGrid renders progressBar mode correctly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BentoGrid(
            totalAccounts: 24,
            totalTokens: 8,
            totalSecrets: 5,
            totalNotes: 14,
            selectedCategory: EntryCategory.all,
            onCategorySelected: (_) {},
            overrideMode: StatsDisplayMode.progressBar,
          ),
        ),
      ),
    );

    expect(find.text('Всего записей в сейфе'), findsOneWidget);
    expect(find.text('51'), findsOneWidget);
    expect(find.text('API Ключи'), findsOneWidget);
  });

  testWidgets('BentoGrid renders hidden mode correctly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BentoGrid(
            totalAccounts: 24,
            totalTokens: 8,
            totalSecrets: 5,
            totalNotes: 14,
            selectedCategory: EntryCategory.all,
            onCategorySelected: (_) {},
            overrideMode: StatsDisplayMode.hidden,
          ),
        ),
      ),
    );

    expect(find.text('Всего записей в сейфе'), findsNothing);
    expect(find.text('Аккаунты'), findsNothing);
  });
}
