using System.Collections.Generic;
using UnityEngine;

namespace EvolutionIsland
{
    /// <summary>
    /// Owns the whole game: builds the 3D world, follows the player with the
    /// camera, spawns melee / ranged animals, tracks level &amp; kills, and draws
    /// the on-screen HUD. Created automatically by <see cref="GameBootstrap"/>.
    /// </summary>
    public class GameManager : MonoBehaviour
    {
        public static GameManager Instance { get; private set; }

        public const float IslandRadius = 38f;

        public PlayerController Player { get; private set; }
        public readonly List<Enemy> Enemies = new List<Enemy>();
        public bool IsGameOver { get; private set; }

        // Progression.
        int _level = 1;
        int _xp;
        int _xpToNext = 10;
        int _kills;

        // Spawning.
        float _spawnTimer;

        // Camera.
        Transform _cam;
        readonly Vector3 _camOffset = new Vector3(0f, 20f, -16f);

        // HUD textures (1x1 solid colours), cached by colour.
        readonly Dictionary<Color, Texture2D> _texCache =
            new Dictionary<Color, Texture2D>();
        GUIStyle _label;
        GUIStyle _big;

        void Awake()
        {
            Instance = this;
        }

        void Start()
        {
            BuildEnvironment();
            StartRun();
        }

        // ---- World construction ----------------------------------------------
        void BuildEnvironment()
        {
            // Camera (reuse the scene's main camera if present).
            Camera cam = Camera.main;
            if (cam == null)
            {
                var camGo = new GameObject("Main Camera");
                camGo.tag = "MainCamera";
                cam = camGo.AddComponent<Camera>();
            }
            cam.fieldOfView = 55f;
            _cam = cam.transform;

            // Directional light (only if the scene has none).
            if (FindObjectOfType<Light>() == null)
            {
                var lightGo = new GameObject("Sun");
                var light = lightGo.AddComponent<Light>();
                light.type = LightType.Directional;
                light.intensity = 1.1f;
                light.color = new Color(1f, 0.96f, 0.88f);
                lightGo.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
            }

            // Sea.
            CreatureBuilder.Part(transform, PrimitiveType.Plane,
                new Vector3(0f, -0.4f, 0f), new Vector3(40f, 1f, 40f),
                new Color(0.11f, 0.45f, 0.66f));

            // Beach ring + grass island.
            CreatureBuilder.Part(transform, PrimitiveType.Cylinder,
                new Vector3(0f, -0.45f, 0f),
                new Vector3((IslandRadius + 3f) * 2f, 0.4f, (IslandRadius + 3f) * 2f),
                new Color(0.90f, 0.84f, 0.62f));
            CreatureBuilder.Part(transform, PrimitiveType.Cylinder,
                new Vector3(0f, -0.4f, 0f),
                new Vector3(IslandRadius * 2f, 0.45f, IslandRadius * 2f),
                new Color(0.30f, 0.57f, 0.31f));

            // Scenery scattered around the island.
            for (int i = 0; i < 26; i++)
            {
                Vector2 p = Random.insideUnitCircle * (IslandRadius - 4f);
                if (p.magnitude < 6f)
                {
                    continue;
                }
                GameObject prop = (Random.value < 0.5f)
                    ? CreatureBuilder.BuildTree()
                    : CreatureBuilder.BuildRock();
                prop.transform.SetParent(transform, false);
                prop.transform.position = new Vector3(p.x, 0f, p.y);
                prop.transform.rotation = Quaternion.Euler(0f, Random.value * 360f, 0f);
            }
        }

        void StartRun()
        {
            IsGameOver = false;
            _level = 1;
            _xp = 0;
            _xpToNext = 10;
            _kills = 0;
            _spawnTimer = 0f;

            // Clear any existing actors.
            for (int i = 0; i < Enemies.Count; i++)
            {
                if (Enemies[i] != null)
                {
                    Destroy(Enemies[i].gameObject);
                }
            }
            Enemies.Clear();

            if (Player != null)
            {
                Destroy(Player.gameObject);
            }

            // Spawn the player.
            GameObject playerGo = CreatureBuilder.Build(CreatureKind.Player);
            playerGo.transform.position = Vector3.zero;
            Player = playerGo.AddComponent<PlayerController>();

            for (int i = 0; i < 6; i++)
            {
                SpawnEnemy();
            }
        }

        // ---- Per-frame --------------------------------------------------------
        void Update()
        {
            Enemies.RemoveAll(e => e == null);

            if (IsGameOver)
            {
                if (Input.GetKeyDown(KeyCode.R))
                {
                    StartRun();
                }
                return;
            }

            int cap = 8 + _level * 2;
            _spawnTimer -= Time.deltaTime;
            if (_spawnTimer <= 0f && Enemies.Count < cap)
            {
                _spawnTimer = Mathf.Max(0.5f, 1.8f - _level * 0.06f);
                SpawnEnemy();
            }
        }

        void LateUpdate()
        {
            if (_cam == null || Player == null)
            {
                return;
            }
            Vector3 target = Player.Position + _camOffset;
            _cam.position = Vector3.Lerp(_cam.position, target, 8f * Time.deltaTime);
            _cam.LookAt(Player.Position + Vector3.up * 1.2f);
        }

        // ---- Spawning & combat helpers ---------------------------------------
        void SpawnEnemy()
        {
            if (Player == null)
            {
                return;
            }
            float scale = 1f + (_level - 1) * 0.12f;
            bool ranged = Random.value < 0.4f;

            GameObject go = CreatureBuilder.Build(
                ranged ? CreatureKind.RangedAnimal : CreatureKind.MeleeAnimal);

            // Place on a ring around the player, kept on the island.
            Vector2 c = Random.insideUnitCircle.normalized * Random.Range(22f, 32f);
            Vector3 pos = ClampToIsland(Player.Position + new Vector3(c.x, 0f, c.y));
            go.transform.position = pos;

            var e = go.AddComponent<Enemy>();
            if (ranged)
            {
                e.Init(AttackStyle.Ranged, 30f * scale, 7f * scale, 5f,
                    16f, 1.6f, 12, 1.0f);
            }
            else
            {
                e.Init(AttackStyle.Melee, 45f * scale, 9f * scale, 6.5f,
                    1.6f, 1.0f, 8, 1.0f);
            }
            Enemies.Add(e);
        }

        public void SpawnProjectile(Vector3 pos, Vector3 dir, float speed,
            float damage, float radius, float life, bool fromPlayer, Color color)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            var proj = go.AddComponent<Projectile>();
            proj.Setup(pos, dir, speed, damage, radius, life, fromPlayer, color);
        }

        public Enemy NearestEnemy(Vector3 from, float range)
        {
            Enemy best = null;
            float bestDist = range;
            for (int i = 0; i < Enemies.Count; i++)
            {
                var e = Enemies[i];
                if (e == null)
                {
                    continue;
                }
                float d = Vector3.Distance(from, e.Position);
                if (d < bestDist)
                {
                    bestDist = d;
                    best = e;
                }
            }
            return best;
        }

        public Vector3 ClampToIsland(Vector3 p)
        {
            Vector2 flat = new Vector2(p.x, p.z);
            float max = IslandRadius - 1.5f;
            if (flat.magnitude > max)
            {
                flat = flat.normalized * max;
            }
            return new Vector3(flat.x, 0f, flat.y);
        }

        public void OnEnemyKilled(Enemy e, int xpReward)
        {
            _kills++;
            _xp += xpReward;
            while (_xp >= _xpToNext)
            {
                _xp -= _xpToNext;
                LevelUp();
            }
        }

        void LevelUp()
        {
            _level++;
            _xpToNext = 10 + _level * _level;
            if (Player != null)
            {
                Player.MaxHp += 15f;
                Player.Damage += 3f;
                Player.AttackCooldown = Mathf.Max(0.16f, Player.AttackCooldown - 0.01f);
                Player.Heal(Player.MaxHp); // full heal on level up
                // Grow a little to show progress.
                float s = Mathf.Min(1.8f, 1f + (_level - 1) * 0.04f);
                Player.transform.localScale = Vector3.one * s;
                Player.Radius = 0.9f * s;
            }
        }

        public void GameOver()
        {
            IsGameOver = true;
        }

        // ---- HUD (IMGUI) ------------------------------------------------------
        Texture2D Tex(Color c)
        {
            Texture2D t;
            if (!_texCache.TryGetValue(c, out t) || t == null)
            {
                t = new Texture2D(1, 1);
                t.SetPixel(0, 0, c);
                t.Apply();
                _texCache[c] = t;
            }
            return t;
        }

        void Bar(float x, float y, float w, float h, float frac, Color fg)
        {
            GUI.DrawTexture(new Rect(x, y, w, h), Tex(new Color(0f, 0f, 0f, 0.55f)));
            GUI.DrawTexture(new Rect(x, y, w * Mathf.Clamp01(frac), h), Tex(fg));
        }

        void OnGUI()
        {
            if (_label == null)
            {
                _label = new GUIStyle(GUI.skin.label) { fontSize = 16, fontStyle = FontStyle.Bold };
                _label.normal.textColor = Color.white;
                _big = new GUIStyle(GUI.skin.label)
                {
                    fontSize = 34,
                    fontStyle = FontStyle.Bold,
                    alignment = TextAnchor.MiddleCenter,
                };
                _big.normal.textColor = Color.white;
            }

            // Enemy health bars in world space.
            if (_cam != null)
            {
                Camera cam = _cam.GetComponent<Camera>();
                for (int i = 0; i < Enemies.Count; i++)
                {
                    var e = Enemies[i];
                    if (e == null || e.HealthFraction >= 1f)
                    {
                        continue;
                    }
                    Vector3 sp = cam.WorldToScreenPoint(e.Position + Vector3.up * 2.4f);
                    if (sp.z <= 0f)
                    {
                        continue;
                    }
                    Color barColor = e.Style == AttackStyle.Ranged
                        ? new Color(0.7f, 0.4f, 1f)
                        : new Color(1f, 0.35f, 0.3f);
                    Bar(sp.x - 22f, Screen.height - sp.y, 44f, 5f,
                        e.HealthFraction, barColor);
                }
            }

            // Player stats panel.
            if (Player != null && !IsGameOver)
            {
                GUI.DrawTexture(new Rect(10, 10, 260, 96),
                    Tex(new Color(0f, 0f, 0f, 0.35f)));
                GUI.Label(new Rect(20, 14, 240, 22),
                    "等级 Lv." + _level + "    击杀 " + _kills, _label);
                GUI.Label(new Rect(20, 40, 60, 20), "HP", _label);
                Bar(70, 42, 190, 16, Player.Hp / Player.MaxHp,
                    new Color(0.9f, 0.25f, 0.25f));
                GUI.Label(new Rect(20, 66, 60, 20), "EXP", _label);
                Bar(70, 68, 190, 16, (float)_xp / _xpToNext,
                    new Color(1f, 0.75f, 0.1f));
            }

            // Controls hint.
            GUI.Label(new Rect(12, Screen.height - 30, 600, 24),
                "方向键 / WASD 移动 · 自动攻击最近的敌人", _label);

            // Game over overlay.
            if (IsGameOver)
            {
                GUI.DrawTexture(new Rect(0, 0, Screen.width, Screen.height),
                    Tex(new Color(0f, 0f, 0f, 0.6f)));
                float cx = Screen.width * 0.5f;
                float cy = Screen.height * 0.5f;
                GUI.Label(new Rect(cx - 200, cy - 90, 400, 50), "你被击败了", _big);
                GUI.Label(new Rect(cx - 200, cy - 30, 400, 28),
                    "等级 Lv." + _level + "    击杀 " + _kills,
                    new GUIStyle(_big) { fontSize = 20 });
                if (GUI.Button(new Rect(cx - 90, cy + 24, 180, 46), "再来一局 (R)"))
                {
                    StartRun();
                }
            }
        }
    }
}
