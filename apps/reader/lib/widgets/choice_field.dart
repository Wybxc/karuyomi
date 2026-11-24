import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'app_routes.dart';
import '../theme/app_theme.dart';

/// Small sets use a menu; Source and language catalogs need searchable choices.
class const ChoiceField<T>({
  super.key,
  required final String label,
  required final T? value,
  required final Map<T?, String> options,
  required final ValueChanged<T?>? onChanged,
  final Set<T?> disabledValues = const {},
  final bool inline = true,
  final bool showInlineLabel = true,

  /// Shows a compact button whose accessible name includes the current choice.
  final IconData? icon,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final focus = useFocusNode();
    final current = useRef(this)..value = this;
    void select(T? selected) {
      final latest = current.value;
      if (latest.options.containsKey(selected) &&
          !latest.disabledValues.contains(selected)) {
        latest.onChanged?.call(selected);
      }
    }

    final enabled = onChanged != null && options.isNotEmpty;
    final valueLabel = options[value] ?? '选择';
    final disabledStyle = enabled
        ? null
        : TextStyle(color: CupertinoColors.tertiaryLabel.resolveFrom(context));
    // Keep the tile style while allowing Source identities to wrap in full.
    Widget tileLabel(String text) => Builder(
      builder: (context) => DefaultTextStyle(
        style: DefaultTextStyle.of(context).style,
        child: Text(text, style: disabledStyle),
      ),
    );

    Widget button(VoidCallback open) => Semantics(
      enabled: enabled,
      child: CupertinoButton(
        focusNode: focus,
        padding: switch (icon) {
          final IconData _ => const EdgeInsets.all(8),
          null when inline => const EdgeInsets.symmetric(horizontal: 8),
          null => EdgeInsets.zero,
        },
        onPressed: enabled ? open : null,
        child: switch (icon) {
          final glyph? => Icon(glyph, semanticLabel: '$label： $valueLabel'),
          null when inline => Semantics(
            label: showInlineLabel ? null : '$label： $valueLabel',
            excludeSemantics: !showInlineLabel,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showInlineLabel) Text('$label：', style: disabledStyle),
                Flexible(
                  child: Text(
                    valueLabel,
                    style: disabledStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  CupertinoIcons.chevron_down,
                  size: 14,
                  color: disabledStyle?.color,
                ),
              ],
            ),
          ),
          null => CupertinoListTile(
            title: tileLabel(label),
            subtitle: tileLabel(valueLabel),
            trailing: const CupertinoListTileChevron(),
          ),
        },
      ),
    );

    final initialMenuValue =
        options.containsKey(value) && !disabledValues.contains(value)
        ? value
        : options.keys
              .where((item) => !disabledValues.contains(item))
              .firstOrNull;
    return options.length <= 8
        ? CupertinoMenuAnchor(
            childFocusNode: focus,
            menuChildren: [
              for (final item in options.entries)
                CupertinoMenuItem(
                  autofocus: item.key == initialMenuValue,
                  onPressed:
                      onChanged == null || disabledValues.contains(item.key)
                      ? null
                      : () => select(item.key),
                  trailing: item.key == value
                      ? const Icon(CupertinoIcons.check_mark)
                      : null,
                  child: Semantics(
                    selected: item.key == value,
                    inMutuallyExclusiveGroup: true,
                    child: Builder(
                      builder: (context) => DefaultTextStyle(
                        style: DefaultTextStyle.of(context).style,
                        child: Text(item.value),
                      ),
                    ),
                  ),
                ),
            ],
            builder: (context, menu, child) =>
                button(() => menu.isOpen ? menu.close() : menu.open()),
          )
        : button(() async {
            final result = await Navigator.of(context).push<({T? value})>(
              AppPageRoute(
                builder: (_) => ChoicePage(
                  label: label,
                  value: value,
                  options: options,
                  disabledValues: disabledValues,
                ),
              ),
            );
            if (!context.mounted) return;
            focus.requestFocus();
            if (result != null) select(result.value);
          });
  }
}

class const ChoicePage<T>({
  super.key,
  required final String label,
  required final T? value,
  required final Map<T?, String> options,
  required final Set<T?> disabledValues,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final query = useTextEditingController();
    useListenable(query);
    final search = query.text.trim().toLowerCase();
    final visible = options.entries
        .where((item) => item.value.toLowerCase().contains(search))
        .toList();
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(label)),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: CupertinoTextField(
                autofillHints: null,
                controller: query,
                placeholder: '查找$label',
                placeholderStyle: TextStyle(
                  color: AppColors.secondaryLabel.resolveFrom(context),
                ),
                textInputAction: TextInputAction.search,
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    CupertinoIcons.search,
                    color: AppColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                clearButtonMode: OverlayVisibilityMode.editing,
                clearButtonSemanticLabel: '清空选项搜索',
                decoration: BoxDecoration(
                  color: AppColors.groupedSurface.resolveFrom(context),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('没有匹配的选项'))
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        return Semantics(
                          selected: item.key == value,
                          enabled: !disabledValues.contains(item.key),
                          blockUserActions: disabledValues.contains(item.key),
                          inMutuallyExclusiveGroup: true,
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: disabledValues.contains(item.key)
                                ? null
                                : () =>
                                      Navigator.of(context)
                                          .pop((value: item.key)),
                            child: CupertinoListTile(
                              title: Builder(
                                builder: (context) => DefaultTextStyle(
                                  style: DefaultTextStyle.of(context).style,
                                  child: Text(item.value),
                                ),
                              ),
                              trailing: item.key == value
                                  ? const Icon(CupertinoIcons.check_mark)
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
