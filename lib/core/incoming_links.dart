import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../checking/link_input.dart';
import '../checking/models.dart';
import '../features/result/result_cubit.dart';
import 'native_bridge.dart';

/// Routes links arriving from other apps (VIEW / SEND intents) to the result
/// screen. Native tags the text as `link:<text>` or `share:<text>`.
class IncomingLinks {
  IncomingLinks({
    required this.bridge,
    required this.router,
    required this.messengerKey,
  });

  final NativeBridge bridge;
  final GoRouter router;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  StreamSubscription<String>? _sub;

  Future<void> start() async {
    _sub = bridge.newLinks.listen(_handle);
    final initial = await bridge.getInitialLink();
    if (initial != null) _handle(initial);
  }

  void _handle(String tagged) {
    final split = tagged.indexOf(':');
    final tag = split < 0 ? '' : tagged.substring(0, split);
    final text = split < 0 ? tagged : tagged.substring(split + 1);
    final source = tag == 'share' ? LinkSource.share : LinkSource.link;

    final url = extractUrl(text);
    if (url != null) {
      router.push('/result', extra: ResultArgs(url: url, source: source));
    } else {
      router.go('/');
      messengerKey.currentState?.showSnackBar(SnackBar(content: Text('incoming.noLink'.tr())));
    }
  }

  void dispose() => _sub?.cancel();
}
