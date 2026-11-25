import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../widgets/app_routes.dart';
import '../../widgets/edit_sheet.dart';
import '../extensions/extension_listing.dart';
import '../settings/reader_device_settings.dart';

final sourceLanguageFilterProvider =
    AsyncNotifierProvider<SourceLanguageFilter, SourceLanguageSelection>(
      SourceLanguageFilter.new,
    );

final class SourceLanguageSelection {
  const SourceLanguageSelection({
    this.languages = const {},
    this.saving = false,
    this.saveFailed = false,
  });

  final Set<String> languages;
  final bool saving;
  final bool saveFailed;
}

class SourceLanguageFilter extends AsyncNotifier<SourceLanguageSelection> {
  static const _key = 'browse_source_languages';

  @override
  Future<SourceLanguageSelection> build() async {
    final storage = ref.watch(readerDeviceStorageProvider);
    try {
      final text = await storage
          .getString(_key)
          .timeout(const Duration(seconds: 3));
      if (text == null) return const SourceLanguageSelection();
      if (jsonDecode(text) case final List<Object?> values) {
        return SourceLanguageSelection(
          languages: Set.unmodifiable(values.whereType<String>()),
        );
      }
    } catch (_) {
      // Browsing remains available without a saved device preference.
    }
    return const SourceLanguageSelection();
  }

  Future<void> save(Set<String> selection) async {
    final previous = state.value;
    if (state.isLoading ||
        previous == null ||
        previous.saving ||
        (!previous.saveFailed && setEquals(previous.languages, selection))) {
      return;
    }
    final next = Set<String>.unmodifiable(selection);
    state = AsyncData(SourceLanguageSelection(languages: next, saving: true));
    var saveFailed = false;
    try {
      final storage = ref.read(readerDeviceStorageProvider);
      await storage.setString(_key, jsonEncode(next.toList()..sort()));
    } catch (_) {
      saveFailed = true;
    } finally {
      if (ref.mounted) {
        state = AsyncData(
          SourceLanguageSelection(languages: next, saveFailed: saveFailed),
        );
      }
    }
  }
}

String browseLanguageLabel(String language) => switch (language) {
  'zh' => '中文',
  'zh-Hans' => '简体中文',
  'zh-Hant' => '繁體中文',
  'en' => '英语',
  'ja' => '日语',
  'ko' => '韩语',
  'all' => '多语言',
  _ => sourceLanguage(language),
};

Future<Set<String>?> chooseSourceLanguages(
  BuildContext context, {
  required List<String> languages,
  required Set<String> selected,
}) => showAppSheet<Set<String>>(
  context: context,
  enableDrag: false,
  scrollableBuilder: (context, scroll) => HookBuilder(
    builder: (context) {
      final draft = useState(selected);
      void toggle(String language) {
        final next = draft.value.toSet();
        if (!next.remove(language)) next.add(language);
        draft.value = next;
      }

      return EditSheet(
        title: const Text('筛选漫画源语言'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        trailing: CupertinoButton(
          key: const ValueKey('source-language-apply'),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context, draft.value),
          child: const Text('完成'),
        ),
        content: ListView(
          controller: scroll,
          children: [
            CupertinoListSection.insetGrouped(
              children: [
                Semantics(
                  selected: draft.value.isEmpty,
                  child: CupertinoListTile(
                    key: const ValueKey('source-language-all'),
                    title: const Text('全部语言'),
                    onTap: () => draft.value = const {},
                    trailing: draft.value.isEmpty
                        ? const Icon(CupertinoIcons.check_mark)
                        : null,
                  ),
                ),
                for (final language in languages)
                  MergeSemantics(
                    child: CupertinoListTile(
                      key: ValueKey(('source-language-option', language)),
                      title: Text(browseLanguageLabel(language)),
                      onTap: () => toggle(language),
                      trailing: CupertinoCheckbox(
                        value: draft.value.contains(language),
                        onChanged: (_) => toggle(language),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  ),
);
