import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StatsDisplayMode {
  compact('compact', 'Компактная карточка', 'Горизонтальный блок с 4 колонками'),
  progressBar('progressBar', 'С прогресс-баром', 'Общий счетчик с цветной полосой распределения'),
  hidden('hidden', 'Скрыть', 'Не показывать блок статистики на главном экране');

  final String id;
  final String labelRu;
  final String descriptionRu;

  const StatsDisplayMode(this.id, this.labelRu, this.descriptionRu);

  static StatsDisplayMode fromId(String? id) {
    return StatsDisplayMode.values.firstWhere(
      (v) => v.id == id,
      orElse: () => StatsDisplayMode.compact,
    );
  }
}

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  final ValueNotifier<StatsDisplayMode> statsDisplayMode =
      ValueNotifier<StatsDisplayMode>(StatsDisplayMode.compact);

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeId = prefs.getString('stats_display_mode');
      statsDisplayMode.value = StatsDisplayMode.fromId(modeId);
    } catch (_) {
      // Fallback to default
    }
  }

  Future<void> setStatsDisplayMode(StatsDisplayMode mode) async {
    statsDisplayMode.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('stats_display_mode', mode.id);
    } catch (_) {}
  }
}
