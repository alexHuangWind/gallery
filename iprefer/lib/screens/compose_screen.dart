import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';
import 'card_screen.dart';

/// Step one of the recording habit: a photo and a line.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _picker = ImagePicker();
  final _controller = TextEditingController();
  File? _photo;

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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("couldn't open that photo — try another")),
        );
      }
    }
  }

  void _makeCard() {
    final text = _controller.text.trim();
    if (_photo == null || text.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardScreen(photo: _photo!, text: text),
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
