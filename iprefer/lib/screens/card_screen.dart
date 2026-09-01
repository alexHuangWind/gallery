import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

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

  File get _imageFile => widget.entry != null
      ? context.read<EntryStore>().fileFor(widget.entry!)
      : widget.photo!;

  /// Share stays disabled until the photo has actually decoded. toImage()
  /// captures whatever is painted right now, so sharing early exports a card
  /// with the lockup floating over nothing.
  bool _imageReady = false;

  /// The decode failed (dangling legacy path, unreadable file). The gate must
  /// stay closed: precacheImage's future completes on error too, so without
  /// this flag a *broken* photo would enable Share and export the placeholder.
  bool _imageBroken = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_imageReady || _imageBroken) return;
    precacheImage(
      FileImage(_imageFile),
      context,
      onError: (_, __) => _imageBroken = true,
    ).whenComplete(() {
      if (mounted && !_imageBroken) setState(() => _imageReady = true);
    });
  }

  Future<void> _save() async {
    if (_busy || _saved) return;
    setState(() => _busy = true);

    // Captured before the first await. Copying the photo is a platform round
    // trip plus a file copy; if the user taps back during it, reading these
    // from a deactivated context throws, the error is swallowed, and the entry
    // is lost with no message — after the photo was already written to disk.
    final store = context.read<EntryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      // The photo-copy + record-write transaction, including its rollback,
      // lives in the store — nothing here can damage a saved entry.
      await store.create(
        sourcePhotoPath: widget.photo!.path,
        text: _text,
        createdAt: _composeDate,
        latitude: widget.fix?.latitude,
        longitude: widget.fix?.longitude,
        placeLabel: widget.fix?.label,
        tags: widget.tags,
      );
      _saved = true;
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text("couldn't save — please try again")),
      );
      if (mounted) setState(() => _busy = false);
      return;
    }
    // On success _busy deliberately stays true: this screen is about to pop,
    // and re-enabling the row first flashes a one-frame button re-layout.

    messenger.showSnackBar(
      const SnackBar(content: Text('saved to your timeline')),
    );
    // Back to the timeline. Without this the user is left on a saved card
    // whose back button returns to a compose screen still holding the photo
    // and text — tapping through again silently saves a duplicate.
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);

    final messenger = ScaffoldMessenger.of(context);
    // iPad presents the share sheet as a popover and UIKit raises a *native*
    // exception when it has no anchor rect — which no Dart catch can intercept.
    final box = context.findRenderObject() as RenderBox?;

    try {
      final bytes = await capturePng(_boundaryKey);
      final id = widget.entry?.id ?? 'preview';
      final file = await EntryStore.writeShareablePng(bytes, id);
      await Share.shareXFiles(
        [XFile(file.path)],
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text("couldn't prepare the image to share")),
      );
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
                            color: context.colors.muted.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                              fontSize: 12, color: context.colors.muted),
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
                        // Stays live while it works. A disabled M3 button
                        // drops the theme's ink fill for onSurface@0.12, which
                        // puts the paper spinner at ~1.3:1 on its own button —
                        // the payoff moment would show a blank grey slab. The
                        // re-entry guard lives in _save itself. Height matches
                        // the plain label, so nothing reflows.
                        onPressed: _save,
                        child: _busy
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.6,
                                        color: context.colors.paper),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('saving'),
                                ],
                              )
                            : const Text('save'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_busy || !_imageReady) ? null : _share,
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
