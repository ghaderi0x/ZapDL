import 'package:shared_preferences/shared_preferences.dart';

/// Most-recent-first list of links the user added, stored locally only.
class UrlHistory {
  UrlHistory(this._prefs);

  static const maxItems = 20;
  static const _key = 'urlHistory';

  final SharedPreferences _prefs;

  List<String> get items => _prefs.getStringList(_key) ?? const [];

  Future<void> add(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    final list = [u, ...items.where((x) => x != u)];
    await _prefs.setStringList(_key, list.take(maxItems).toList());
  }

  Future<void> clear() => _prefs.remove(_key);
}
