import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'models.dart';
import 'painter.dart';

/// 达尔文进化岛 —— A self-contained, single-player survival game.
///
/// You wake on a monster-infested island as a tiny slime. Move with the
/// on-screen joystick (drag anywhere), automatically attack the nearest
/// monster, gather EXP from the kills and evolve through six escalating life
/// forms, all the way up to the Ancient Dragon.
class EvolutionIslandGame extends StatefulWidget {
  const EvolutionIslandGame({super.key});

  @override
  State<EvolutionIslandGame> createState() => _EvolutionIslandGameState();
}

class _EvolutionIslandGameState extends State<EvolutionIslandGame>
    with SingleTickerProviderStateMixin {
  static const double islandRadius = 1400;

  final math.Random _rng = math.Random();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _time = 0;

  // ---- Player state ---------------------------------------------------------
  Offset _playerPos = Offset.zero;
  double _hp = 100;
  int _level = 1;
  int _exp = 0;
  int _expToNext = 10;
  int _kills = 0;
  EvolutionStage _stage = kEvolutionStages.first;
  double _attackTimer = 0;
  double _playerWobble = 0;
  bool _facingRight = true;
  double _invuln = 0;

  bool _gameOver = false;
  bool _started = false;

  // ---- World entities -------------------------------------------------------
  final List<Monster> _monsters = <Monster>[];
  final List<Projectile> _projectiles = <Projectile>[];
  final List<Particle> _particles = <Particle>[];
  final List<FloatingText> _texts = <FloatingText>[];
  final List<Scenery> _decorations = <Scenery>[];
  double _spawnTimer = 0;

  // ---- Input ----------------------------------------------------------------
  Offset? _joyBase; // null when idle
  Offset? _joyKnob;
  Offset _moveDir = Offset.zero;

  @override
  void initState() {
    super.initState();
    _resetGame();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _resetGame() {
    _playerPos = Offset.zero;
    _hp = kEvolutionStages.first.maxHp;
    _level = 1;
    _exp = 0;
    _expToNext = 10;
    _kills = 0;
    _stage = kEvolutionStages.first;
    _attackTimer = 0;
    _invuln = 0;
    _gameOver = false;
    _monsters.clear();
    _projectiles.clear();
    _particles.clear();
    _texts.clear();
    _decorations.clear();
    _spawnTimer = 0;
    _joyBase = null;
    _moveDir = Offset.zero;

    _generateDecorations();
    for (int i = 0; i < 9; i++) {
      _spawnMonster(awayFromPlayer: true);
    }
  }

  void _generateDecorations() {
    final math.Random r = math.Random(42);
    for (int i = 0; i < 46; i++) {
      final Offset pos = randomPointInCircle(r, Offset.zero, islandRadius - 80);
      if (pos.distance < 160) {
        continue; // keep the spawn area clear
      }
      _decorations.add(
        Scenery(
          position: pos,
          radius: 14 + r.nextDouble() * 26,
          isRock: r.nextBool(),
          seed: i,
        ),
      );
    }
  }

  int get _maxMonsters => 10 + _level * 2;

  void _spawnMonster({bool awayFromPlayer = false}) {
    // Choose among monster types unlocked for the current level, by weight.
    final List<MonsterType> pool = kMonsterTypes
        .where((t) => t.minPlayerLevel <= _level)
        .toList();
    if (pool.isEmpty) {
      return;
    }
    double total = 0;
    for (final MonsterType t in pool) {
      total += t.weight;
    }
    double pick = _rng.nextDouble() * total;
    MonsterType type = pool.first;
    for (final MonsterType t in pool) {
      pick -= t.weight;
      if (pick <= 0) {
        type = t;
        break;
      }
    }

    Offset pos;
    int tries = 0;
    do {
      pos = randomPointInCircle(_rng, Offset.zero, islandRadius - 60);
      tries++;
    } while (awayFromPlayer && (pos - _playerPos).distance < 320 && tries < 30);

    // Scale stats up with player level so the island stays threatening.
    final double scale = 1 + (_level - 1) * 0.12;
    _monsters.add(
      Monster(
        type: type,
        position: pos,
        hp: type.baseHp * scale,
        maxHp: type.baseHp * scale,
        attack: type.baseAttack * (1 + (_level - 1) * 0.08),
        expReward: (type.expReward * (1 + (_level - 1) * 0.05)).round(),
      ),
    );
  }

  // ---- Game loop ------------------------------------------------------------
  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    double dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt > 0.05) {
      dt = 0.05; // clamp to avoid huge jumps after a stall
    }
    _time += dt;

    if (_started && !_gameOver) {
      _update(dt);
    }
    setState(() {});
  }

  void _update(double dt) {
    _updatePlayer(dt);
    _updateMonsters(dt);
    _updateProjectiles(dt);
    _updateEffects(dt);
    _handleSpawning(dt);
  }

  void _updatePlayer(double dt) {
    if (_moveDir != Offset.zero) {
      _playerPos += _moveDir * _stage.speed * dt;
      _facingRight = _moveDir.dx >= 0;
      _playerWobble += dt * 14;
      // Constrain to the island.
      if (_playerPos.distance > islandRadius - 20) {
        _playerPos = normalize(_playerPos) * (islandRadius - 20);
      }
    }

    if (_invuln > 0) {
      _invuln -= dt;
    }

    // Passive health regeneration.
    _hp = math.min(_stage.maxHp, _hp + _stage.maxHp * 0.01 * dt);

    // Auto-attack the nearest monster in range.
    _attackTimer -= dt;
    if (_attackTimer <= 0) {
      final Monster? target = _nearestMonster(_stage.attackRange);
      if (target != null) {
        _attackTimer = _stage.attackCooldown;
        _facingRight = target.position.dx >= _playerPos.dx;
        if (_stage.ranged) {
          _fireProjectile(target);
        } else {
          _meleeHit(target);
        }
      }
    }
  }

  Monster? _nearestMonster(double range) {
    Monster? best;
    double bestDist = range;
    for (final Monster m in _monsters) {
      final double d = (m.position - _playerPos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = m;
      }
    }
    return best;
  }

  void _meleeHit(Monster target) {
    _damageMonster(target, _stage.attack);
    // Slash spark burst toward the target.
    final Offset dir = normalize(target.position - _playerPos);
    final Offset hitPos = _playerPos + dir * _stage.radius;
    for (int i = 0; i < 6; i++) {
      final double a =
          math.atan2(dir.dy, dir.dx) + (_rng.nextDouble() - 0.5) * 1.2;
      _particles.add(
        Particle(
          position: hitPos,
          velocity: Offset(math.cos(a), math.sin(a)) * 120,
          color: Colors.white,
          life: 0.25,
          maxLife: 0.25,
          radius: 4,
        ),
      );
    }
  }

  void _fireProjectile(Monster target) {
    final Offset dir = normalize(target.position - _playerPos);
    _projectiles.add(
      Projectile(
        position: _playerPos + dir * _stage.radius,
        velocity: dir * 460,
        damage: _stage.attack,
        radius: 9,
        color: _stage.accent,
        fromPlayer: true,
        life: 1.4,
      ),
    );
  }

  void _damageMonster(Monster m, double dmg) {
    m.hp -= dmg;
    _texts.add(
      FloatingText(
        position: m.position.translate(0, -m.radius - 6),
        text: dmg.round().toString(),
        color: Colors.white,
        size: 16,
      ),
    );
    if (m.isDead) {
      _killMonster(m);
    }
  }

  void _killMonster(Monster m) {
    _monsters.remove(m);
    _kills++;
    _gainExp(m.expReward);
    _texts.add(
      FloatingText(
        position: m.position.translate(0, -m.radius),
        text: '+${m.expReward}',
        color: const Color(0xFFFFEB3B),
        size: 15,
      ),
    );
    for (int i = 0; i < 14; i++) {
      final double a = _rng.nextDouble() * math.pi * 2;
      final double sp = 60 + _rng.nextDouble() * 140;
      _particles.add(
        Particle(
          position: m.position,
          velocity: Offset(math.cos(a), math.sin(a)) * sp,
          color: m.type.color,
          life: 0.5,
          maxLife: 0.5,
          radius: 5,
        ),
      );
    }
  }

  void _gainExp(int amount) {
    _exp += amount;
    while (_exp >= _expToNext) {
      _exp -= _expToNext;
      _levelUp();
    }
  }

  void _levelUp() {
    _level++;
    _expToNext = (10 + _level * _level * 1.6).round();
    final EvolutionStage newStage = stageForLevel(_level);
    if (newStage.name != _stage.name) {
      _evolve(newStage);
    } else {
      // Small heal on every level up.
      _hp = math.min(_stage.maxHp, _hp + _stage.maxHp * 0.25);
      _texts.add(
        FloatingText(
          position: _playerPos.translate(0, -_stage.radius - 20),
          text: '升级! Lv.$_level',
          color: const Color(0xFF80D8FF),
          size: 20,
        ),
      );
    }
  }

  void _evolve(EvolutionStage newStage) {
    _stage = newStage;
    _hp = newStage.maxHp; // full heal on evolution
    _invuln = 1.2;
    _texts.add(
      FloatingText(
        position: _playerPos.translate(0, -newStage.radius - 26),
        text: '进化! ${newStage.name}',
        color: const Color(0xFFFFD740),
        size: 26,
      ),
    );
    // Evolution shockwave.
    for (int i = 0; i < 30; i++) {
      final double a = _rng.nextDouble() * math.pi * 2;
      _particles.add(
        Particle(
          position: _playerPos,
          velocity:
              Offset(math.cos(a), math.sin(a)) *
              (160 + _rng.nextDouble() * 120),
          color: const Color(0xFFFFD740),
          life: 0.7,
          maxLife: 0.7,
          radius: 6,
        ),
      );
    }
  }

  void _updateMonsters(double dt) {
    for (final Monster m in _monsters) {
      m.wobble += dt * 10;
      final Offset toPlayer = _playerPos - m.position;
      final double dist = toPlayer.distance;

      if (dist < m.type.aggroRange) {
        // Chase the player.
        final Offset dir = normalize(toPlayer);
        m.position += dir * m.type.speed * dt;
        m.facingRight = dir.dx >= 0;
      } else {
        // Wander.
        m.wanderTimer -= dt;
        if (m.wanderTimer <= 0) {
          m.wanderTimer = 1.5 + _rng.nextDouble() * 2;
          final double a = _rng.nextDouble() * math.pi * 2;
          m.wanderDir = Offset(math.cos(a), math.sin(a));
        }
        m.position += m.wanderDir * m.type.speed * 0.4 * dt;
        if (m.wanderDir.dx != 0) {
          m.facingRight = m.wanderDir.dx >= 0;
        }
      }

      // Keep monsters on the island.
      if (m.position.distance > islandRadius - 10) {
        m.position = normalize(m.position) * (islandRadius - 10);
      }

      // Attack the player on contact (or fire if ranged).
      m.attackTimer -= dt;
      if (dist < m.type.contactRange && m.attackTimer <= 0) {
        m.attackTimer = m.type.attackCooldown;
        if (m.type.ranged) {
          final Offset dir = normalize(toPlayer);
          _projectiles.add(
            Projectile(
              position: m.position + dir * m.radius,
              velocity: dir * 300,
              damage: m.attack,
              radius: 8,
              color: m.type.color,
              fromPlayer: false,
              life: 2.0,
            ),
          );
        } else {
          _hurtPlayer(m.attack);
        }
      }
    }
  }

  void _hurtPlayer(double dmg) {
    if (_invuln > 0) {
      return;
    }
    _hp -= dmg;
    _invuln = 0.4;
    _texts.add(
      FloatingText(
        position: _playerPos.translate(0, -_stage.radius - 10),
        text: '-${dmg.round()}',
        color: const Color(0xFFFF5252),
        size: 18,
      ),
    );
    if (_hp <= 0) {
      _hp = 0;
      _gameOver = true;
    }
  }

  void _updateProjectiles(double dt) {
    for (final Projectile p in _projectiles) {
      p.position += p.velocity * dt;
      p.life -= dt;
      if (p.life <= 0 || p.position.distance > islandRadius + 100) {
        p.dead = true;
        continue;
      }
      if (p.fromPlayer) {
        for (final Monster m in _monsters) {
          if ((m.position - p.position).distance < m.radius + p.radius) {
            _damageMonster(m, p.damage);
            p.dead = true;
            break;
          }
        }
      } else {
        if ((_playerPos - p.position).distance < _stage.radius + p.radius) {
          _hurtPlayer(p.damage);
          p.dead = true;
        }
      }
    }
    _projectiles.removeWhere((p) => p.dead);
  }

  void _updateEffects(double dt) {
    for (final Particle p in _particles) {
      p.position += p.velocity * dt;
      p.velocity *= 0.92;
      p.life -= dt;
    }
    _particles.removeWhere((p) => p.life <= 0);

    for (final FloatingText t in _texts) {
      t.position = t.position.translate(0, -28 * dt);
      t.life -= dt;
    }
    _texts.removeWhere((t) => t.life <= 0);

    _playerWobble += dt * 3; // idle breathing
  }

  void _handleSpawning(double dt) {
    _spawnTimer -= dt;
    if (_spawnTimer <= 0 && _monsters.length < _maxMonsters) {
      _spawnTimer = math.max(0.4, 1.6 - _level * 0.05);
      _spawnMonster(awayFromPlayer: true);
    }
  }

  // ---- Input handling -------------------------------------------------------
  void _onPanStart(DragStartDetails d) {
    if (!_started) {
      setState(() => _started = true);
      return;
    }
    if (_gameOver) {
      return;
    }
    setState(() {
      _joyBase = d.localPosition;
      _joyKnob = d.localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final Offset? base = _joyBase;
    if (base == null) {
      return;
    }
    final Offset delta = d.localPosition - base;
    const double maxR = 60;
    final double dist = delta.distance;
    final Offset clamped = dist > maxR ? normalize(delta) * maxR : delta;
    setState(() {
      _joyKnob = base + clamped;
      _moveDir = dist > 8 ? normalize(delta) : Offset.zero;
    });
  }

  void _onPanEnd(DragEndDetails d) {
    setState(() {
      _joyBase = null;
      _joyKnob = null;
      _moveDir = Offset.zero;
    });
  }

  // ---- UI -------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B6FA8),
      body: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: <Widget>[
            // The game world.
            Positioned.fill(
              child: CustomPaint(
                painter: GamePainter(
                  playerPos: _playerPos,
                  playerStage: _stage,
                  playerFacingRight: _facingRight,
                  playerWobble: _playerWobble,
                  invulnFlash: _invuln,
                  islandRadius: islandRadius,
                  monsters: _monsters,
                  projectiles: _projectiles,
                  particles: _particles,
                  floatingTexts: _texts,
                  decorations: _decorations,
                  time: _time,
                ),
              ),
            ),

            // Virtual joystick.
            if (_joyBase != null) _buildJoystick(),

            // HUD.
            if (_started && !_gameOver) _buildHud(),

            // Start screen.
            if (!_started) _buildStartScreen(),

            // Game over screen.
            if (_gameOver) _buildGameOverScreen(),
          ],
        ),
      ),
    );
  }

  Widget _buildJoystick() {
    final Offset base = _joyBase!;
    final Offset knob = _joyKnob!;
    return Positioned(
      left: base.dx - 70,
      top: base.dy - 70,
      child: IgnorePointer(
        child: SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.12),
                  border: Border.all(color: Colors.white24, width: 2),
                ),
              ),
              Positioned(
                left: 70 + (knob.dx - base.dx) - 28,
                top: 70 + (knob.dy - base.dy) - 28,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHud() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _statBadge('Lv.$_level', const Color(0xFF1565C0)),
                const SizedBox(width: 8),
                _statBadge(_stage.name, _stage.accent),
                const Spacer(),
                _statBadge('击杀 $_kills', const Color(0xFF424242)),
              ],
            ),
            const SizedBox(height: 10),
            _bar(
              'HP',
              _hp / _stage.maxHp,
              const Color(0xFFE53935),
              '${_hp.round()} / ${_stage.maxHp.round()}',
            ),
            const SizedBox(height: 6),
            _bar(
              'EXP',
              _exp / _expToNext,
              const Color(0xFFFFB300),
              '$_exp / $_expToNext',
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _bar(String label, double frac, Color color, String value) {
    return SizedBox(
      width: 260,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: <Widget>[
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: frac.clamp(0.0, 1.0).toDouble(),
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Container(
                  height: 16,
                  alignment: Alignment.center,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartScreen() {
    return Container(
      color: Colors.black.withOpacity(0.55),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              '达尔文进化岛',
              style: TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Darwin Evolution Island',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            Container(
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '🏝  孤岛上遍布各种怪物。\n'
                '🕹  拖动屏幕任意位置移动（虚拟摇杆）。\n'
                '⚔  自动攻击范围内最近的怪物。\n'
                '🧬  击杀获得经验，升级后不断进化：\n'
                '    史莱姆 → 蜥蜴 → 影狼 → 岩石巨兽\n'
                '    → 烈焰翼龙 → 远古巨龙\n'
                '❤  小心，HP 归零即游戏结束！',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 16,
                ),
                backgroundColor: const Color(0xFF43A047),
              ),
              onPressed: () => setState(() => _started = true),
              child: const Text(
                '开始游戏',
                style: TextStyle(fontSize: 20, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOverScreen() {
    return Container(
      color: Colors.black.withOpacity(0.65),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            '你被吞噬了…',
            style: TextStyle(
              color: Color(0xFFFF5252),
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '进化阶段：${_stage.name}',
            style: const TextStyle(color: Colors.white, fontSize: 20),
          ),
          Text(
            '达到等级：Lv.$_level',
            style: const TextStyle(color: Colors.white, fontSize: 20),
          ),
          Text(
            '击杀怪物：$_kills',
            style: const TextStyle(color: Colors.white, fontSize: 20),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              backgroundColor: const Color(0xFF43A047),
            ),
            onPressed: () => setState(_resetGame),
            child: const Text(
              '再来一局',
              style: TextStyle(fontSize: 20, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
