import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/location_service.dart';
import '../theme.dart';
import '../widgets/tag_input.dart';
import 'card_screen.dart';

/// Step one of the recording habit: a photo, a line, and — quietly, in the
/// background — where you are.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

enum _FixState { idle, locating, found, unavailable, dropped }

class _ComposeScreenState extends State<ComposeScreen> {
  final _picker = ImagePicker();
  final _controller = TextEditingController();
  File? _photo;

  PlaceFix? _fix;
  _FixState _fixState = _FixState.idle;
  List<String> _tags = const [];

  /// The in-flight location lookup, so "make card" can give it a moment to
  /// land instead of silently saving a placeless entry.
  Future<void>? _locating;

  /// Guards the up-to-2s wait in [_makeCard]: without it a double-tap pushes
  /// two card screens — and because the fix can land between the taps, the
  /// two cards can even disagree about the place.
  bool _makingCard = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 90,
      );
      if (picked != null) {
        // pickImage hands control to another app for an unbounded time; the
        // route can be gone by the time it returns.
        if (!mounted) return;
        setState(() => _photo = File(picked.path));
        // Only now do we ask for location: the user has committed to recording
        // something, so the permission prompt has an obvious reason attached.
        _locating = _locate();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("couldn't open that photo — try another")),
        );
      }
    }
  }

  Future<void> _locate() async {
    if (_fixState == _FixState.locating) return;
    setState(() => _fixState = _FixState.locating);
    final fix = await LocationService.current(prompt: true);
    if (!mounted) return;
    setState(() {
      _fix = fix;
      _fixState = fix == null ? _FixState.unavailable : _FixState.found;
    });
  }

  void _dropFix() {
    setState(() {
      _fix = null;
      _fixState = _FixState.dropped;
    });
  }

  Future<void> _makeCard() async {
    final text = _controller.text.trim();
    if (_photo == null || text.isEmpty || _makingCard) return;
    setState(() => _makingCard = true);

    try {
      // A cold GPS plus a reverse geocode can outlast a fast typist. Without
      // this the entry is written placeless — no pin, no recall, invisible to
      // "nearest" — while the fix lands seconds later on a screen already
      // left. Bounded, because location must never block recording.
      if (_fixState == _FixState.locating && _locating != null) {
        await _locating!.timeout(const Duration(seconds: 2), onTimeout: () {});
      }
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              CardScreen(photo: _photo!, text: text, fix: _fix, tags: _tags),
        ),
      );
    } finally {
      // Re-arms when the card screen pops back to an unfinished compose.
      if (mounted) setState(() => _makingCard = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canMake = _photo != null && _controller.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('new')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PhotoWell(photo: _photo, onPick: _pick),
              if (_photo != null) ...[
                const SizedBox(height: 12),
                _PlaceRow(
                  state: _fixState,
                  fix: _fix,
                  onRetry: () => _locating = _locate(),
                  onDrop: _dropFix,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'I prefer',
                    style: TextStyle(
                      fontFamily: AppTheme.serif,
                      fontStyle: FontStyle.italic,
                      fontSize: 22,
                      color: context.colors.ink.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                onChanged: (_) => setState(() {}),
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.none,
                style: const TextStyle(fontFamily: AppTheme.serif, fontSize: 20),
                decoration: const InputDecoration(
                  hintText: 'ferns that uncurl like a slow question',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 22),
              TagInput(
                tags: _tags,
                onChanged: (t) => setState(() => _tags = t),
              ),
              const SizedBox(height: 28),
              FilledButton(
                // Not disabled while making: a disabled M3 button loses the
                // ink fill and the paper spinner vanishes into it. _makeCard
                // guards its own re-entry.
                onPressed: canMake ? _makeCard : null,
                child: _makingCard
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.6, color: context.colors.paper),
                          ),
                          const SizedBox(width: 8),
                          const Text('making your card'),
                        ],
                      )
                    : const Text('make card'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet one-liner about where this is being recorded. Never a blocker —
/// worst case it says the place is unknown and the entry saves anyway.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.state,
    required this.fix,
    required this.onRetry,
    required this.onDrop,
  });

  final _FixState state;
  final PlaceFix? fix;
  final VoidCallback onRetry;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.colors.muted, fontSize: 13);

    switch (state) {
      case _FixState.locating:
        return Row(
          children: [
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
            const SizedBox(width: 10),
            Text('finding where you are', style: muted),
          ],
        );

      case _FixState.found:
        final label = fix?.label ?? 'this spot';
        return Row(
          children: [
            Icon(Icons.place_outlined, size: 16, color: context.colors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label, style: muted, overflow: TextOverflow.ellipsis),
            ),
            TextButton(
              onPressed: onDrop,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                // Visually small, but the hit area stays a real target: these
                // buttons are the recovery path right after a location denial,
                // the worst moment to demand precision. shrinkWrap would
                // collapse the tappable box to the label.
                minimumSize: const Size(48, 40),
              ),
              child: const Text('leave it off', style: TextStyle(fontSize: 12)),
            ),
          ],
        );

      case _FixState.dropped:
        return Row(
          children: [
            Icon(Icons.place_outlined, size: 16, color: context.colors.muted),
            const SizedBox(width: 6),
            Text('no place on this one', style: muted),
            const Spacer(),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                // Visually small, but the hit area stays a real target: these
                // buttons are the recovery path right after a location denial,
                // the worst moment to demand precision. shrinkWrap would
                // collapse the tappable box to the label.
                minimumSize: const Size(48, 40),
              ),
              child: const Text('add it back', style: TextStyle(fontSize: 12)),
            ),
          ],
        );

      case _FixState.unavailable:
        return Row(
          children: [
            Icon(Icons.place_outlined, size: 16, color: context.colors.muted),
            const SizedBox(width: 6),
            Expanded(child: Text("couldn't get your location", style: muted)),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                // Visually small, but the hit area stays a real target: these
                // buttons are the recovery path right after a location denial,
                // the worst moment to demand precision. shrinkWrap would
                // collapse the tappable box to the label.
                minimumSize: const Size(48, 40),
              ),
              child: const Text('try again', style: TextStyle(fontSize: 12)),
            ),
          ],
        );

      case _FixState.idle:
        return const SizedBox.shrink();
    }
  }
}

class _PhotoWell extends StatelessWidget {
  const _PhotoWell({required this.photo, required this.onPick});

  final File? photo;
  final void Function(ImageSource) onPick;

  void _choose(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('take a photo'),
              onTap: () {
                Navigator.pop(context);
                onPick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('choose from library'),
              onTap: () {
                Navigator.pop(context);
                onPick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: GestureDetector(
        onTap: () => _choose(context),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.placeholder,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.muted.withValues(alpha: 0.3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: photo == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 40, color: context.colors.muted),
                      const SizedBox(height: 12),
                      Text('add a photo of something you like',
                          style: TextStyle(color: context.colors.muted)),
                    ],
                  ),
                )
              : Image.file(photo!, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
