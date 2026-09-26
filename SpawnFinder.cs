using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using UnityEngine;

namespace MobTracker
{
    /// <summary>
    /// Where in the world a creature's world-spawn rule can be satisfied. Biome and height come
    /// from WorldGenerator, which is a pure function of the world seed, so this works for zones
    /// that have never been loaded and on a client of a dedicated server.
    ///
    /// It mirrors the seed-derivable half of SpawnSystem.IsSpawnPointGood (biome, biome area,
    /// distance from centre, altitude, forest). Tilt, lava, player bases and ocean depth need the
    /// loaded terrain and are not checked, so an area is "can spawn here", not "will".
    /// </summary>
    internal class SpawnFinder : MonoBehaviour
    {
        private const float ZoneSize = 64f;
        private const float WorldRadius = 10500f;
        private const float WaterLevel = 30f;
        private const int AreaCount = 5;
        private const float AreaSpacing = 400f;  // pins closer than this are the same swamp
        private const long FrameBudgetMs = 4;

        // Zone centre plus the four quarter points: a zone counts if any of them passes.
        private static readonly Vector2[] Samples =
        {
            Vector2.zero, new Vector2(-16f, -16f), new Vector2(16f, -16f), new Vector2(16f, 16f), new Vector2(-16f, 16f)
        };

        private static SpawnFinder _instance;

        private readonly List<Minimap.PinData> _pins = new List<Minimap.PinData>();
        private Coroutine _search;

        private void Awake()
        {
            _instance = this;
        }

        public static void Find(string prefabName, string displayName)
        {
            _instance.StartFind(prefabName, displayName);
        }

        private void StartFind(string prefabName, string displayName)
        {
            Player player = Player.m_localPlayer;
            if (player == null || WorldGenerator.instance == null)
                return;

            // Every SpawnSystem carries the same lists; any loaded zone's will do.
            if (SpawnSystem.m_instances.Count == 0)
            {
                Say("No zone loaded yet - try again in a moment");
                return;
            }

            var rules = new List<SpawnSystem.SpawnData>();
            foreach (SpawnSystemList list in SpawnSystem.m_instances[0].m_spawnLists)
            {
                foreach (SpawnSystem.SpawnData spawn in list.m_spawners)
                {
                    if (spawn.m_enabled && spawn.m_prefab != null && spawn.m_prefab.name == prefabName)
                        rules.Add(spawn);
                }
            }

            if (rules.Count == 0)
            {
                Say(displayName + " has no world-spawn rule - it comes from spawners, raids or summons");
                return;
            }

            if (_search != null)
                StopCoroutine(_search);
            _search = StartCoroutine(Search(rules, displayName, player.transform.position));
        }

        private IEnumerator Search(List<SpawnSystem.SpawnData> rules, string displayName, Vector3 origin)
        {
            Say("Searching the world for " + displayName + " spawn areas...");
            WorldGenerator world = WorldGenerator.instance;
            var clock = Stopwatch.StartNew();

            // Pass 1, cheap: every zone whose centre has a biome and centre-distance some rule allows.
            var candidates = new List<Vector2>();
            int zones = Mathf.CeilToInt(WorldRadius / ZoneSize);
            for (int zx = -zones; zx <= zones; zx++)
            {
                for (int zy = -zones; zy <= zones; zy++)
                {
                    var centre = new Vector2(zx * ZoneSize, zy * ZoneSize);
                    if (centre.magnitude > WorldRadius)
                        continue;

                    Heightmap.Biome biome = Heightmap.Biome.None;
                    foreach (SpawnSystem.SpawnData rule in rules)
                    {
                        // Half a zone of slack: the rule is tested per point later, this is per centre.
                        if (!DistanceOk(rule, centre.magnitude, ZoneSize))
                            continue;

                        if (biome == Heightmap.Biome.None)
                            biome = world.GetBiome(centre.x, centre.y);
                        if ((rule.m_biome & biome) != 0)
                        {
                            candidates.Add(centre);
                            break;
                        }
                    }
                }

                if (clock.ElapsedMilliseconds > FrameBudgetMs)
                {
                    yield return null;
                    clock.Restart();
                }
            }

            // Pass 2, nearest first: the expensive height test only runs on zones that would
            // become a new pin, until there are enough pins.
            var from = new Vector2(origin.x, origin.z);
            candidates.Sort((a, b) => (a - from).sqrMagnitude.CompareTo((b - from).sqrMagnitude));

            var areas = new List<Vector2>();
            foreach (Vector2 centre in candidates)
            {
                if (areas.Count >= AreaCount)
                    break;

                if (Rules.IsSpaced(centre.x, centre.y, areas, AreaSpacing, a => a.x, a => a.y) && ZoneOk(world, rules, centre))
                    areas.Add(centre);

                if (clock.ElapsedMilliseconds > FrameBudgetMs)
                {
                    yield return null;
                    clock.Restart();
                }
            }

            _search = null;
            Report(rules, displayName, from, areas);
        }

        private void Report(List<SpawnSystem.SpawnData> rules, string displayName, Vector2 from, List<Vector2> areas)
        {
            string rule = Describe(rules);
            MobTrackerPlugin.Log.LogInfo(displayName + " world spawn: " + rule);

            if (Minimap.instance != null)
            {
                foreach (Minimap.PinData pin in _pins)
                    Minimap.instance.RemovePin(pin);
            }
            _pins.Clear();

            if (areas.Count == 0)
            {
                Say(displayName + ": " + rule + " - no matching area in this world");
                return;
            }

            foreach (Vector2 area in areas)
            {
                var position = new Vector3(area.x, WaterLevel, area.y);
                MobTrackerPlugin.Log.LogInfo("  area at " + position + ", " + Mathf.RoundToInt((area - from).magnitude) + "m away");
                if (Minimap.instance != null)
                    _pins.Add(Minimap.instance.AddPin(position, Minimap.PinType.Icon3, displayName + " area", false, false));
            }

            Tracker.TrackPoint(new Vector3(areas[0].x, WaterLevel, areas[0].y), displayName + " spawn area");
            Say(displayName + ": " + rule + " - nearest area " + Mathf.RoundToInt((areas[0] - from).magnitude) + "m, " + areas.Count + " pinned on the map");
        }

        private static bool ZoneOk(WorldGenerator world, List<SpawnSystem.SpawnData> rules, Vector2 centre)
        {
            foreach (Vector2 sample in Samples)
            {
                Vector2 p = centre + sample;
                Heightmap.Biome biome = world.GetBiome(p.x, p.y);
                float altitude = float.NaN; // worked out at most once per point; it is the costly part

                foreach (SpawnSystem.SpawnData rule in rules)
                {
                    if ((rule.m_biome & biome) == 0 || !DistanceOk(rule, p.magnitude, 0f))
                        continue;

                    var point = new Vector3(p.x, 0f, p.y);
                    if ((rule.m_biomeArea & BiomeArea(world, p, biome)) == 0)
                        continue;

                    if (!rule.m_inForest || !rule.m_outsideForest)
                    {
                        bool forest = WorldGenerator.InForest(point);
                        if ((forest && !rule.m_inForest) || (!forest && !rule.m_outsideForest))
                            continue;
                    }

                    if (float.IsNaN(altitude))
                        altitude = world.GetHeight(p.x, p.y) - WaterLevel;
                    if (altitude >= rule.m_minAltitude && altitude <= rule.m_maxAltitude)
                        return true;
                }
            }
            return false;
        }

        /// <summary>
        /// Edge if any neighbour 64 m away is another biome, as the game defines it - but asked of
        /// the seed noise directly. WorldGenerator.GetBiomeArea reads the biome-sector data, which
        /// answers "all Meadows" until it is ready and may never be on a server's client.
        /// </summary>
        private static Heightmap.BiomeArea BiomeArea(WorldGenerator world, Vector2 p, Heightmap.Biome biome)
        {
            for (int x = -1; x <= 1; x++)
            {
                for (int z = -1; z <= 1; z++)
                {
                    if ((x != 0 || z != 0) && world.GetBiome(p.x + x * ZoneSize, p.y + z * ZoneSize) != biome)
                        return Heightmap.BiomeArea.Edge;
                }
            }
            return Heightmap.BiomeArea.Median;
        }

        /// <summary>0 means "no limit" on either end, as in SpawnSystem.IsSpawnPointGood.</summary>
        private static bool DistanceOk(SpawnSystem.SpawnData rule, float fromCentre, float slack)
        {
            if (rule.m_minDistanceFromCenter > 0f && fromCentre < rule.m_minDistanceFromCenter - slack)
                return false;

            return !(rule.m_maxDistanceFromCenter > 0f) || fromCentre <= rule.m_maxDistanceFromCenter + slack;
        }

        private static string Describe(List<SpawnSystem.SpawnData> rules)
        {
            SpawnSystem.SpawnData rule = rules[0];
            string text = rule.m_biome.ToString();

            if (rule.m_minDistanceFromCenter > 0f || rule.m_maxDistanceFromCenter > 0f)
                text += ", " + Mathf.RoundToInt(rule.m_minDistanceFromCenter) + "-"
                      + (rule.m_maxDistanceFromCenter > 0f ? Mathf.RoundToInt(rule.m_maxDistanceFromCenter).ToString() : "any") + "m from centre";

            text += rule.m_spawnAtDay && rule.m_spawnAtNight ? ", day+night" : rule.m_spawnAtNight ? ", night only" : ", day only";

            if (!string.IsNullOrEmpty(rule.m_requiredGlobalKey))
                text += ", needs " + rule.m_requiredGlobalKey;
            if (rule.m_requiredEnvironments.Count > 0)
                text += ", weather: " + string.Join("/", rule.m_requiredEnvironments);
            if (rules.Count > 1)
                text += " (+" + (rules.Count - 1) + " more rule" + (rules.Count > 2 ? "s" : "") + ")";

            return text;
        }

        private static void Say(string text)
        {
            if (MessageHud.instance != null)
                MessageHud.instance.ShowMessage(MessageHud.MessageType.Center, text);
        }
    }
}
