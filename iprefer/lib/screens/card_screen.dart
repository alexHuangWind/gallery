import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../data/entry_store.dart';
import '../data/location_service.dart';
import '../models/entry.dart';
import '../theme.dart';
import '../widgets/preference_card.dart';

/// Shows the rendered card. Primary action **Save** (records the entry),
/// secondary **Share** (system share of the exported PNG).
///
/// Reused in two modes:
///  - compose flow: pass [photo] + [text]; Save persists a new entry.
///  - archive view: pass an existing [entry]; Save is hidden, Share enabled.
class CardScreen extends StatefulWidget {
  const CardScreen({
    super.key,
    this.photo,
    this.text,
    this.fix,
    this.tags = const [],
    this.entry,
  }) : assert(entry != null || (photo != null && text != null),
            'provide either an existing entry or a photo+text to compose');

  final File? photo;
  final String? text;

  /// Where this was recorded, when composing. Null is fine — the entry saves
  /// without a place.
  final PlaceFix? fix;

  /// Tags chosen while composing. Ignored when [entry] is supplied.
  final List<String> tags;

  final Entry? entry;

  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen> {
  final _boundaryKey = GlobalKey();
  bool _saved = false;
  bool _busy = false;

  bool get _isExisting => widget.entry != null;

  String get _text => widget.entry?.text ?? widget.text!;
  DateTime get _createdAt => widget.entry?.createdAt ?? _composeDate;
  late final DateTime _composeDate = DateTime.now();

  String? get _placeLabel => widget.entry?.placeLabel ?? widget.fix?.label;

  List<String> get _tags => widget.entry?.tags ?? widget.tags;

  File get _imageFile =>
      widget.entry != null ? File(widget.entry!.localPath) : widget.photo!;

  Future<void> _save() async {
    if (_busy || _saved) return;
    setState(() => _busy = true);
    try {
      final id = const Uuid().v4();
      final storedPath = await EntryStore.persistPhoto(_imageFile.path, id);
      final entry = Entry(
        id: id,
        localPath: storedPath,
        text: _text,
        createdAt: _composeDate,
        latitude: widget.fix?.latitude,
        longitude: widget.fix?.longitude,
        placeLabel: widget.fix?.label,
        tags: normalizeTags(widget.tags),
      );
      await context.read<EntryStore>().add(entry);
      if (mounted) {
        setState(() => _saved = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('saved to your timeline')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("couldn't save — please try again")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await capturePng(_boundaryKey);
      final id = widget.entry?.id ?? 'preview';
      final file = await EntryStore.writeShareablePng(bytes, id);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("couldn't prepare the image to share")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = !_isExisting && !_saved;

    return Scaffold(
      appBar: AppBar(title: const Text('your card')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: PreferenceCard(
                    boundaryKey: _boundaryKey,
                    image: FileImage(_imageFile),
                    text: _text,
                    createdAt: _createdAt,
                    placeLabel: _placeLabel,
                  ),
                ),
              ),
            ),
            if (_tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final tag in _tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.muted.withOpacity(0.35),
                          ),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.muted),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Row(
                children: [
                  if (canSave) ...[
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        child: const Text('save'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _share,
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('share'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
