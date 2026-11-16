import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/platform.dart';
import '../../engine/parts.dart';
import '../../engine/probe.dart';
import '../../l10n/gen/app_localizations.dart';
import '../settings/settings_cubit.dart';
import 'downloads_cubit.dart';

/// Opens the "group of links" form: several links that download one at a
/// time, in the order they are listed (multi-part games, split archives).
Future<void> showAddGroup(
  BuildContext context, {
  required DownloadsCubit downloads,
  required SettingsCubit settings,
  String? initialText,
}) {
  final wide = MediaQuery.sizeOf(context).width >= 640;
  Widget form() => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: downloads),
          BlocProvider.value(value: settings),
        ],
        child: AddGroupForm(initialText: initialText),
      );
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: form()),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: form(),
    ),
  );
}

class AddGroupForm extends StatefulWidget {
  const AddGroupForm({super.key, this.initialText});

  final String? initialText;

  @override
  State<AddGroupForm> createState() => _AddGroupFormState();
}

class _AddGroupFormState extends State<AddGroupForm> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initialText ?? '');
  String? _dir;
  bool _autoNext = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _dir = context.read<SettingsCubit>().state.downloadDir;
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  List<String> get _links => [
        for (final line in _text.text.split(RegExp(r'[\r\n]+')))
          if (looksLikeDownloadUrl(line)) line.trim(),
      ];

  Future<void> _pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null && mounted) setState(() => _dir = dir);
  }

  Future<void> _add() async {
    final links = _links;
    if (links.isEmpty || _dir == null) return;
    final cubit = context.read<DownloadsCubit>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    final r = await cubit.addGroup(links, _dir!, autoNext: _autoNext);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(r.failed == 0
          ? l.bulkAdded(r.added)
          : '${l.bulkAdded(r.added)} · ${l.bulkFailed(r.failed)}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final links = _links;
    final looksPart = links.isNotEmpty && looksLikePart(links.last);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.addGroup, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(l.addGroupOrderInfo, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 5,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(hintText: l.addGroupHint),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _autoNext,
            onChanged: (v) => setState(() => _autoNext = v),
            title: Text(l.addAutoNext),
            subtitle: Text(looksPart ? l.addAutoNextSuggest : l.addAutoNextHelp),
          ),
          Row(children: [
            Expanded(
              child: Text('${l.addSaveTo}: $_dir',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            if (isDesktopPlatform)
              TextButton(onPressed: _pickFolder, child: Text(l.actionChange)),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.actionClose)),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: (_busy || links.isEmpty) ? null : _add,
              child: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('${l.actionAdd} (${links.length})'),
            ),
          ]),
        ],
      ),
    );
  }
}
