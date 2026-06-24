using UnityEngine;

namespace EvolutionIsland
{
    /// <summary>
    /// The hero. Movement is deliberately simple: arrow keys or WASD move the
    /// creature up / down / left / right on the island. Combat is automatic —
    /// the player keeps firing at the nearest enemy in range with no button
    /// presses required.
    /// </summary>
    public class PlayerController : MonoBehaviour
    {
        // Tunable stats (GameManager raises these on level up).
        public float MoveSpeed = 9f;
        public float MaxHp = 100f;
        public float Damage = 18f;
        public float AttackRange = 14f;
        public float AttackCooldown = 0.45f;
        public float ProjectileSpeed = 22f;
        public float Radius = 0.9f;

        public float Hp { get; private set; }
        public Vector3 Position { get { return transform.position; } }

        float _attackTimer;
        Transform _model;
        float _bobPhase;
        readonly Color _shotColor = new Color(0.35f, 0.9f, 1f);

        void Awake()
        {
            Hp = MaxHp;
            _model = transform.Find("Model");
        }

        public void ResetState()
        {
            Hp = MaxHp;
            _attackTimer = 0f;
        }

        void Update()
        {
            var gm = GameManager.Instance;
            if (gm == null || gm.IsGameOver)
            {
                return;
            }

            float dt = Time.deltaTime;

            // ---- Movement: up / down / left / right ----
            float h = Input.GetAxisRaw("Horizontal"); // A/D or Left/Right
            float v = Input.GetAxisRaw("Vertical");   // W/S or Up/Down
            Vector3 dir = new Vector3(h, 0f, v);
            if (dir.sqrMagnitude > 1f)
            {
                dir.Normalize();
            }

            if (dir.sqrMagnitude > 0.0001f)
            {
                transform.position += dir * MoveSpeed * dt;
                transform.position = gm.ClampToIsland(transform.position);
                transform.rotation = Quaternion.Slerp(transform.rotation,
                    Quaternion.LookRotation(dir), 12f * dt);

                if (_model != null)
                {
                    _bobPhase += dt * 12f;
                    float bob = Mathf.Abs(Mathf.Sin(_bobPhase)) * 0.12f;
                    _model.localPosition = new Vector3(0f, bob, 0f);
                }
            }
            else if (_model != null)
            {
                _model.localPosition = Vector3.Lerp(
                    _model.localPosition, Vector3.zero, 8f * dt);
            }

            // ---- Automatic attack ----
            _attackTimer -= dt;
            if (_attackTimer <= 0f)
            {
                Enemy target = gm.NearestEnemy(transform.position, AttackRange);
                if (target != null)
                {
                    _attackTimer = AttackCooldown;
                    Vector3 aim = target.Position - transform.position;
                    aim.y = 0f;
                    aim.Normalize();

                    // Snap to face the target while attacking.
                    if (aim.sqrMagnitude > 0.0001f)
                    {
                        transform.rotation = Quaternion.LookRotation(aim);
                    }

                    Vector3 origin = transform.position +
                        Vector3.up * 1.1f + aim * (Radius + 0.4f);
                    gm.SpawnProjectile(origin, aim, ProjectileSpeed, Damage,
                        0.3f, 3f, true, _shotColor);
                }
            }
        }

        public void TakeDamage(float dmg)
        {
            var gm = GameManager.Instance;
            if (gm == null || gm.IsGameOver)
            {
                return;
            }
            Hp -= dmg;
            if (Hp <= 0f)
            {
                Hp = 0f;
                gm.GameOver();
            }
        }

        public void Heal(float amount)
        {
            Hp = Mathf.Min(MaxHp, Hp + amount);
        }
    }
}
