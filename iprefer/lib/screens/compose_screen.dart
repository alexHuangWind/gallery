import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/location_service.dart';
import '../theme.dart';
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
        setState(() => _photo = File(picked.path));
        // Only now do we ask for location: the user has committed to recording
        // something, so the permission prompt has an obvious reason attached.
        _locate();
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

  void _makeCard() {
    final text = _controller.text.trim();
    if (_photo == null || text.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardScreen(photo: _photo!, text: text, fix: _fix),
      ),
    );
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
                  onRetry: _locate,
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
                      color: AppTheme.ink.withOpacity(0.85),
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
              const SizedBox(height: 28),
              FilledButton(
                onPressed: canMake ? _makeCard : null,
                child: const Text('make card'),
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
    final muted = TextStyle(color: AppTheme.muted, fontSize: 13);

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
            const Icon(Icons.place_outlined, size: 16, color: AppTheme.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label, style: muted, overflow: TextOverflow.ellipsis),
            ),
            TextButton(
              onPressed: onDrop,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('leave it off', style: TextStyle(fontSize: 12)),
            ),
          ],
        );

      case _FixState.dropped:
        return Row(
          children: [
            const Icon(Icons.place_outlined, size: 16, color: AppTheme.muted),
            const SizedBox(width: 6),
            Text('no place on this one', style: muted),
            const Spacer(),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('add it back', style: TextStyle(fontSize: 12)),
            ),
          ],
        );

      case _FixState.unavailable:
        return Row(
          children: [
            const Icon(Icons.place_outlined, size: 16, color: AppTheme.muted),
            const SizedBox(width: 6),
            Expanded(child: Text("couldn't get your location", style: muted)),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
            color: const Color(0xFFEDEAE3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.muted.withOpacity(0.3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: photo == null
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 40, color: AppTheme.muted),
                      SizedBox(height: 12),
                      Text('add a photo of something you like',
                          style: TextStyle(color: AppTheme.muted)),
                    ],
                  ),
                )
              : Image.file(photo!, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
