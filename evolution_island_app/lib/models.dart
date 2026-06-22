import 'dart:math' as math;
import 'dart:ui';

/// Shapes used to render creatures. Each form is drawn procedurally so the
/// game needs no image assets.
enum CreatureForm {
  slime,
  lizard,
  wolf,
  golem,
  wyvern,
  dragon,
  beetle,
  bat,
  boar,
  toad,
  flame,
}

/// One step on the player's evolutionary ladder. Reaching [minLevel] morphs the
/// player into this stage, fully heals it and grants the listed combat stats.
class EvolutionStage {
  const EvolutionStage({
    required this.name,
    required this.minLevel,
    required this.maxHp,
    required this.attack,
    required this.attackRange,
    required this.attackCooldown,
    required this.speed,
    required this.radius,
    required this.color,
    required this.accent,
    required this.form,
    required this.ranged,
    required this.description,
  });

  final String name;
  final int minLevel;
  final double maxHp;
  final double attack;
  final double attackRange;
  final double attackCooldown;
  final double speed;
  final double radius;
  final Color color;
  final Color accent;
  final CreatureForm form;
  final bool ranged;
  final String description;
}

/// The full evolution chain, ordered from weakest to strongest.
const List<EvolutionStage> kEvolutionStages = <EvolutionStage>[
  EvolutionStage(
    name: '幼苗史莱姆',
    minLevel: 1,
    maxHp: 100,
    attack: 12,
    attackRange: 70,
    attackCooldown: 0.55,
    speed: 150,
    radius: 18,
    color: Color(0xFF7CD66B),
    accent: Color(0xFF2E7D32),
    form: CreatureForm.slime,
    ranged: false,
    description: '一团柔软的生命，刚刚在岛上苏醒。',
  ),
  EvolutionStage(
    name: '利齿蜥蜴',
    minLevel: 3,
    maxHp: 180,
    attack: 22,
    attackRange: 85,
    attackCooldown: 0.5,
    speed: 175,
    radius: 21,
    color: Color(0xFF66BB6A),
    accent: Color(0xFF1B5E20),
    form: CreatureForm.lizard,
    ranged: false,
    description: '长出了尖牙与利爪，开始主动狩猎。',
  ),
  EvolutionStage(
    name: '影狼',
    minLevel: 6,
    maxHp: 320,
    attack: 38,
    attackRange: 95,
    attackCooldown: 0.42,
    speed: 205,
    radius: 24,
    color: Color(0xFF607D8B),
    accent: Color(0xFF263238),
    form: CreatureForm.wolf,
    ranged: false,
    description: '迅捷而凶猛，成群猎物的噩梦。',
  ),
  EvolutionStage(
    name: '岩石巨兽',
    minLevel: 10,
    maxHp: 560,
    attack: 60,
    attackRange: 110,
    attackCooldown: 0.5,
    speed: 165,
    radius: 30,
    color: Color(0xFF8D6E63),
    accent: Color(0xFF4E342E),
    form: CreatureForm.golem,
    ranged: false,
    description: '皮坚肉厚的庞然大物，一击碎石。',
  ),
  EvolutionStage(
    name: '烈焰翼龙',
    minLevel: 15,
    maxHp: 820,
    attack: 78,
    attackRange: 230,
    attackCooldown: 0.45,
    speed: 215,
    radius: 32,
    color: Color(0xFFEF6C00),
    accent: Color(0xFFB71C1C),
    form: CreatureForm.wyvern,
    ranged: true,
    description: '展开烈焰之翼，从远处喷吐火球。',
  ),
  EvolutionStage(
    name: '远古巨龙',
    minLevel: 21,
    maxHp: 1300,
    attack: 110,
    attackRange: 270,
    attackCooldown: 0.38,
    speed: 235,
    radius: 38,
    color: Color(0xFFC62828),
    accent: Color(0xFFFFD54F),
    form: CreatureForm.dragon,
    ranged: true,
    description: '岛屿真正的霸主，进化的终点。',
  ),
];

/// Returns the highest evolution stage the player qualifies for at [level].
EvolutionStage stageForLevel(int level) {
  EvolutionStage current = kEvolutionStages.first;
  for (final EvolutionStage stage in kEvolutionStages) {
    if (level >= stage.minLevel) {
      current = stage;
    }
  }
  return current;
}

/// Static description of a kind of monster. Concrete monsters are spawned from
/// these blueprints with their stats scaled by the player's level.
class MonsterType {
  const MonsterType({
    required this.name,
    required this.baseHp,
    required this.baseAttack,
    required this.speed,
    required this.radius,
    required this.color,
    required this.accent,
    required this.form,
    required this.expReward,
    required this.aggroRange,
    required this.attackCooldown,
    required this.contactRange,
    required this.minPlayerLevel,
    required this.weight,
    required this.ranged,
  });

  final String name;
  final double baseHp;
  final double baseAttack;
  final double speed;
  final double radius;
  final Color color;
  final Color accent;
  final CreatureForm form;
  final int expReward;
  final double aggroRange;
  final double attackCooldown;
  final double contactRange;

  /// The monster only starts appearing once the player reaches this level.
  final int minPlayerLevel;

  /// Relative spawn likelihood among the currently unlocked monster types.
  final double weight;
  final bool ranged;
}

const List<MonsterType> kMonsterTypes = <MonsterType>[
  MonsterType(
    name: '甲虫',
    baseHp: 40,
    baseAttack: 6,
    speed: 70,
    radius: 14,
    color: Color(0xFF795548),
    accent: Color(0xFF3E2723),
    form: CreatureForm.beetle,
    expReward: 6,
    aggroRange: 220,
    attackCooldown: 1.1,
    contactRange: 34,
    minPlayerLevel: 1,
    weight: 5,
    ranged: false,
  ),
  MonsterType(
    name: '暗影蝙蝠',
    baseHp: 30,
    baseAttack: 8,
    speed: 165,
    radius: 13,
    color: Color(0xFF5E35B1),
    accent: Color(0xFF311B92),
    form: CreatureForm.bat,
    expReward: 9,
    aggroRange: 320,
    attackCooldown: 0.9,
    contactRange: 32,
    minPlayerLevel: 2,
    weight: 4,
    ranged: false,
  ),
  MonsterType(
    name: '狂暴野猪',
    baseHp: 95,
    baseAttack: 14,
    speed: 120,
    radius: 20,
    color: Color(0xFF8D6E63),
    accent: Color(0xFF4E342E),
    form: CreatureForm.boar,
    expReward: 16,
    aggroRange: 300,
    attackCooldown: 1.0,
    contactRange: 44,
    minPlayerLevel: 4,
    weight: 3.5,
    ranged: false,
  ),
  MonsterType(
    name: '剧毒巨蛙',
    baseHp: 130,
    baseAttack: 18,
    speed: 95,
    radius: 22,
    color: Color(0xFF558B2F),
    accent: Color(0xFF33691E),
    form: CreatureForm.toad,
    expReward: 22,
    aggroRange: 300,
    attackCooldown: 1.2,
    contactRange: 46,
    minPlayerLevel: 6,
    weight: 3,
    ranged: false,
  ),
  MonsterType(
    name: '岩石魔像',
    baseHp: 280,
    baseAttack: 30,
    speed: 70,
    radius: 30,
    color: Color(0xFF616161),
    accent: Color(0xFF212121),
    form: CreatureForm.golem,
    expReward: 40,
    aggroRange: 260,
    attackCooldown: 1.4,
    contactRange: 58,
    minPlayerLevel: 9,
    weight: 2,
    ranged: false,
  ),
  MonsterType(
    name: '火焰元素',
    baseHp: 200,
    baseAttack: 26,
    speed: 110,
    radius: 22,
    color: Color(0xFFFF7043),
    accent: Color(0xFFBF360C),
    form: CreatureForm.flame,
    expReward: 48,
    aggroRange: 380,
    attackCooldown: 1.6,
    contactRange: 230,
    minPlayerLevel: 13,
    weight: 2,
    ranged: true,
  ),
];

/// Shared 2D vector helper built on [Offset].
Offset normalize(Offset v) {
  final double d = v.distance;
  if (d == 0) {
    return Offset.zero;
  }
  return v / d;
}

/// A live monster instance fighting on the island.
class Monster {
  Monster({
    required this.type,
    required this.position,
    required this.hp,
    required this.maxHp,
    required this.attack,
    required this.expReward,
  });

  final MonsterType type;
  Offset position;
  double hp;
  double maxHp;
  double attack;
  int expReward;

  Offset velocity = Offset.zero;
  double attackTimer = 0;
  bool facingRight = true;
  double wobble = 0;

  // A random wander heading used while the player is out of aggro range.
  Offset wanderDir = Offset.zero;
  double wanderTimer = 0;

  double get radius => type.radius;
  bool get isDead => hp <= 0;
  double get healthFraction => (hp / maxHp).clamp(0.0, 1.0).toDouble();
}

/// A damaging shot fired by the player (or a ranged monster).
class Projectile {
  Projectile({
    required this.position,
    required this.velocity,
    required this.damage,
    required this.radius,
    required this.color,
    required this.fromPlayer,
    required this.life,
  });

  Offset position;
  Offset velocity;
  double damage;
  double radius;
  Color color;
  bool fromPlayer;
  double life;

  bool dead = false;
}

/// Short-lived rising combat text (damage numbers, level-up, etc.).
class FloatingText {
  FloatingText({
    required this.position,
    required this.text,
    required this.color,
    required this.size,
  });

  Offset position;
  String text;
  Color color;
  double size;
  double life = 0.9;
}

/// A small decorative spark used for hit and death bursts.
class Particle {
  Particle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.life,
    required this.maxLife,
    required this.radius,
  });

  Offset position;
  Offset velocity;
  Color color;
  double life;
  double maxLife;
  double radius;
}

/// Static island scenery (rocks, bushes) generated once per game.
class Scenery {
  Scenery({
    required this.position,
    required this.radius,
    required this.isRock,
    required this.seed,
  });

  Offset position;
  double radius;
  bool isRock;
  int seed;
}

/// Picks a random point inside a circle of [radius] around [center].
Offset randomPointInCircle(math.Random rng, Offset center, double radius) {
  final double angle = rng.nextDouble() * math.pi * 2;
  final double r = radius * math.sqrt(rng.nextDouble());
  return center + Offset(math.cos(angle) * r, math.sin(angle) * r);
}
