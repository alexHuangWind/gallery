import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:palette_generator/palette_generator.dart';

import '../theme.dart';

/// How the scrim tone gets read off a photo. Returns null when the photo has
/// nothing to say — the card then keeps its neutral fallback scrim.
///
/// A seam, not an abstraction: the real implementation is
/// [samplePaletteScrim]. It exists so a test can hand the card a colour
/// synchronously instead of waiting out PaletteGenerator's own decode and
/// 15 s timeout for an image it already knows the answer for.
typedef ScrimSampler = Future<Color?> Function(ImageProvider image);

/// The card. First principle from the spec: **don't fight the photo.**
/// Full-bleed 9:16 image, a scrim pulled from the photo's own bottom tone, and
/// the signature lockup. No frames, no stickers, no outside colors.
///
/// Wrap the instance you intend to export with a [RepaintBoundary] keyed by
/// [boundaryKey], then call [capturePng] to get a PNG.
///
/// Type on the card is fixed and does not follow the phone's text scale — see
/// the note in [State.build]. Everything else in the app does.
class PreferenceCard extends StatefulWidget {
  const PreferenceCard({
    super.key,
    required this.image,
    required this.text,
    required this.createdAt,
    this.placeLabel,
    this.boundaryKey,
    this.compact = false,
    this.sampleScrim = samplePaletteScrim,
  });

  final ImageProvider image;

  /// The user's words (without the "I prefer" prefix).
  final String text;
  final DateTime createdAt;

  /// Where this was recorded. Joins the date line when present; the card
  /// gains no new type family for it.
  final String? placeLabel;

  /// If set, the card is wrapped in a [RepaintBoundary] for PNG export.
  final GlobalKey? boundaryKey;

  /// Smaller type scale for grid thumbnails.
  final bool compact;

  /// Where the scrim tone comes from. Only tests pass anything else.
  final ScrimSampler sampleScrim;

  @override
  State<PreferenceCard> createState() => _PreferenceCardState();
}

/// Scrim tones already worked out, newest use last.
///
/// Grid tiles are keyed by entry id, so scrolling one off the list and back on
/// destroys and recreates its State — and without this every one of those
/// round trips paid for another decode plus quantization of the same photo.
///
/// Capped, and deliberately holding nothing but a provider and a colour: at 64
/// entries there is no meaningful amount of anyone's archive sitting here after
/// a sign-out, and the cap evicts what there is as the next account scrolls.
final LinkedHashMap<ImageProvider, Color> _scrimCache =
    LinkedHashMap<ImageProvider, Color>();
const int _scrimCacheLimit = 64;

/// Least-recently-used, by re-inserting on read: [LinkedHashMap] keeps
/// insertion order, so the oldest key is always the first one.
Color? _cachedScrim(ImageProvider image) {
  final hit = _scrimCache.remove(image);
  if (hit != null) _scrimCache[image] = hit;
  return hit;
}

void _cacheScrim(ImageProvider image, Color scrim) {
  _scrimCache.remove(image);
  _scrimCache[image] = scrim;
  while (_scrimCache.length > _scrimCacheLimit) {
    _scrimCache.remove(_scrimCache.keys.first);
  }
}

/// Visible to tests only, so one test's cached tones can't decide another's.
@visibleForTesting
void clearScrimCache() => _scrimCache.clear();

/// The real sampler: quantize the bottom of the photo and take its dominant
/// tone.
///
/// `region` is expressed in the coordinate space of `size`, so we sample the
/// bottom third of a small 9:16 proxy — where the text will sit.
Future<Color?> samplePaletteScrim(ImageProvider image) async {
  const size = Size(120, 213);
  final palette = await PaletteGenerator.fromImageProvider(
    image,
    size: size,
    region: const Rect.fromLTRB(0, 142, 120, 213),
    maximumColorCount: 8,
  );
  return palette.dominantColor?.color ??
      palette.darkMutedColor?.color ??
      const Color(0xFF101010);
}

/// The scrim the spec asks for, from a tone sampled out of the photo: drop the
/// value (and ease the saturation) so it reads as a deep tone *of that photo* —
/// never a loud color, and never the generic black bar the spec rules out.
///
/// Pure on purpose. This is the whole of the card's colour promise, so it is
/// worth being able to assert on it without rendering anything.
Color scrimFrom(Color source) {
  final hsv = HSVColor.fromColor(source);
  return hsv
      .withValue((hsv.value * 0.35).clamp(0.0, 0.32))
      .withSaturation((hsv.saturation * 0.7).clamp(0.0, 0.6))
      .toColor()
      .withValues(alpha: 0.92);
}

class _PreferenceCardState extends State<PreferenceCard> {
  /// What actually gets decoded and painted.
  ///
  /// Compact cards (grid tiles) cap the decode at 600 px wide — a 2-column
  /// tile paints ~192 logical pt, so 600 covers a 3x display exactly. A
  /// 2000 px photo
  /// otherwise decodes to ~20 MB of RGBA *per tile*, blowing through the image
  /// cache after a handful of entries and re-decoding on every scroll. The
  /// SAME resized provider must feed the palette call below — its `size:`
  /// parameter scales the paint, not the decode, so passing the raw provider
  /// there would do the full decode this exists to avoid. The full-size card
  /// (and therefore the export boundary) keeps the raw provider untouched.
  ///
  /// Derived per use rather than stored: [didUpdateWidget] compares the *base*
  /// provider (FileImage has value equality; an inline ResizeImage does not),
  /// and the image cache keys on ResizeImage's equatable key, so re-creating
  /// the wrapper never causes a second decode.
  ImageProvider get _paintImage => widget.compact
      ? ResizeImage(widget.image, width: 600)
      : widget.image;

  /// Dark tone sampled from the bottom of the photo (value dropped in HSV).
  Color _scrim = const Color(0xCC101010);

  /// Guards against a slower extraction for a previous photo landing last and
  /// painting its scrim onto this card. Grid tiles are recycled by index, so
  /// scrolling or re-sorting starts several extractions on the same State.
  int _scrimRequest = 0;

  @override
  void initState() {
    super.initState();
    _extractScrim();
  }

  @override
  void didUpdateWidget(PreferenceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _extractScrim();
    }
  }

  Future<void> _extractScrim() async {
    final request = ++_scrimRequest;
    final image = _paintImage;

    // Before any await, so a cached tone is already on the field by the time
    // the build that follows initState / didUpdateWidget runs — a scrolled-back
    // tile paints its real scrim on its first frame rather than flashing the
    // neutral fallback. A plain assignment rather than setState for the same
    // reason: both callers are immediately followed by a build.
    final cached = _cachedScrim(image);
    if (cached != null) {
      _scrim = cached;
      return;
    }

    try {
      final source = await widget.sampleScrim(image);
      if (source == null) return; // nothing to pull from; keep the fallback
      final scrim = scrimFrom(source);
      // Cache before the guards: the tone is right for this photo whether or
      // not this particular State still wants it.
      _cacheScrim(image, scrim);
      if (!mounted || request != _scrimRequest) return; // a newer photo won
      setState(() => _scrim = scrim);
    } catch (_) {
      // Keep the neutral fallback scrim; a failed sample must not break the card.
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.compact ? 10 : 16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Full-bleed photo. An errorBuilder matters most here: this is the
            // widget that gets exported, and a missing file would otherwise
            // throw on every rebuild instead of degrading to a placeholder.
            Image(
              image: _paintImage,
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => ColoredBox(
                color: context.colors.placeholder,
                child: Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      size: 26, color: context.colors.muted),
                ),
              ),
            ),

            // Bottom scrim: transparent → photo's own dark tone.
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: 0.55,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_scrim.withValues(alpha: 0), _scrim],
                      stops: const [0.0, 0.85],
                    ),
                  ),
                ),
              ),
            ),

            // The lockup.
            Positioned(
              left: widget.compact ? 12 : 22,
              right: widget.compact ? 12 : 22,
              bottom: widget.compact ? 12 : 26,
              child: _Lockup(
                text: widget.text,
                createdAt: widget.createdAt,
                placeLabel: widget.placeLabel,
                compact: widget.compact,
              ),
            ),
          ],
        ),
      ),
    );

    // The card ignores the phone's text scale — every size in the lockup is
    // fixed. [capturePng] exports exactly what is painted, so with
    // accessibility type at 2x the lockup would swallow the photo and clip off
    // the top of the tile, and two phones would produce different PNGs from
    // the same entry. This is the same argument that exempts this file from
    // the palette rule (see test/palette_discipline_test.dart): what the card
    // promises is one artifact, not a rendering of the sender's settings.
    //
    // The compact tile does not scale either, even though it is on-screen UI.
    // It is a preview of that artifact — a tile whose type ran at 2x while the
    // card it opens does not would be lying about what tapping it gives you —
    // and its shadow is sized for exactly this type. The words are never
    // trapped: the tile caps at two lines and a tap opens the full text.
    final fixedType = MediaQuery.withNoTextScaling(child: card);

    if (widget.boundaryKey != null) {
      return RepaintBoundary(key: widget.boundaryKey, child: fixedType);
    }
    return fixedType;
  }
}

class _Lockup extends StatelessWidget {
  const _Lockup({
    required this.text,
    required this.createdAt,
    required this.placeLabel,
    required this.compact,
  });

  final String text;
  final DateTime createdAt;
  final String? placeLabel;
  final bool compact;

  String _stamp() {
    final date = quietDate(createdAt);
    final place = placeLabel?.trim();
    if (place == null || place.isEmpty) return date;
    return '$date · $place';
  }

  @override
  Widget build(BuildContext context) {
    final shadows = <Shadow>[
      Shadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(0, 1)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Signature: serif italic, ~80% white.
        Text(
          'I prefer',
          style: TextStyle(
            fontFamily: AppTheme.serif,
            fontStyle: FontStyle.italic,
            fontSize: compact ? 13 : 19,
            color: Colors.white.withValues(alpha: 0.8),
            shadows: shadows,
          ),
        ),
        SizedBox(height: compact ? 2 : 6),
        // The user's words: larger serif white. Compact tiles cap at 2 lines:
        // the lockup grows upward from the bottom, so a third line eats
        // visibly more photo on some tiles than others and breaks the grid's
        // rhythm. Tapping opens the full card; nothing is lost.
        Text(
          text,
          maxLines: compact ? 2 : 6,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTheme.serif,
            fontSize: compact ? 17 : 27,
            height: 1.2,
            color: Colors.white,
            shadows: shadows,
          ),
        ),
        SizedBox(height: compact ? 6 : 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Date (and place, when we have one) in a plain sans — the only
            // non-serif type on the card. Kept to a single quiet line.
            Flexible(
              child: Text(
                _stamp(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 9 : 11,
                  letterSpacing: 0.4,
                  color: Colors.white.withValues(alpha: 0.7),
                  shadows: shadows,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Tiny low-opacity wordmark.
            Text(
              'iprefer',
              style: TextStyle(
                fontFamily: AppTheme.serif,
                fontStyle: FontStyle.italic,
                fontSize: compact ? 9 : 12,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Renders the [RepaintBoundary] behind [boundaryKey] to PNG bytes.
///
/// [pixelRatio] of 3 gives a crisp, Story-ready export from the on-screen card.
Future<Uint8List> capturePng(GlobalKey boundaryKey, {double pixelRatio = 3}) async {
  // Let any in-flight scrim/photo frame settle first: toImage() captures what
  // is painted at this instant, and in debug it asserts the boundary is clean.
  await WidgetsBinding.instance.endOfFrame;

  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError('the card is no longer on screen');
  }

  final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('could not encode the card');
    }
    return byteData.buffer.asUint8List();
  } finally {
    // ~8 MB of native memory per share at pixelRatio 3 if this is skipped.
    image.dispose();
  }
}
