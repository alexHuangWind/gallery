import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/location_service.dart';
import '../theme.dart';
import '../widgets/tag_input.dart';
import 'card_screen.dart';

/// Where the background location lookup has got to. Public only so a test can
/// name the states — every one of them is otherwise reachable exclusively
/// through a real photo pick.
enum FixState { idle, locating, found, unavailable, dropped }

/// Lets a test hold on to the photo well across a keystroke and check it was
/// not rebuilt — the well is the expensive part of this screen and the whole
/// point of not rebuilding it.
@visibleForTesting
const Key photoWellKey = Key('compose-photo-well');

/// Step one of the recording habit: a photo, a line, and — quietly, in the
/// background — where you are.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key})
      : initialPhoto = null,
        initialFixState = FixState.idle,
        initialFix = null;

  /// Starts the screen in a state that only a photo pick can otherwise
  /// produce. A pick goes out to the platform picker and then to the location
  /// stack, neither of which exists under `flutter test`, so without this seam
  /// the photo well, the place row and an enabled "make card" are all
  /// unreachable in a widget test.
  @visibleForTesting
  const ComposeScreen.seeded({
    super.key,
    this.initialPhoto,
    this.initialFixState = FixState.idle,
    this.initialFix,
  });

  @visibleForTesting
  final File? initialPhoto;
  @visibleForTesting
  final FixState initialFixState;
  @visibleForTesting
  final PlaceFix? initialFix;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _picker = ImagePicker();
  final _controller = TextEditingController();
  File? _photo;

  PlaceFix? _fix;
  FixState _fixState = FixState.idle;
  List<String> _tags = const [];

  /// The in-flight location lookup, so "make card" can give it a moment to
  /// land instead of silently saving a placeless entry.
  Future<void>? _locating;

  /// Guards the up-to-2s wait in [_makeCard]: without it a double-tap pushes
  /// two card screens — and because the fix can land between the taps, the
  /// two cards can even disagree about the place.
  bool _makingCard = false;

  @override
  void initState() {
    super.initState();
    _photo = widget.initialPhoto;
    _fix = widget.initialFix;
    _fixState = widget.initialFixState;
  }

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
          const SnackBar(
              content: Text("couldn't open that photo — try another")),
        );
      }
    }
  }

  Future<void> _locate() async {
    if (_fixState == FixState.locating) return;
    setState(() => _fixState = FixState.locating);
    final fix = await LocationService.current(prompt: true);
    if (!mounted) return;
    setState(() {
      _fix = fix;
      _fixState = fix == null ? FixState.unavailable : FixState.found;
    });
  }

  void _dropFix() {
    setState(() {
      _fix = null;
      _fixState = FixState.dropped;
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
      if (_fixState == FixState.locating && _locating != null) {
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
    return Scaffold(
      appBar: AppBar(title: const Text('new')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PhotoWell(key: photoWellKey, photo: _photo, onPick: _pick),
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
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.none,
                style:
                    const TextStyle(fontFamily: AppTheme.serif, fontSize: 20),
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
              // Only the button cares about the words, so only the button
              // listens. Reading _controller.text in build meant every
              // keystroke rebuilt the screen: the photo well re-inflating a
              // full-size decoded image, and TagInput re-reading the whole
              // archive's tag vocabulary out of the store.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  final canMake =
                      _photo != null && value.text.trim().isNotEmpty;
                  return FilledButton(
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
                                    strokeWidth: 1.6,
                                    color: context.colors.paper),
                              ),
                              const SizedBox(width: 8),
                              const Text('making your card'),
                            ],
                          )
                        : const Text('make card'),
                  );
                },
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

  final FixState state;
  final PlaceFix? fix;
  final VoidCallback onRetry;
  final VoidCallback onDrop;

  /// Visually small, but the hit area stays a real target: these buttons are
  /// the recovery path right after a location denial, the worst moment to
  /// demand precision. shrinkWrap would collapse the tappable box to the label.
  static final ButtonStyle _actionStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: const Size(48, 40),
  );

  /// Every branch is a leading glyph, a label and (usually) one action, so
  /// they share a shape. Laying them out one at a time is how the "no place on
  /// this one" row ended up with a bare Text and a Spacer, which overflows the
  /// moment the label is bigger than the room left beside the button.
  Widget _row(BuildContext context,
      {required Widget leading, required String label, Widget? action}) {
    return Row(
      children: [
        leading,
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: context.colors.muted, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (action != null) action,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pin =
        Icon(Icons.place_outlined, size: 16, color: context.colors.muted);

    switch (state) {
      case FixState.locating:
        return _row(
          context,
          leading: const Padding(
            // The pin the other branches use is 16 wide; matching it keeps the
            // label from stepping sideways when the fix lands.
            padding: EdgeInsets.symmetric(horizontal: 1.5),
            child: SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
          ),
          label: 'finding where you are',
        );

      case FixState.found:
        return _row(
          context,
          leading: pin,
          label: fix?.label ?? 'this spot',
          action: TextButton(
            onPressed: onDrop,
            style: _actionStyle,
            child: const Text('leave it off', style: TextStyle(fontSize: 12)),
          ),
        );

      case FixState.dropped:
        return _row(
          context,
          leading: pin,
          label: 'no place on this one',
          action: TextButton(
            onPressed: onRetry,
            style: _actionStyle,
            child: const Text('add it back', style: TextStyle(fontSize: 12)),
          ),
        );

      case FixState.unavailable:
        return _row(
          context,
          leading: pin,
          label: "couldn't get your location",
          action: TextButton(
            onPressed: onRetry,
            style: _actionStyle,
            child: const Text('try again', style: TextStyle(fontSize: 12)),
          ),
        );

      case FixState.idle:
        return const SizedBox.shrink();
    }
  }
}

class _PhotoWell extends StatelessWidget {
  const _PhotoWell({super.key, required this.photo, required this.onPick});

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
    // Merged rather than annotated: the role and the label live here, the tap
    // action lives on the GestureDetector below, and a screen reader needs
    // them on the same node to offer something it can activate.
    return MergeSemantics(
      child: Semantics(
        button: true,
        // The app's first action is an undecorated tap target. Without a role
        // a screen reader reads the placeholder sentence as prose and gives no
        // hint that the thing can be pressed at all.
        label: photo == null
            ? 'add a photo of something you like'
            : 'change the photo',
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: GestureDetector(
            onTap: () => _choose(context),
            // The placeholder sentence is already the label above; left in, it
            // would be read out a second time.
            child: ExcludeSemantics(
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.placeholder,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: context.colors.muted.withValues(alpha: 0.3)),
                ),
                clipBehavior: Clip.antiAlias,
                child: photo == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_a_photo_outlined,
                                size: 40, color: context.colors.muted),
                            const SizedBox(height: 12),
                            Text('add a photo of something you like',
                                style: TextStyle(color: context.colors.muted)),
                          ],
                        ),
                      )
                    : Image.file(
                        photo!,
                        fit: BoxFit.cover,
                        // The picker hands back up to 2000 px wide; the well
                        // is ~360 pt. Uncapped, a portrait pick sits in the
                        // image cache as tens of MB of RGBA — every other
                        // photo site in the app caps its decode near 3x its
                        // painted width.
                        cacheWidth: 1200,
                        // A file the platform decoder can't read would
                        // otherwise throw out of build. The well already
                        // paints colors.placeholder, so degrade to the same
                        // muted glyph the card and the timeline use.
                        errorBuilder: (context, _, __) => Center(
                          child: Icon(Icons.image_not_supported_outlined,
                              size: 40, color: context.colors.muted),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
