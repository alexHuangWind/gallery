// Copyright 2024 The Flutter team. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

/// Draws the whole game world: the island, scenery, creatures and effects.
///
/// The HUD (bars, text, buttons) is rendered with regular widgets on top of
/// this painter, so everything here lives in world space and is offset by the
/// camera that follows the player.
class GamePainter extends CustomPainter {
  GamePainter({
    this.playerPos,
    this.playerStage,
    this.playerHealthFraction,
    this.playerFacingRight,
    this.playerWobble,
    this.invulnFlash,
    this.islandRadius,
    this.monsters,
    this.projectiles,
    this.particles,
    this.floatingTexts,
    this.decorations,
    this.time,
  });

  final Offset playerPos;
  final EvolutionStage playerStage;
  final double playerHealthFraction;
  final bool playerFacingRight;
  final double playerWobble;
  final double invulnFlash;
  final double islandRadius;
  final List<Monster> monsters;
  final List<Projectile> projectiles;
  final List<Particle> particles;
  final List<FloatingText> floatingTexts;
  final List<Decoration> decorations;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    // Camera keeps the player centred on screen.
    final Offset camera = playerPos - size.center(Offset.zero);

    // Ocean background.
    final Paint ocean = Paint()..color = const Color(0xFF1B6FA8);
    canvas.drawRect(Offset.zero & size, ocean);
    _drawOceanSparkle(canvas, size, camera);

    canvas.save();
    canvas.translate(-camera.dx, -camera.dy);

    _drawIsland(canvas);
    _drawDecorations(canvas);

    // Shadows first so creatures sit on top of them.
    _drawShadow(canvas, playerPos, playerStage.radius);
    for (final Monster m in monsters) {
      _drawShadow(canvas, m.position, m.radius);
    }

    for (final Monster m in monsters) {
      _drawCreature(
        canvas,
        m.position,
        m.radius,
        m.type.color,
        m.type.accent,
        m.type.form,
        m.facingRight,
        m.wobble,
      );
      _drawHealthBar(
        canvas,
        m.position,
        m.radius,
        m.healthFraction,
        const Color(0xFFE53935),
      );
    }

    // Player drawn last among creatures so it stays visible in a crowd.
    final bool flashing = invulnFlash > 0 && (invulnFlash * 20).floor().isEven;
    _drawCreature(
      canvas,
      playerPos,
      playerStage.radius,
      flashing ? Colors.white : playerStage.color,
      playerStage.accent,
      playerStage.form,
      playerFacingRight,
      playerWobble,
    );

    _drawProjectiles(canvas);
    _drawParticles(canvas);
    _drawFloatingTexts(canvas);

    canvas.restore();
  }

  void _drawOceanSparkle(Canvas canvas, Size size, Offset camera) {
    final Paint p = Paint()..color = Colors.white.withOpacity(0.06);
    for (int i = 0; i < 40; i++) {
      final double x = ((i * 137.0) - camera.dx * 0.3) % (size.width + 40) - 20;
      final double y =
          ((i * 211.0) - camera.dy * 0.3) % (size.height + 40) - 20;
      final double r = 2 + (math.sin(time * 2 + i) + 1) * 1.5;
      canvas.drawCircle(Offset(x, y), r, p);
    }
  }

  void _drawIsland(Canvas canvas) {
    // Sandy beach ring. The island is centred on the world origin (0, 0).
    canvas.drawCircle(
      Offset.zero,
      islandRadius + 26,
      Paint()..color = const Color(0xFFE9D8A6),
    );
    // Grass interior.
    canvas.drawCircle(
      Offset.zero,
      islandRadius,
      Paint()..color = const Color(0xFF4E944F),
    );
    // Darker grass patches for texture.
    final Paint patch = Paint()..color = const Color(0xFF3F7E41);
    final math.Random r = math.Random(7);
    for (int i = 0; i < 80; i++) {
      final Offset c = randomPointInCircle(r, Offset.zero, islandRadius - 30);
      canvas.drawCircle(c, 18 + r.nextDouble() * 40, patch);
    }
  }

  void _drawDecorations(Canvas canvas) {
    for (final Decoration d in decorations) {
      if (d.isRock) {
        final Paint rock = Paint()..color = const Color(0xFF9E9E9E);
        final Paint dark = Paint()..color = const Color(0xFF616161);
        canvas.drawCircle(
          d.position.translate(0, d.radius * 0.3),
          d.radius,
          dark,
        );
        canvas.drawCircle(d.position, d.radius * 0.85, rock);
      } else {
        // Bush / small tree.
        final Paint leaf = Paint()..color = const Color(0xFF2E7D32);
        final Paint leaf2 = Paint()..color = const Color(0xFF388E3C);
        canvas.drawCircle(
          d.position.translate(-d.radius * 0.5, 0),
          d.radius * 0.7,
          leaf,
        );
        canvas.drawCircle(
          d.position.translate(d.radius * 0.5, 0),
          d.radius * 0.7,
          leaf,
        );
        canvas.drawCircle(
          d.position.translate(0, -d.radius * 0.4),
          d.radius * 0.8,
          leaf2,
        );
      }
    }
  }

  void _drawShadow(Canvas canvas, Offset pos, double radius) {
    canvas.drawOval(
      Rect.fromCenter(
        center: pos.translate(0, radius * 0.75),
        width: radius * 2,
        height: radius * 0.8,
      ),
      Paint()..color = Colors.black.withOpacity(0.18),
    );
  }

  void _drawHealthBar(
    Canvas canvas,
    Offset pos,
    double radius,
    double frac,
    Color color,
  ) {
    if (frac >= 1.0) {
      return;
    }
    const double w = 40;
    const double h = 5;
    final Offset topLeft = pos.translate(-w / 2, -radius - 16);
    final Rect bg = topLeft & const Size(w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bg, const Radius.circular(2)),
      Paint()..color = Colors.black.withOpacity(0.45),
    );
    final Rect fill = topLeft & Size(w * frac, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fill, const Radius.circular(2)),
      Paint()..color = color,
    );
  }

  void _drawProjectiles(Canvas canvas) {
    for (final Projectile p in projectiles) {
      final Paint glow = Paint()
        ..color = p.color.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(p.position, p.radius * 1.8, glow);
      canvas.drawCircle(p.position, p.radius, Paint()..color = p.color);
      canvas.drawCircle(
        p.position,
        p.radius * 0.5,
        Paint()..color = Colors.white.withOpacity(0.8),
      );
    }
  }

  void _drawParticles(Canvas canvas) {
    for (final Particle p in particles) {
      final double a = (p.life / p.maxLife).clamp(0.0, 1.0).toDouble();
      canvas.drawCircle(
        p.position,
        p.radius * a,
        Paint()..color = p.color.withOpacity(a),
      );
    }
  }

  void _drawFloatingTexts(Canvas canvas) {
    for (final FloatingText t in floatingTexts) {
      final double a = (t.life / 0.9).clamp(0.0, 1.0).toDouble();
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            color: t.color.withOpacity(a),
            fontSize: t.size,
            fontWeight: FontWeight.bold,
            shadows: const <Shadow>[
              Shadow(color: Colors.black54, blurRadius: 2),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, t.position.translate(-tp.width / 2, -tp.height / 2));
    }
  }

  // ---- Creature drawing -----------------------------------------------------

  void _drawCreature(
    Canvas canvas,
    Offset pos,
    double radius,
    Color color,
    Color accent,
    CreatureForm form,
    bool facingRight,
    double wobble,
  ) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    if (!facingRight) {
      canvas.scale(-1, 1);
    }
    // A gentle squash-and-stretch breathing/bobbing motion.
    final double sx = 1 + math.sin(wobble) * 0.04;
    final double sy = 1 - math.sin(wobble) * 0.04;
    canvas.scale(sx, sy);

    final Paint body = Paint()..color = color;
    final Paint dark = Paint()..color = accent;

    switch (form) {
      case CreatureForm.slime:
        _slime(canvas, radius, body, dark);
        break;
      case CreatureForm.lizard:
        _lizard(canvas, radius, body, dark);
        break;
      case CreatureForm.wolf:
        _wolf(canvas, radius, body, dark);
        break;
      case CreatureForm.golem:
        _golem(canvas, radius, body, dark);
        break;
      case CreatureForm.wyvern:
        _wyvern(canvas, radius, body, dark, wobble);
        break;
      case CreatureForm.dragon:
        _dragon(canvas, radius, body, dark, wobble);
        break;
      case CreatureForm.beetle:
        _beetle(canvas, radius, body, dark);
        break;
      case CreatureForm.bat:
        _bat(canvas, radius, body, dark, wobble);
        break;
      case CreatureForm.boar:
        _boar(canvas, radius, body, dark);
        break;
      case CreatureForm.toad:
        _toad(canvas, radius, body, dark);
        break;
      case CreatureForm.flame:
        _flame(canvas, radius, body, dark, wobble);
        break;
    }
    canvas.restore();
  }

  void _eyes(Canvas canvas, double r, double dx, double dy, double size) {
    final Paint white = Paint()..color = Colors.white;
    final Paint black = Paint()..color = Colors.black87;
    canvas.drawCircle(Offset(dx, dy), size, white);
    canvas.drawCircle(Offset(dx + size * 0.3, dy), size * 0.55, black);
  }

  void _slime(Canvas canvas, double r, Paint body, Paint dark) {
    final Path p = Path();
    p.moveTo(-r, r * 0.6);
    p.quadraticBezierTo(-r * 1.1, -r * 0.9, 0, -r);
    p.quadraticBezierTo(r * 1.1, -r * 0.9, r, r * 0.6);
    p.quadraticBezierTo(r * 0.5, r, 0, r);
    p.quadraticBezierTo(-r * 0.5, r, -r, r * 0.6);
    p.close();
    canvas.drawPath(p, body);
    canvas.drawCircle(
      Offset(-r * 0.3, -r * 0.4),
      r * 0.2,
      Paint()..color = Colors.white.withOpacity(0.5),
    );
    _eyes(canvas, r, r * 0.25, -r * 0.1, r * 0.22);
    _eyes(canvas, r, -r * 0.35, -r * 0.1, r * 0.22);
  }

  void _lizard(Canvas canvas, double r, Paint body, Paint dark) {
    // Tail.
    final Path tail = Path()
      ..moveTo(-r * 0.6, 0)
      ..lineTo(-r * 1.7, -r * 0.25)
      ..lineTo(-r * 0.6, r * 0.4)
      ..close();
    canvas.drawPath(tail, dark);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 1.5),
      body,
    );
    // Head.
    canvas.drawCircle(Offset(r * 0.8, -r * 0.1), r * 0.55, body);
    // Spikes.
    for (int i = -1; i <= 1; i++) {
      final Path s = Path()
        ..moveTo(i * r * 0.45, -r * 0.7)
        ..lineTo(i * r * 0.45 - r * 0.12, -r * 0.95)
        ..lineTo(i * r * 0.45 + r * 0.12, -r * 0.95)
        ..close();
      canvas.drawPath(s, dark);
    }
    _eyes(canvas, r, r * 0.95, -r * 0.25, r * 0.18);
  }

  void _wolf(Canvas canvas, double r, Paint body, Paint dark) {
    // Tail.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 1.1, -r * 0.2),
        width: r * 0.9,
        height: r * 0.5,
      ),
      dark,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 2.1, height: r * 1.4),
      body,
    );
    // Head.
    canvas.drawCircle(Offset(r * 0.85, -r * 0.2), r * 0.6, body);
    // Ears.
    for (final double ex in <double>[0.55, 1.05]) {
      final Path ear = Path()
        ..moveTo(r * ex, -r * 0.6)
        ..lineTo(r * ex - r * 0.15, -r * 1.0)
        ..lineTo(r * ex + r * 0.2, -r * 0.65)
        ..close();
      canvas.drawPath(ear, dark);
    }
    // Snout.
    canvas.drawCircle(Offset(r * 1.25, -r * 0.1), r * 0.18, dark);
    _eyes(canvas, r, r * 1.0, -r * 0.35, r * 0.16);
  }

  void _golem(Canvas canvas, double r, Paint body, Paint dark) {
    final Path p = Path()
      ..moveTo(-r, -r * 0.4)
      ..lineTo(-r * 0.5, -r)
      ..lineTo(r * 0.6, -r * 0.9)
      ..lineTo(r, -r * 0.1)
      ..lineTo(r * 0.7, r)
      ..lineTo(-r * 0.6, r * 0.95)
      ..close();
    canvas.drawPath(p, body);
    // Cracks.
    final Paint crack = Paint()
      ..color = dark.color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(-r * 0.3, -r * 0.6),
      Offset(r * 0.1, r * 0.2),
      crack,
    );
    canvas.drawLine(Offset(r * 0.1, r * 0.2), Offset(r * 0.6, r * 0.1), crack);
    _eyes(canvas, r, r * 0.25, -r * 0.2, r * 0.16);
    _eyes(canvas, r, -r * 0.25, -r * 0.2, r * 0.16);
  }

  void _wing(Canvas canvas, double r, double dir, Paint paint, double flap) {
    final double lift = math.sin(flap) * r * 0.4;
    final Path w = Path()
      ..moveTo(0, -r * 0.2)
      ..lineTo(dir * r * 1.6, -r * 0.9 - lift)
      ..lineTo(dir * r * 1.5, -r * 0.1 - lift)
      ..lineTo(dir * r * 1.3, r * 0.4 - lift)
      ..close();
    canvas.drawPath(w, paint);
  }

  void _wyvern(Canvas canvas, double r, Paint body, Paint dark, double flap) {
    final Paint wing = Paint()..color = dark.color.withOpacity(0.85);
    _wing(canvas, r, -1, wing, flap * 6);
    _wing(canvas, r, 1, wing, flap * 6);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 1.8, height: r * 1.3),
      body,
    );
    canvas.drawCircle(Offset(r * 0.9, -r * 0.3), r * 0.55, body);
    // Horn.
    final Path horn = Path()
      ..moveTo(r * 0.8, -r * 0.7)
      ..lineTo(r * 1.0, -r * 1.1)
      ..lineTo(r * 1.05, -r * 0.6)
      ..close();
    canvas.drawPath(horn, dark);
    _eyes(canvas, r, r * 1.05, -r * 0.4, r * 0.16);
  }

  void _dragon(Canvas canvas, double r, Paint body, Paint dark, double flap) {
    final Paint wing = Paint()..color = dark.color.withOpacity(0.9);
    _wing(canvas, r * 1.3, -1, wing, flap * 5);
    _wing(canvas, r * 1.3, 1, wing, flap * 5);
    // Tail.
    final Path tail = Path()
      ..moveTo(-r * 0.7, 0)
      ..lineTo(-r * 1.9, -r * 0.5)
      ..lineTo(-r * 1.7, -r * 0.7)
      ..lineTo(-r * 0.6, r * 0.3)
      ..close();
    canvas.drawPath(tail, body);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 2.0, height: r * 1.5),
      body,
    );
    canvas.drawCircle(Offset(r * 1.0, -r * 0.3), r * 0.6, body);
    // Horns.
    for (final double hx in <double>[0.75, 1.1]) {
      final Path horn = Path()
        ..moveTo(r * hx, -r * 0.75)
        ..lineTo(r * hx + r * 0.05, -r * 1.25)
        ..lineTo(r * hx + r * 0.18, -r * 0.7)
        ..close();
      canvas.drawPath(horn, dark);
    }
    // Belly.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, r * 0.3),
        width: r * 1.1,
        height: r * 0.8,
      ),
      Paint()..color = dark.color.withOpacity(0.4),
    );
    _eyes(canvas, r, r * 1.15, -r * 0.45, r * 0.18);
  }

  void _beetle(Canvas canvas, double r, Paint body, Paint dark) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 1.6),
      body,
    );
    canvas.drawLine(
      Offset(0, -r * 0.8),
      Offset(0, r * 0.8),
      Paint()
        ..color = dark.color
        ..strokeWidth = 2,
    );
    // Antennae.
    canvas.drawLine(
      Offset(r * 0.6, -r * 0.6),
      Offset(r * 1.1, -r * 1.1),
      Paint()
        ..color = dark.color
        ..strokeWidth = 2,
    );
    _eyes(canvas, r, r * 0.7, -r * 0.2, r * 0.14);
  }

  void _bat(Canvas canvas, double r, Paint body, Paint dark, double flap) {
    final Paint wing = Paint()..color = dark.color;
    _wing(canvas, r * 0.9, -1, wing, flap * 8);
    _wing(canvas, r * 0.9, 1, wing, flap * 8);
    canvas.drawCircle(Offset.zero, r * 0.7, body);
    // Ears.
    for (final int s in <int>[-1, 1]) {
      final Path ear = Path()
        ..moveTo(s * r * 0.3, -r * 0.5)
        ..lineTo(s * r * 0.5, -r * 0.95)
        ..lineTo(s * r * 0.55, -r * 0.4)
        ..close();
      canvas.drawPath(ear, body);
    }
    _eyes(canvas, r, r * 0.25, -r * 0.05, r * 0.14);
    _eyes(canvas, r, -r * 0.25, -r * 0.05, r * 0.14);
  }

  void _boar(Canvas canvas, double r, Paint body, Paint dark) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 2.2, height: r * 1.5),
      body,
    );
    canvas.drawCircle(Offset(r * 0.9, 0), r * 0.6, body);
    // Snout.
    canvas.drawCircle(Offset(r * 1.35, r * 0.05), r * 0.25, dark);
    // Tusks.
    for (final int s in <int>[-1, 1]) {
      final Path t = Path()
        ..moveTo(r * 1.25, s * r * 0.1)
        ..lineTo(r * 1.55, s * r * 0.3 - r * 0.1)
        ..lineTo(r * 1.3, s * r * 0.1 + r * 0.08)
        ..close();
      canvas.drawPath(t, Paint()..color = Colors.white);
    }
    _eyes(canvas, r, r * 0.95, -r * 0.3, r * 0.14);
  }

  void _toad(Canvas canvas, double r, Paint body, Paint dark) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 2.2, height: r * 1.6),
      body,
    );
    // Spots.
    final Paint spot = Paint()..color = dark.color;
    canvas.drawCircle(Offset(-r * 0.4, r * 0.1), r * 0.2, spot);
    canvas.drawCircle(Offset(r * 0.5, r * 0.25), r * 0.16, spot);
    // Bulging eyes.
    canvas.drawCircle(Offset(-r * 0.5, -r * 0.7), r * 0.32, body);
    canvas.drawCircle(Offset(r * 0.5, -r * 0.7), r * 0.32, body);
    _eyes(canvas, r, -r * 0.5, -r * 0.7, r * 0.22);
    _eyes(canvas, r, r * 0.5, -r * 0.7, r * 0.22);
  }

  void _flame(Canvas canvas, double r, Paint body, Paint dark, double t) {
    final Path p = Path();
    final double w = math.sin(t * 6) * r * 0.1;
    p.moveTo(0, r);
    p.quadraticBezierTo(-r, r * 0.3, -r * 0.5, -r * 0.2);
    p.quadraticBezierTo(-r * 0.2, -r * 0.5, 0, -r + w);
    p.quadraticBezierTo(r * 0.2, -r * 0.5, r * 0.5, -r * 0.2);
    p.quadraticBezierTo(r, r * 0.3, 0, r);
    p.close();
    canvas.drawPath(p, body);
    // Inner core.
    canvas.drawCircle(
      Offset(0, r * 0.1),
      r * 0.4,
      Paint()..color = const Color(0xFFFFEB3B),
    );
    _eyes(canvas, r, r * 0.2, -r * 0.1, r * 0.12);
    _eyes(canvas, r, -r * 0.2, -r * 0.1, r * 0.12);
  }

  @override
  bool shouldRepaint(GamePainter oldDelegate) => true;
}
