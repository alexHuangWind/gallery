using UnityEngine;

namespace EvolutionIsland
{
    /// <summary>
    /// A straight-flying damage orb. Player projectiles hit enemies; enemy
    /// projectiles hit the player. Collision is resolved by simple distance
    /// checks against the GameManager's actor lists, so no physics is needed.
    /// </summary>
    public class Projectile : MonoBehaviour
    {
        bool _fromPlayer;
        float _damage;
        float _speed;
        float _radius;
        float _life;
        Vector3 _dir;

        public void Setup(Vector3 position, Vector3 dir, float speed, float damage,
            float radius, float life, bool fromPlayer, Color color)
        {
            transform.position = position;
            _dir = dir.normalized;
            _speed = speed;
            _damage = damage;
            _radius = radius;
            _life = life;
            _fromPlayer = fromPlayer;

            transform.localScale = Vector3.one * radius * 2f;
            var col = GetComponent<Collider>();
            if (col != null)
            {
                Destroy(col);
            }
            GetComponent<Renderer>().material.color = color;
        }

        void Update()
        {
            float dt = Time.deltaTime;
            transform.position += _dir * _speed * dt;
            _life -= dt;

            var gm = GameManager.Instance;
            if (_life <= 0f || gm == null)
            {
                Destroy(gameObject);
                return;
            }

            Vector3 pos = transform.position;

            if (_fromPlayer)
            {
                var enemies = gm.Enemies;
                for (int i = 0; i < enemies.Count; i++)
                {
                    var e = enemies[i];
                    if (e == null)
                    {
                        continue;
                    }
                    if (FlatDistance(pos, e.Position) < _radius + e.Radius)
                    {
                        e.TakeDamage(_damage);
                        Destroy(gameObject);
                        return;
                    }
                }
            }
            else
            {
                var p = gm.Player;
                if (p != null &&
                    FlatDistance(pos, p.Position) < _radius + p.Radius)
                {
                    p.TakeDamage(_damage);
                    Destroy(gameObject);
                    return;
                }
            }
        }

        // Horizontal-plane distance; the game plays top-down so vertical
        // offsets between a shot and its target should not matter.
        static float FlatDistance(Vector3 a, Vector3 b)
        {
            float dx = a.x - b.x;
            float dz = a.z - b.z;
            return Mathf.Sqrt(dx * dx + dz * dz);
        }
    }
}
