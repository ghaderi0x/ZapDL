import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/format.dart';
import '../../core/platform.dart';
import '../../core/theme/zap_colors.dart';
import '../../engine/errors.dart';
import '../../engine/file_utils.dart';
import '../../engine/parts.dart';
import '../../engine/probe.dart';
import '../../media/media_models.dart';
import '../../media/resolver.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/l10n_helpers.dart';
import '../../shared/widgets.dart';
import '../settings/settings_cubit.dart';
import 'downloads_cubit.dart';
import 'add_group.dart';
import 'url_history.dart';

class _RecentLinks extends StatelessWidget {
  const _RecentLinks({required this.urls, required this.title, required this.onPick});

  final List<String> urls;
  final String title;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final u in urls)
                ActionChip(
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Text(
                      u.replaceFirst(RegExp(r'^https?://'), ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onPressed: () => onPick(u),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens the add-download flow: a dialog on wide screens, a bottom sheet on
/// phones. The same form is used for typed URLs, pasted URLs and clipboard
/// suggestions, so validation and duplicate detection are always applied.
Future<void> showAddDownload(BuildContext context, {String? initialUrl}) {
  final wide = MediaQuery.sizeOf(context).width >= 640;
  final cubit = context.read<DownloadsCubit>();
  final settings = context.read<SettingsCubit>();
  Widget form() => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: cubit),
          BlocProvider.value(value: settings),
        ],
        child: AddDownloadForm(initialUrl: initialUrl),
      );
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: form(),
        ),
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

enum _Phase { idle, loading, ready, error }

class AddDownloadForm extends StatefulWidget {
  const AddDownloadForm({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  State<AddDownloadForm> createState() => _AddDownloadFormState();
}

class _AddDownloadFormState extends State<AddDownloadForm> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  _Phase _phase = _Phase.idle;
  ProbeResult? _probe;
  DownloadFailure? _failure;
  String? _dir;
  bool _adding = false;
  final _refererController = TextEditingController();
  final _cookiesController = TextEditingController();
  MediaInfo? _media;
  MediaFormat? _format;
  String? _mediaError;
  DateTime? _scheduledAt;
  bool _autoNext = false;

  @override
  void initState() {
    super.initState();
    _dir = context.read<SettingsCubit>().state.downloadDir;
    final initial = widget.initialUrl;
    if (initial != null) {
      _urlController.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _refererController.dispose();
    _cookiesController.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _urlController.text = text;
    await _check();
  }

  Map<String, String> get _extraHeaders {
    final ref = _refererController.text.trim();
    return {if (ref.isNotEmpty) 'Referer': ref};
  }

  String? get _cookieText {
    final c = _cookiesController.text.trim();
    return c.isEmpty ? null : c;
  }

  String _mediaFileName(MediaInfo info, MediaFormat f) =>
      sanitizeFileName('${info.title}.${f.extension}');

  Future<void> _check() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _phase = _Phase.loading;
      _failure = null;
      _mediaError = null;
      _media = null;
      _format = null;
      _probe = null;
    });
    final cubit = context.read<DownloadsCubit>();
    final uri = Uri.tryParse(url);

    // Web-page links (YouTube, Reddit, Telegram, ...) are resolved to files.
    if (uri != null && uri.hasScheme && MediaResolver.looksLikePage(uri)) {
      try {
        final info = await cubit.resolveMedia(url);
        if (!mounted) return;
        final f = info.recommended!;
        setState(() {
          _media = info;
          _format = f;
          _nameController.text = _mediaFileName(info, f);
          _phase = _Phase.ready;
        });
        return;
      } on MediaException catch (e) {
        if (!mounted) return;
        final platformLink = MediaResolver.isYouTube(uri) ||
            MediaResolver.isReddit(uri) ||
            MediaResolver.isTelegram(uri);
        if (platformLink) {
          setState(() {
            _mediaError = mediaErrorText(AppLocalizations.of(context), e);
            _phase = _Phase.error;
          });
          return;
        }
        // Not a media page: it may still be a direct file without an extension.
      }
    }

    try {
      final result = await cubit.probe(url, headers: _extraHeaders, cookies: _cookieText);
      if (!mounted) return;
      setState(() {
        _probe = result;
        _nameController.text = result.fileName;
        _phase = _Phase.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = DownloadFailure.from(e);
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    setState(() => _scheduledAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null && mounted) setState(() => _dir = dir);
  }

  Future<void> _add() async {
    final media = _media;
    final format = _format;
    if ((_probe == null && (media == null || format == null)) || _dir == null) return;
    final downloads = context.read<DownloadsCubit>();
    final history = context.read<UrlHistory>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final pageUrl = _urlController.text.trim();
    setState(() => _adding = true);
    try {
      if (media != null && format != null) {
        await downloads.add(
          url: format.url,
          directory: _dir!,
          fileName: _nameController.text,
          headers: {...format.headers, ..._extraHeaders},
          cookies: _cookieText,
          scheduledAt: _scheduledAt,
          sourcePage: media.sourcePage,
        );
      } else {
        await downloads.add(
          url: pageUrl,
          directory: _dir!,
          fileName: _nameController.text,
          probe: _probe,
          headers: _extraHeaders,
          cookies: _cookieText,
          scheduledAt: _scheduledAt,
          autoNext: _autoNext,
        );
      }
      await history.add(pageUrl);
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      final f = DownloadFailure.from(e);
      messenger.showSnackBar(SnackBar(content: Text(errorText(l, f.code, f.detail))));
    }
  }

  void _useRecent(String url) {
    _urlController.text = url;
    _check();
  }

  Widget _destinationRow(AppLocalizations l) => Row(children: [
        Expanded(
          child: Text(
            '${l.addSaveTo}: $_dir',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (isDesktopPlatform)
          TextButton(onPressed: _pickFolder, child: Text(l.actionChange)),
      ]);

  /// Optional request settings: referer, cookies and a delayed start.
  Widget _advanced(AppLocalizations l) {
    final locale = Localizations.localeOf(context).toString();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(l.addAdvanced, style: Theme.of(context).textTheme.titleSmall),
        children: [
          TextField(
            controller: _refererController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: l.addReferer),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cookiesController,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: l.addCookies,
              hintText: l.addCookiesHint,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.schedule_rounded,
                size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _scheduledAt == null
                    ? l.addScheduleNow
                    : l.addScheduleAt(formatDateTime(_scheduledAt!, locale)),
              ),
            ),
            if (_scheduledAt != null)
              IconButton(
                tooltip: l.addScheduleNow,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => _scheduledAt = null),
              ),
            TextButton(onPressed: _pickSchedule, child: Text(l.addSchedule)),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    final locale = Localizations.localeOf(context).toString();
    final cubit = context.read<DownloadsCubit>();
    final duplicate = _phase == _Phase.ready && cubit.isDuplicate(_urlController.text);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.addTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            autofocus: widget.initialUrl == null,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _check(),
            onChanged: (_) {
              if (_phase != _Phase.idle) setState(() => _phase = _Phase.idle);
            },
            decoration: InputDecoration(
              hintText: l.addUrlHint,
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: IconButton(
                tooltip: l.actionPaste,
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: _paste,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_phase == _Phase.idle && _urlController.text.isEmpty)
            _RecentLinks(
              urls: context.read<UrlHistory>().items.take(5).toList(),
              title: l.addRecent,
              onPick: _useRecent,
            ),
          if (_phase == _Phase.loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
              ),
            ),
          if (_phase == _Phase.error && (_failure != null || _mediaError != null))
            ZapCard(
              color: z.error.withValues(alpha: 0.10),
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.error_outline_rounded, color: z.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_mediaError ??
                      errorText(l, _failure!.code, _failure!.detail)),
                ),
              ]),
            ),
          if (_phase == _Phase.ready && _media != null && _format != null) ...[
            Text(_media!.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(l.addFromPage(_media!.platform),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            DropdownButtonFormField<MediaFormat>(
              initialValue: _format,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.addPickQuality),
              items: [
                for (final f in _media!.formats)
                  DropdownMenuItem(
                    value: f,
                    child: Text(
                      f.sizeBytes == null
                          ? f.label
                          : '${f.label} · ${formatBytes(f.sizeBytes!, locale)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (f) {
                if (f == null) return;
                setState(() {
                  _format = f;
                  _nameController.text = _mediaFileName(_media!, f);
                });
              },
            ),
            if (mediaNoteText(l, _format!.note) != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: z.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(mediaNoteText(l, _format!.note)!,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ]),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: l.addFileName),
            ),
            const SizedBox(height: 8),
            Text(l.mediaLegal, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            _destinationRow(l),
          ],
          if (_phase == _Phase.ready && _probe != null) ...[
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: l.addFileName),
            ),
            const SizedBox(height: 12),
            Row(children: [
              InfoChip(
                icon: Icons.straighten_rounded,
                label: '${l.addSize}: ${_probe!.totalBytes > 0 ? formatBytes(_probe!.totalBytes, locale) : l.addUnknownSize}',
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(
                _probe!.rangeSupported ? Icons.bolt_rounded : Icons.info_outline_rounded,
                size: 18,
                color: _probe!.rangeSupported ? z.success : z.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _probe!.rangeSupported ? l.addResumeYes : l.addResumeNo,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            _destinationRow(l),
            if (duplicate)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: z.warning),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l.addDuplicate)),
                ]),
              ),
          ],
          if (_phase == _Phase.ready && _media == null && looksLikePart(_urlController.text.trim()))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _autoNext,
                onChanged: (v) => setState(() => _autoNext = v),
                title: Text(l.addAutoNext),
                subtitle: Text(l.addAutoNextSuggest),
              ),
            ),
          if (_phase == _Phase.idle || _phase == _Phase.ready || _phase == _Phase.error)
            _advanced(l),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  final downloads = context.read<DownloadsCubit>();
                  final settings = context.read<SettingsCubit>();
                  final root = Navigator.of(context, rootNavigator: true).context;
                  Navigator.of(context).pop();
                  showAddGroup(root, downloads: downloads, settings: settings);
                },
                child: Text(l.addGroup),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.actionClose),
              ),
              const SizedBox(width: 8),
              if (_phase == _Phase.ready)
                FilledButton(
                  onPressed: _adding ? null : _add,
                  child: Text(duplicate ? l.actionAddAnyway : l.actionAdd),
                )
              else
                FilledButton(
                  onPressed: _phase == _Phase.loading ? null : _check,
                  child: Text(l.actionCheck),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
