import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../checking/models.dart';
import '../../data/history_repository.dart';

class HistoryState {
  const HistoryState({this.loaded = false, this.items = const []});
  final bool loaded;
  final List<CheckResult> items;
}

class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit(this._repo) : super(const HistoryState()) {
    _sub = _repo.changes.listen((_) => _load());
    _load();
  }

  final HistoryRepository _repo;
  late final StreamSubscription<void> _sub;

  Future<void> _load() async {
    final items = await _repo.all();
    if (!isClosed) emit(HistoryState(loaded: true, items: items));
  }

  Future<void> clear() => _repo.clear();

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
