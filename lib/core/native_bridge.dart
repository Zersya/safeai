import 'dart:async';

import 'package:flutter/services.dart';

import '../checking/link_checker.dart';

class BrowserInfo {
  const BrowserInfo({required this.package, required this.label});
  final String package;
  final String label;
}

/// Typed wrapper over the `id.safeai.app/native` MethodChannel.
///
/// All intents go through here (never `url_launcher`): once safeAI is the
/// default browser, a generic launcher would loop back into this app.
class NativeBridge implements HostConverter {
  NativeBridge() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNewLink' && call.arguments is String) {
        _newLinks.add(call.arguments as String);
      }
      return null;
    });
  }

  static const _channel = MethodChannel('id.safeai.app/native');
  final _newLinks = StreamController<String>.broadcast();

  /// Tagged text (`link:<url>` / `share:<text>`) delivered while running.
  Stream<String> get newLinks => _newLinks.stream;

  /// Tagged text from the launch intent; returned once.
  Future<String?> getInitialLink() => _channel.invokeMethod<String>('getInitialLink');

  Future<List<BrowserInfo>> listBrowsers() async {
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('listBrowsers');
    return [
      for (final m in raw ?? const <Map<Object?, Object?>>[])
        BrowserInfo(package: m['package'] as String, label: m['label'] as String),
    ];
  }

  Future<bool> openUrl(String url, {String? package}) async =>
      await _channel.invokeMethod<bool>('openUrl', {'url': url, 'package': package}) ?? false;

  Future<bool> isDefaultBrowser() async =>
      await _channel.invokeMethod<bool>('isDefaultBrowser') ?? false;

  Future<bool> requestDefaultBrowser() async =>
      await _channel.invokeMethod<bool>('requestDefaultBrowser') ?? false;

  Future<bool> openDefaultAppsSettings() async =>
      await _channel.invokeMethod<bool>('openDefaultAppsSettings') ?? false;

  @override
  Future<String?> toAsciiHost(String host) =>
      _channel.invokeMethod<String>('toAsciiHost', {'host': host});

  Future<void> moveToBack() => _channel.invokeMethod<void>('moveToBack');
}
