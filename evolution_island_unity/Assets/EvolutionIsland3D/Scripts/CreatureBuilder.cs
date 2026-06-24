using UnityEngine;

namespace EvolutionIsland
{
    /// <summary>
    /// The three kinds of creature we build procedurally out of Unity
    /// primitives, so the game needs no imported 3D model assets.
    /// </summary>
    public enum CreatureKind
    {
        Player,
        MeleeAnimal,
        RangedAnimal,
    }

    /// <summary>
    /// Builds simple but recognisable 3D creatures (and a couple of scenery
    /// props) from Unity's built-in primitives at runtime. Every creature is a
    /// root GameObject with a single "Model" child that holds the visual parts,
    /// so gameplay scripts can bob / rotate the model without touching the
    /// logical root transform.
    /// </summary>
    public static class CreatureBuilder
    {
        public static GameObject Build(CreatureKind kind)
        {
            var root = new GameObject(kind.ToString());
            var model = new GameObject("Model");
            model.transform.SetParent(root.transform, false);

            switch (kind)
            {
                case CreatureKind.Player:
                    BuildPlayer(model.transform);
                    break;
                case CreatureKind.MeleeAnimal:
                    BuildMelee(model.transform);
                    break;
                case CreatureKind.RangedAnimal:
                    BuildRanged(model.transform);
                    break;
            }
            return root;
        }

        /// <summary>Creates one coloured primitive parented under <paramref name="parent"/>.</summary>
        public static GameObject Part(
            Transform parent,
            PrimitiveType type,
            Vector3 pos,
            Vector3 scale,
            Color color,
            Quaternion? rot = null)
        {
            var go = GameObject.CreatePrimitive(type);
            // Visual-only parts must not collide or physically push each other.
            var col = go.GetComponent<Collider>();
            if (col != null)
            {
                Object.Destroy(col);
            }
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = rot ?? Quaternion.identity;
            go.transform.localScale = scale;
            // Setting .color on the primitive's default material keeps the
            // correct shader for whichever render pipeline the project uses.
            go.GetComponent<Renderer>().material.color = color;
            return go;
        }

        static void Eye(Transform parent, Vector3 pos, float size)
        {
            Part(parent, PrimitiveType.Sphere, pos, Vector3.one * size, Color.white);
            Part(parent, PrimitiveType.Sphere,
                pos + new Vector3(0, 0, size * 0.45f),
                Vector3.one * size * 0.5f, Color.black);
        }

        // ---- Player: a friendly green biped -----------------------------------
        static void BuildPlayer(Transform m)
        {
            var green = new Color(0.40f, 0.78f, 0.40f);
            var dark = new Color(0.22f, 0.50f, 0.25f);

            // Legs.
            Part(m, PrimitiveType.Cylinder, new Vector3(-0.28f, 0.4f, 0),
                new Vector3(0.28f, 0.4f, 0.28f), dark);
            Part(m, PrimitiveType.Cylinder, new Vector3(0.28f, 0.4f, 0),
                new Vector3(0.28f, 0.4f, 0.28f), dark);
            // Body.
            Part(m, PrimitiveType.Capsule, new Vector3(0, 1.15f, 0),
                new Vector3(0.85f, 0.65f, 0.85f), green);
            // Arms.
            Part(m, PrimitiveType.Capsule, new Vector3(-0.55f, 1.15f, 0),
                new Vector3(0.25f, 0.45f, 0.25f), green,
                Quaternion.Euler(0, 0, 20));
            Part(m, PrimitiveType.Capsule, new Vector3(0.55f, 1.15f, 0),
                new Vector3(0.25f, 0.45f, 0.25f), green,
                Quaternion.Euler(0, 0, -20));
            // Head.
            Part(m, PrimitiveType.Sphere, new Vector3(0, 1.95f, 0),
                Vector3.one * 0.7f, green);
            // Tail.
            Part(m, PrimitiveType.Capsule, new Vector3(0, 1.0f, -0.6f),
                new Vector3(0.2f, 0.35f, 0.2f), dark,
                Quaternion.Euler(60, 0, 0));
            // Eyes (facing +Z, the forward direction).
            Eye(m, new Vector3(-0.2f, 2.05f, 0.5f), 0.16f);
            Eye(m, new Vector3(0.2f, 2.05f, 0.5f), 0.16f);
        }

        // ---- Melee animal: a charging red boar --------------------------------
        static void BuildMelee(Transform m)
        {
            var hide = new Color(0.55f, 0.28f, 0.22f);
            var dark = new Color(0.32f, 0.16f, 0.12f);

            // Body (long along +Z).
            Part(m, PrimitiveType.Cube, new Vector3(0, 0.85f, 0),
                new Vector3(0.95f, 0.85f, 1.6f), hide);
            // Head at the front.
            Part(m, PrimitiveType.Sphere, new Vector3(0, 0.8f, 1.0f),
                Vector3.one * 0.85f, hide);
            // Snout.
            Part(m, PrimitiveType.Cube, new Vector3(0, 0.7f, 1.45f),
                new Vector3(0.4f, 0.35f, 0.3f), dark);
            // Tusks.
            Part(m, PrimitiveType.Cube, new Vector3(-0.22f, 0.65f, 1.5f),
                new Vector3(0.08f, 0.08f, 0.35f), Color.white,
                Quaternion.Euler(-25, 0, 0));
            Part(m, PrimitiveType.Cube, new Vector3(0.22f, 0.65f, 1.5f),
                new Vector3(0.08f, 0.08f, 0.35f), Color.white,
                Quaternion.Euler(-25, 0, 0));
            // Ears.
            Part(m, PrimitiveType.Cube, new Vector3(-0.35f, 1.25f, 0.9f),
                new Vector3(0.18f, 0.25f, 0.08f), dark);
            Part(m, PrimitiveType.Cube, new Vector3(0.35f, 1.25f, 0.9f),
                new Vector3(0.18f, 0.25f, 0.08f), dark);
            // Four legs.
            float[] zs = { 0.55f, -0.55f };
            float[] xs = { -0.35f, 0.35f };
            foreach (var z in zs)
            {
                foreach (var x in xs)
                {
                    Part(m, PrimitiveType.Cylinder, new Vector3(x, 0.3f, z),
                        new Vector3(0.22f, 0.3f, 0.22f), dark);
                }
            }
            // Eyes.
            Eye(m, new Vector3(-0.28f, 1.0f, 1.35f), 0.14f);
            Eye(m, new Vector3(0.28f, 1.0f, 1.35f), 0.14f);
        }

        // ---- Ranged animal: a purple spitting toad ----------------------------
        static void BuildRanged(Transform m)
        {
            var skin = new Color(0.55f, 0.36f, 0.80f);
            var dark = new Color(0.30f, 0.18f, 0.45f);

            // Wide squat body.
            Part(m, PrimitiveType.Sphere, new Vector3(0, 0.65f, 0),
                new Vector3(1.5f, 0.95f, 1.4f), skin);
            // Spots.
            Part(m, PrimitiveType.Sphere, new Vector3(-0.4f, 1.0f, -0.2f),
                Vector3.one * 0.3f, dark);
            Part(m, PrimitiveType.Sphere, new Vector3(0.45f, 0.95f, 0.1f),
                Vector3.one * 0.25f, dark);
            // Muzzle / spitter cannon, pointing forward (+Z).
            Part(m, PrimitiveType.Cylinder, new Vector3(0, 0.55f, 0.85f),
                new Vector3(0.22f, 0.3f, 0.22f), dark,
                Quaternion.Euler(90, 0, 0));
            // Big bulging eyes on top.
            Part(m, PrimitiveType.Sphere, new Vector3(-0.38f, 1.15f, 0.35f),
                Vector3.one * 0.4f, skin);
            Part(m, PrimitiveType.Sphere, new Vector3(0.38f, 1.15f, 0.35f),
                Vector3.one * 0.4f, skin);
            Eye(m, new Vector3(-0.38f, 1.2f, 0.55f), 0.18f);
            Eye(m, new Vector3(0.38f, 1.2f, 0.55f), 0.18f);
            // Stubby legs.
            Part(m, PrimitiveType.Sphere, new Vector3(-0.6f, 0.25f, 0.5f),
                Vector3.one * 0.35f, dark);
            Part(m, PrimitiveType.Sphere, new Vector3(0.6f, 0.25f, 0.5f),
                Vector3.one * 0.35f, dark);
            Part(m, PrimitiveType.Sphere, new Vector3(-0.55f, 0.25f, -0.5f),
                Vector3.one * 0.3f, dark);
            Part(m, PrimitiveType.Sphere, new Vector3(0.55f, 0.25f, -0.5f),
                Vector3.one * 0.3f, dark);
        }

        // ---- Scenery ----------------------------------------------------------
        public static GameObject BuildTree()
        {
            var root = new GameObject("Tree");
            Part(root.transform, PrimitiveType.Cylinder, new Vector3(0, 0.9f, 0),
                new Vector3(0.3f, 0.9f, 0.3f), new Color(0.45f, 0.30f, 0.18f));
            Part(root.transform, PrimitiveType.Sphere, new Vector3(0, 2.1f, 0),
                Vector3.one * 1.6f, new Color(0.20f, 0.55f, 0.25f));
            return root;
        }

        public static GameObject BuildRock()
        {
            var root = new GameObject("Rock");
            Part(root.transform, PrimitiveType.Cube, new Vector3(0, 0.4f, 0),
                new Vector3(1.1f, 0.8f, 0.9f), new Color(0.55f, 0.55f, 0.58f),
                Quaternion.Euler(0, 30, 12));
            return root;
        }
    }
}
