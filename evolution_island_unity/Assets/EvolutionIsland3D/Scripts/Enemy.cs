using UnityEngine;

namespace EvolutionIsland
{
    public enum AttackStyle
    {
        Melee,
        Ranged,
    }

    /// <summary>
    /// A hostile animal. Two behaviours share this one component:
    ///  - Melee  : charges the player and bites on contact.
    ///  - Ranged : keeps its distance and spits projectiles (kites the player).
    /// </summary>
    public class Enemy : MonoBehaviour
    {
        public AttackStyle Style { get; private set; }
        public float Radius { get; private set; }
        public Vector3 Position { get { return transform.position; } }

        float _hp;
        float _maxHp;
        float _damage;
        float _moveSpeed;
        float _attackRange;   // contact range (melee) or firing range (ranged)
        float _preferred;     // ranged: distance it tries to hold
        float _cooldown;
        float _timer;
        int _xpReward;
        Color _shotColor;

        Transform _model;
        float _bobPhase;

        public void Init(AttackStyle style, float hp, float damage, float speed,
            float attackRange, float cooldown, int xpReward, float radius)
        {
            Style = style;
            _hp = _maxHp = hp;
            _damage = damage;
            _moveSpeed = speed;
            _attackRange = attackRange;
            _preferred = attackRange * 0.8f;
            _cooldown = cooldown;
            _timer = Random.Range(0f, cooldown);
            _xpReward = xpReward;
            Radius = radius;
            _shotColor = new Color(1f, 0.55f, 0.15f);

            _model = transform.Find("Model");
            _bobPhase = Random.Range(0f, 10f);
        }

        public float HealthFraction { get { return Mathf.Clamp01(_hp / _maxHp); } }

        void Update()
        {
            var gm = GameManager.Instance;
            if (gm == null || gm.Player == null || gm.IsGameOver)
            {
                return;
            }

            float dt = Time.deltaTime;
            Vector3 toPlayer = gm.Player.Position - transform.position;
            toPlayer.y = 0f;
            float dist = toPlayer.magnitude;
            Vector3 dir = dist > 0.001f ? toPlayer / dist : Vector3.zero;

            Vector3 move = Vector3.zero;
            if (Style == AttackStyle.Melee)
            {
                // Always close in.
                move = dir;
            }
            else
            {
                // Kite: approach if too far, retreat if too close, else hold.
                if (dist > _attackRange)
                {
                    move = dir;
                }
                else if (dist < _preferred * 0.6f)
                {
                    move = -dir;
                }
            }

            transform.position += move * _moveSpeed * dt;
            transform.position = gm.ClampToIsland(transform.position);

            // Face the player.
            if (dir.sqrMagnitude > 0.0001f)
            {
                transform.rotation = Quaternion.Slerp(transform.rotation,
                    Quaternion.LookRotation(dir), 10f * dt);
            }

            // Bobbing animation.
            if (_model != null)
            {
                _bobPhase += dt * 9f;
                float h = Mathf.Abs(Mathf.Sin(_bobPhase)) * 0.12f;
                _model.localPosition = new Vector3(0f, h, 0f);
            }

            // Attack.
            _timer -= dt;
            if (_timer <= 0f)
            {
                if (Style == AttackStyle.Melee)
                {
                    if (dist <= _attackRange + gm.Player.Radius)
                    {
                        gm.Player.TakeDamage(_damage);
                        _timer = _cooldown;
                        if (_model != null)
                        {
                            _model.localPosition += dir * 0.2f; // tiny lunge
                        }
                    }
                }
                else
                {
                    if (dist <= _attackRange)
                    {
                        Vector3 origin = transform.position +
                            Vector3.up * 0.6f + dir * (Radius + 0.3f);
                        gm.SpawnProjectile(origin, dir, 14f, _damage, 0.32f,
                            4f, false, _shotColor);
                        _timer = _cooldown;
                    }
                }
            }
        }

        public void TakeDamage(float dmg)
        {
            _hp -= dmg;
            if (_hp <= 0f)
            {
                var gm = GameManager.Instance;
                if (gm != null)
                {
                    gm.OnEnemyKilled(this, _xpReward);
                }
                Destroy(gameObject);
            }
        }
    }
}
