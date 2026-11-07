import 'package:flutter_test/flutter_test.dart';
import 'package:vaultex/data/models/vault_entry.dart';

void main() {
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
}
