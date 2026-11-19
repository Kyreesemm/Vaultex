/// Helper utilities for formatting and displaying vault metadata cleanly.
String formatVaultDisplayName(String rawName) {
  // Strip trailing .vex or .vault extension
  var name = rawName.replaceAll(RegExp(r'\.(vex|vault)$', caseSensitive: false), '');
  // Replace underscores with spaces (e.g. Test_Vault -> Test Vault)
  name = name.replaceAll('_', ' ').trim();
  return name.isEmpty ? 'Хранилище' : name;
}
