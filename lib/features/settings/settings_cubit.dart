import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/native_bridge.dart';
import '../../data/settings_repository.dart';

/// Whether safeAI is the default browser. `null` until first read.
class ProtectionCubit extends Cubit<bool?> {
  ProtectionCubit(this._bridge) : super(null) {
    refresh();
  }

  final NativeBridge _bridge;

  Future<void> refresh() async {
    final active = await _bridge.isDefaultBrowser();
    if (!isClosed) emit(active);
  }

  /// Shows the system role dialog. Returns false when the user must use the
  /// system settings instead.
  Future<bool> request() async {
    final granted = await _bridge.requestDefaultBrowser();
    await refresh();
    return granted;
  }

  Future<void> openSettings() => _bridge.openDefaultAppsSettings();
}

class SettingsState {
  const SettingsState({
    this.browsers = const [],
    this.browserPackage,
    this.version = '',
  });

  final List<BrowserInfo> browsers;

  /// Explicit choice; null means automatic.
  final String? browserPackage;
  final String version;
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._settings, this._bridge)
      : super(SettingsState(browserPackage: _settings.browserPackage)) {
    load();
  }

  final SettingsRepository _settings;
  final NativeBridge _bridge;

  Future<void> load() async {
    final browsers = await _bridge.listBrowsers();
    final info = await PackageInfo.fromPlatform();
    if (isClosed) return;
    emit(SettingsState(
      browsers: browsers,
      browserPackage: _settings.browserPackage,
      version: '${info.version} (${info.buildNumber})',
    ));
  }

  Future<void> setBrowser(String? package) async {
    await _settings.setBrowserPackage(package);
    if (isClosed) return;
    emit(SettingsState(
      browsers: state.browsers,
      browserPackage: package,
      version: state.version,
    ));
  }

  Future<void> openUrl(String url) async {
    final browser = chooseBrowser(state.browsers, _settings.browserPackage);
    await _bridge.openUrl(url, package: browser?.package);
  }
}
