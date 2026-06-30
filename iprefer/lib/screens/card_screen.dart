import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../data/entry_store.dart';
import '../models/entry.dart';
import '../widgets/preference_card.dart';

/// Shows the rendered card. Primary action **Save** (records the entry),
/// secondary **Share** (system share of the exported PNG).
///
/// Reused in two modes:
///  - compose flow: pass [photo] + [text]; Save persists a new entry.
///  - archive view: pass an existing [entry]; Save is hidden, Share enabled.
class CardScreen extends StatefulWidget {
  const CardScreen({super.key, this.photo, this.text, this.entry})
      : assert(entry != null || (photo != null && text != null),
            'provide either an existing entry or a photo+text to compose');

  final File? photo;
  final String? text;
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
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
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
