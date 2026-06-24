using UnityEngine;

namespace EvolutionIsland
{
    /// <summary>
    /// Zero-setup entry point. Thanks to <c>RuntimeInitializeOnLoadMethod</c>
    /// the game builds itself the moment you press Play — even in an empty
    /// scene. Just drop this Scripts folder into a Unity 3D project and run;
    /// there is nothing to wire up in the Inspector.
    /// </summary>
    public static class GameBootstrap
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Launch()
        {
            if (GameManager.Instance != null)
            {
                return; // already running
            }
            var go = new GameObject("EvolutionIslandGame");
            go.AddComponent<GameManager>();
        }
    }
}
