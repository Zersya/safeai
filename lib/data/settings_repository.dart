import 'package:shared_preferences/shared_preferences.dart';

import '../core/native_bridge.dart';

const chromePackage = 'com.android.chrome';

class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _onboardingKey = 'onboarding_done';
  static const _browserKey = 'browser_package';

  bool get onboardingDone => _prefs.getBool(_onboardingKey) ?? false;
  Future<void> setOnboardingDone(bool value) => _prefs.setBool(_onboardingKey, value);

  /// Explicit browser choice; null means automatic.
  String? get browserPackage => _prefs.getString(_browserKey);

  Future<void> setBrowserPackage(String? package) => package == null
      ? _prefs.remove(_browserKey)
      : _prefs.setString(_browserKey, package);
}

/// The browser links are opened in: the saved choice if still installed,
/// otherwise Chrome, otherwise the first installed browser, otherwise null
/// (native side then shows a chooser).
BrowserInfo? chooseBrowser(List<BrowserInfo> installed, String? saved) {
  if (saved != null) {
    for (final b in installed) {
      if (b.package == saved) return b;
    }
  }
  for (final b in installed) {
    if (b.package == chromePackage) return b;
  }
  return installed.isEmpty ? null : installed.first;
}
