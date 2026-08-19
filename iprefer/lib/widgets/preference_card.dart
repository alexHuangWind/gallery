import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:palette_generator/palette_generator.dart';

import '../theme.dart';

/// The card. First principle from the spec: **don't fight the photo.**
/// Full-bleed 9:16 image, a scrim pulled from the photo's own bottom tone, and
/// the signature lockup. No frames, no stickers, no outside colors.
///
/// Wrap the instance you intend to export with a [RepaintBoundary] keyed by
/// [boundaryKey], then call [capturePng] to get a PNG.
class PreferenceCard extends StatefulWidget {
  const PreferenceCard({
    super.key,
    required this.image,
    required this.text,
    required this.createdAt,
    this.placeLabel,
    this.boundaryKey,
    this.compact = false,
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

  @override
  State<PreferenceCard> createState() => _PreferenceCardState();
}

class _PreferenceCardState extends State<PreferenceCard> {
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
    try {
      // `region` is expressed in the coordinate space of `size`, so we sample
      // the bottom third of a small 9:16 proxy — where the text will sit.
      const size = Size(120, 213);
      final palette = await PaletteGenerator.fromImageProvider(
        widget.image,
        size: size,
        region: const Rect.fromLTRB(0, 142, 120, 213),
        maximumColorCount: 8,
      );
      final source = palette.dominantColor?.color ??
          palette.darkMutedColor?.color ??
          const Color(0xFF101010);

      // Drop the value (and ease the saturation) so the scrim reads as a deep
      // tone of the photo — never pure black, never a loud color.
      final hsv = HSVColor.fromColor(source);
      final scrim = hsv
          .withValue((hsv.value * 0.35).clamp(0.0, 0.32))
          .withSaturation((hsv.saturation * 0.7).clamp(0.0, 0.6))
          .toColor();
      if (!mounted || request != _scrimRequest) return; // a newer photo won
      setState(() => _scrim = scrim.withOpacity(0.92));
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
              image: widget.image,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: Color(0xFFEDEAE3),
                child: Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      size: 26, color: AppTheme.muted),
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
                      colors: [_scrim.withOpacity(0), _scrim],
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

    if (widget.boundaryKey != null) {
      return RepaintBoundary(key: widget.boundaryKey, child: card);
    }
    return card;
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
    final date = DateFormat('MMM d, yyyy').format(createdAt).toLowerCase();
    final place = placeLabel?.trim();
    if (place == null || place.isEmpty) return date;
    return '$date · $place';
  }

  @override
  Widget build(BuildContext context) {
    final shadows = <Shadow>[
      Shadow(color: Colors.black.withOpacity(0.45), blurRadius: 8, offset: const Offset(0, 1)),
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
            color: Colors.white.withOpacity(0.8),
            shadows: shadows,
          ),
        ),
        SizedBox(height: compact ? 2 : 6),
        // The user's words: larger serif white.
        Text(
          text,
          maxLines: compact ? 3 : 6,
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
                  color: Colors.white.withOpacity(0.7),
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
                color: Colors.white.withOpacity(0.45),
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
