import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../checking/models.dart';
import '../../core/theme.dart';
import '../result/result_cubit.dart';
import 'history_cubit.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  Future<void> _confirmClear(BuildContext context) async {
    final cubit = context.read<HistoryCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('history.clearTitle'.tr()),
        content: Text('history.clearBody'.tr(), style: Theme.of(ctx).textTheme.bodyLarge),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 56)),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 56),
              foregroundColor: VerdictStyle.of(Verdict.dangerous).color,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('history.clearAll'.tr()),
          ),
        ],
      ),
    );
    if (ok == true) await cubit.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HistoryCubit>().state;
    final theme = Theme.of(context);
    final format = DateFormat.yMMMd(context.locale.toString()).add_Hm();
    return Scaffold(
      appBar: AppBar(
        title: Text('history.title'.tr()),
        actions: [
          if (state.items.isNotEmpty)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => _confirmClear(context),
              child: Text('history.clearAll'.tr(), style: const TextStyle(fontSize: 18)),
            ),
        ],
      ),
      body: !state.loaded
          ? const SizedBox.shrink()
          : state.items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'history.empty'.tr(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: state.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = state.items[i];
                    final style = VerdictStyle.of(item.verdict);
                    final uri = Uri.tryParse(item.url);
                    final host = (uri == null || uri.host.isEmpty) ? item.url : uri.host;
                    return ListTile(
                      minVerticalPadding: 12,
                      leading: Icon(style.icon, color: style.color, size: 40),
                      title: Text(
                        host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(
                            '${'common.verdict.${item.verdict.name}'.tr()} · ${format.format(item.checkedAt)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: style.color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => context.push('/result', extra: ResultArgs(historyEntry: item)),
                    );
                  },
                ),
    );
  }
}
