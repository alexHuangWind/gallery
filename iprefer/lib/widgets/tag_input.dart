import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/entry_store.dart';
import '../models/entry.dart';
import '../theme.dart';

/// Tag editor for compose: what kind of thing is this?
///
/// Suggestions come from the tags the user has already used, most-used first,
/// so the vocabulary is theirs rather than ours. The seeds below only appear
/// while the archive is still empty — a first-run scaffold, not a taxonomy.
class TagInput extends StatefulWidget {
  const TagInput({super.key, required this.tags, required this.onChanged});

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  /// Shown only to a user who has no tags yet.
  static const seedSuggestions = <String>['grocery', 'wine', 'dish'];

  @override
  State<TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<TagInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _typing = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final next = normalizeTags([...widget.tags, raw]);
    _controller.clear();
    if (next.length != widget.tags.length) widget.onChanged(next);
    setState(() {});
  }

  void _remove(String tag) {
    widget.onChanged(widget.tags.where((t) => t != tag).toList());
  }

  @override
  Widget build(BuildContext context) {
    final used = context.watch<EntryStore>().tagsByUse;
    final pool = used.isEmpty ? TagInput.seedSuggestions : used;
    final suggestions =
        pool.where((t) => !widget.tags.contains(t)).take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'what kind of thing is it?',
          style: TextStyle(color: AppTheme.muted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final tag in widget.tags)
              _Chip(
                label: tag,
                selected: true,
                onTap: () => _remove(tag),
                trailing: Icons.close,
              ),
            if (_typing)
              SizedBox(
                width: 132,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.none,
                  style: const TextStyle(fontSize: 13),
                  // Commas and spaces are how people naturally separate tags.
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'[,\n]')),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'add a tag',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) {
                    _add(v);
                    // Keep the field open so several tags can be typed in a row.
                    _focus.requestFocus();
                  },
                  onTapOutside: (_) {
                    _add(_controller.text);
                    setState(() => _typing = false);
                    _focus.unfocus();
                  },
                ),
              )
            else
              _Chip(
                label: 'add',
                selected: false,
                dashed: true,
                onTap: () => setState(() => _typing = true),
                trailing: Icons.add,
              ),
          ],
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in suggestions)
                _Chip(label: s, selected: false, onTap: () => _add(s)),
            ],
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.dashed = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailing;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppTheme.paper : AppTheme.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppTheme.ink
                : AppTheme.muted.withOpacity(dashed ? 0.5 : 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: fg)),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              Icon(trailing, size: 13, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}
