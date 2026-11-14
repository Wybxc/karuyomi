import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'app_page_route.dart';
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

    Widget button(VoidCallback open) => CupertinoButton(
      focusNode: focus,
      padding: inline
          ? const EdgeInsets.symmetric(horizontal: 8)
          : EdgeInsets.zero,
      onPressed: onChanged == null || options.isEmpty ? null : open,
      child: inline
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$label：'),
                Flexible(
                  child: Text(
                    options[value] ?? '选择',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(CupertinoIcons.chevron_down, size: 14),
              ],
            )
          : CupertinoListTile(
              title: Text(
                label,
                maxLines: 2,
                style: TextStyle(color: AppColors.label.resolveFrom(context)),
              ),
              subtitle: Text(
                options[value] ?? '选择',
                maxLines: 3,
                style: TextStyle(
                  color: AppColors.secondaryLabel.resolveFrom(context),
                ),
              ),
              trailing: const CupertinoListTileChevron(),
            ),
    );

    return options.length <= 8
        ? CupertinoMenuAnchor(
            childFocusNode: focus,
            menuChildren: [
              for (final item in options.entries)
                CupertinoMenuItem(
                  onPressed:
                      onChanged == null || disabledValues.contains(item.key)
                      ? null
                      : () => select(item.key),
                  trailing: item.key == value
                      ? const Icon(CupertinoIcons.check_mark)
                      : null,
                  child: Text(item.value),
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
                        return CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: disabledValues.contains(item.key)
                              ? null
                              : () =>
                                    Navigator.of(context)
                                        .pop((value: item.key)),
                          child: CupertinoListTile(
                            title: Text(item.value),
                            trailing: item.key == value
                                ? const Icon(CupertinoIcons.check_mark)
                                : null,
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
