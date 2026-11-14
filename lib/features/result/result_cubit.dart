import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../checking/link_checker.dart';
import '../../checking/models.dart';
import '../../core/native_bridge.dart';
import '../../data/settings_repository.dart';

class ResultArgs {
  const ResultArgs({this.url, this.source = LinkSource.manual, this.historyEntry})
      : assert(url != null || historyEntry != null);

  final String? url;
  final LinkSource source;
  final CheckResult? historyEntry;
}

enum ResultStatus { checking, done, opened }

class ResultState {
  const ResultState({
    required this.status,
    this.result,
    this.fromHistory = false,
    this.counting = false,
    this.secondsLeft = 0,
    this.browserLabel,
    this.openFailed = false,
  });

  final ResultStatus status;
  final CheckResult? result;

  /// Showing a stored entry; no countdown, offers a re-check.
  final bool fromHistory;
  final bool counting;
  final int secondsLeft;
  final String? browserLabel;
  final bool openFailed;

  ResultState copyWith({
    ResultStatus? status,
    CheckResult? result,
    bool? fromHistory,
    bool? counting,
    int? secondsLeft,
    String? browserLabel,
    bool? openFailed,
  }) =>
      ResultState(
        status: status ?? this.status,
        result: result ?? this.result,
        fromHistory: fromHistory ?? this.fromHistory,
        counting: counting ?? this.counting,
        secondsLeft: secondsLeft ?? this.secondsLeft,
        browserLabel: browserLabel ?? this.browserLabel,
        openFailed: openFailed ?? this.openFailed,
      );
}

const countdownSeconds = 2;

class ResultCubit extends Cubit<ResultState> {
  ResultCubit({
    required ResultArgs args,
    required LinkChecker checker,
    required NativeBridge bridge,
    required SettingsRepository settings,
  })  : _args = args,
        _checker = checker,
        _bridge = bridge,
        _settings = settings,
        super(ResultState(
          status: args.historyEntry != null ? ResultStatus.done : ResultStatus.checking,
          result: args.historyEntry,
          fromHistory: args.historyEntry != null,
        )) {
    if (args.historyEntry == null) _run(args.url!, args.source);
  }

  final ResultArgs _args;
  final LinkChecker _checker;
  final NativeBridge _bridge;
  final SettingsRepository _settings;
  Timer? _timer;

  String get url => _args.url ?? _args.historyEntry!.url;

  /// Re-runs the check, as a manual check.
  Future<void> recheck() async {
    _cancelTimer();
    emit(const ResultState(status: ResultStatus.checking));
    await _run(url, LinkSource.manual);
  }

  Future<void> _run(String url, LinkSource recorded) async {
    final result = await _checker.check(url, recorded);
    if (isClosed) return;
    final browser = await _browser();
    if (isClosed) return;
    final isSafe = result.verdict == Verdict.safe;
    emit(ResultState(
      status: ResultStatus.done,
      result: result,
      counting: isSafe,
      secondsLeft: countdownSeconds,
      browserLabel: browser?.label,
    ));
    if (isSafe) _startCountdown();
  }

  /// Where the link came from; drives back navigation, even after a re-check.
  LinkSource get origin => _args.source;

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = state.secondsLeft - 1;
      if (left <= 0) {
        _cancelTimer();
        emit(state.copyWith(secondsLeft: 0));
        open();
      } else {
        emit(state.copyWith(secondsLeft: left));
      }
    });
  }

  void cancelCountdown() {
    _cancelTimer();
    emit(state.copyWith(counting: false));
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<BrowserInfo?> _browser() async =>
      chooseBrowser(await _bridge.listBrowsers(), _settings.browserPackage);

  /// Opens the checked link in the real browser.
  Future<void> open() => openExternal(state.result?.url ?? url);

  /// Opens [target] in the real browser; emits [ResultStatus.opened] on success.
  Future<void> openExternal(String target, {bool navigateAfter = true}) async {
    _cancelTimer();
    final browser = await _browser();
    final ok = await _bridge.openUrl(target, package: browser?.package);
    if (isClosed) return;
    if (!ok) {
      emit(state.copyWith(counting: false, openFailed: true));
      emit(state.copyWith(openFailed: false));
    } else if (navigateAfter) {
      emit(state.copyWith(status: ResultStatus.opened, counting: false));
    }
  }

  @override
  Future<void> close() {
    _cancelTimer();
    return super.close();
  }
}
