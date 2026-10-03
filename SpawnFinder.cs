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
    /// distance from centre, altitude, forest) and, from SpawnSystem.UpdateSpawnList, which rules
    /// are open in this world (Rules.OpenRules). Tilt, lava, player bases and ocean depth need the
    /// loaded terrain and are not checked, so an area is "can spawn here", not "will". Also not
    /// reproduced: sub-biome spawn lists and the spawns they block, and the game's own biome test,
    /// which reads the zone's four corner biome sectors where this asks the seed per point.
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

        // The pins of the last Find, and the map they are on: a new world brings a new Minimap, and the old
        // pins went with the old one.
        private readonly List<Minimap.PinData> _pins = new List<Minimap.PinData>();
        private Minimap _pinsMap;
        private Coroutine _search;

        public static bool HasPins
        {
            get { return _instance != null && _instance._pins.Count > 0 && _instance._pinsMap != null; }
        }

        private void Awake()
        {
            _instance = this;
        }

        public static void Find(string prefabName, string displayName)
        {
            _instance.StartFind(prefabName, displayName);
        }

        /// <summary>Takes the last Find's pins off the map, and its arrow if a spawn area is still being tracked.</summary>
        public static void Clear()
        {
            if (_instance != null)
                _instance.RemovePins();

            if (Tracker.IsTracking && !Tracker.IsTrackingCreature)
                Tracker.Stop();
        }

        /// <summary>
        /// For the map's delete gesture (see RemoveAreaPinPatch): removes the area pin nearest to
        /// <paramref name="pos"/> within <paramref name="radius"/>, chosen as Minimap.GetClosestPin chooses
        /// (shown on the map, nearest by DistanceXZ, strictly inside the radius). False if there is none.
        /// </summary>
        public static bool RemovePinNear(Minimap map, Vector3 pos, float radius)
        {
            if (_instance == null || map == null || _instance._pinsMap != map)
                return false;

            List<Minimap.PinData> pins = _instance._pins;
            int nearest = -1;
            float nearestDistance = radius;
            for (int i = 0; i < pins.Count; i++)
            {
                Minimap.PinData pin = pins[i];
                if (pin.m_uiElement == null || !pin.m_uiElement.gameObject.activeInHierarchy)
                    continue;

                float distance = Utils.DistanceXZ(pos, pin.m_pos);
                if (distance < nearestDistance)
                {
                    nearest = i;
                    nearestDistance = distance;
                }
            }

            if (nearest < 0)
                return false;

            Events.MapDeleteTookAreaPin(pins[nearest].m_name);
            map.RemovePin(pins[nearest]);
            pins.RemoveAt(nearest);
            return true;
        }

        private void RemovePins()
        {
            Events.PinsRemoved(_pins.Count);
            if (_pinsMap != null)
            {
                foreach (Minimap.PinData pin in _pins)
                    _pinsMap.RemovePin(pin);
            }
            _pins.Clear();
            _pinsMap = null;
        }

        private void StartFind(string prefabName, string displayName)
        {
            Player player = Player.m_localPlayer;
            if (player == null || WorldGenerator.instance == null || ZoneSystem.instance == null)
            {
                Events.FindNotStarted();
                return;
            }

            // Every SpawnSystem carries the same lists; any loaded zone's will do.
            if (SpawnSystem.m_instances.Count == 0)
            {
                Say("No zone loaded yet - try again in a moment");
                return;
            }

            var named = new List<SpawnSystem.SpawnData>();
            foreach (SpawnSystemList list in SpawnSystem.m_instances[0].m_spawnLists)
            {
                foreach (SpawnSystem.SpawnData spawn in list.m_spawners)
                {
                    if (spawn.m_enabled && spawn.m_prefab != null && spawn.m_prefab.name == prefabName)
                        named.Add(spawn);
                }
            }

            // Global keys reach every client (ZoneSystem.SendGlobalKeys on connect and on every change), and the
            // client that owns a zone is the one that spawns in it, so this world's keys are the ones that count.
            var keys = new List<string>();
            var events = new List<string>();
            ZoneSystem zones = ZoneSystem.instance;
            List<SpawnSystem.SpawnData> rules = Rules.OpenRules(named, rule => rule.m_requiredGlobalKey, rule => rule.m_requiredPersistentEvent,
                key => zones.GetGlobalKey(key), keys, events);

            if (rules.Count == 0)
            {
                if (_search != null)
                {
                    StopCoroutine(_search);
                    _search = null;
                }
                Clear(); // the last Find's pins and arrow are for another creature
                Say(Rules.NoOpenRule(displayName, keys, events));
                return;
            }

            if (_search != null)
            {
                Events.FindReplaced();
                StopCoroutine(_search);
            }
            _search = StartCoroutine(Search(rules, displayName, player.transform.position));
        }

        private IEnumerator Search(List<SpawnSystem.SpawnData> rules, string displayName, Vector3 origin)
        {
            Say("Searching the world for " + displayName + " spawn areas...");
            WorldGenerator world = WorldGenerator.instance;
            var clock = Stopwatch.StartNew();
            var total = Stopwatch.StartNew(); // for the verbose log: the whole search, and the frames it took
            int frames = 1; // this one; each pause below adds the frame it resumes in

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
                    frames++;
                    yield return null;
                    clock.Restart();
                }
            }

            // The sort gets a frame of its own: an ocean creature has some 25,000 candidates, about 8 ms.
            frames++;
            yield return null;
            clock.Restart();

            // Pass 2, nearest first: the expensive height test only runs on zones that would
            // become a new pin, until there are enough pins.
            var from = new Vector2(origin.x, origin.z);
            candidates.Sort((a, b) => (a - from).sqrMagnitude.CompareTo((b - from).sqrMagnitude));

            var areas = new List<Vector2>();
            SpawnSystem.SpawnData nearestRule = null; // the rule that produced areas[0]
            foreach (Vector2 centre in candidates)
            {
                if (areas.Count >= AreaCount)
                    break;

                if (Rules.IsSpaced(centre.x, centre.y, areas, AreaSpacing, a => a.x, a => a.y))
                {
                    SpawnSystem.SpawnData matched = ZoneOk(world, rules, centre);
                    if (matched != null)
                    {
                        if (areas.Count == 0)
                            nearestRule = matched;
                        areas.Add(centre);
                    }
                }

                if (clock.ElapsedMilliseconds > FrameBudgetMs)
                {
                    frames++;
                    yield return null;
                    clock.Restart();
                }
            }

            _search = null;
            Events.FindDone(displayName, total.ElapsedMilliseconds, frames, candidates.Count, areas.Count);
            Report(rules, nearestRule, displayName, from, areas);
        }

        private void Report(List<SpawnSystem.SpawnData> rules, SpawnSystem.SpawnData nearestRule, string displayName, Vector2 from, List<Vector2> areas)
        {
            RemovePins();

            if (areas.Count == 0)
            {
                if (Tracker.IsTracking && !Tracker.IsTrackingCreature)
                    Tracker.Stop(); // still pointing at another creature's area
                string rule = Describe(rules[0], rules.Count);
                MobTrackerPlugin.Log.LogInfo(displayName + " world spawn: " + rule + " - no matching area");
                Say(displayName + ": " + rule + " - no matching area in this world");
                return;
            }

            string matched = Describe(nearestRule, rules.Count);
            MobTrackerPlugin.Log.LogInfo(displayName + " world spawn, nearest area by: " + matched);

            Minimap map = Minimap.instance;
            if (map != null)
                _pinsMap = map;
            foreach (Vector2 area in areas)
            {
                var position = new Vector3(area.x, WaterLevel, area.y);
                MobTrackerPlugin.Log.LogInfo("  area at " + position + ", " + Mathf.RoundToInt((area - from).magnitude) + "m away");
                // Local-only: save false, and ownerID left at 0, so the pin is never written to the map data,
                // never shared at a cartography table, and gone in the next session.
                if (map != null)
                    _pins.Add(map.AddPin(position, Minimap.PinType.Icon3, displayName + " area", false, false));
            }

            Tracker.TrackPoint(new Vector3(areas[0].x, WaterLevel, areas[0].y), displayName + " spawn area");
            Say(displayName + ": " + matched + " - nearest area " + Mathf.RoundToInt((areas[0] - from).magnitude) + "m, " + areas.Count + " pinned on the map");
        }

        /// <summary>The first rule a sample point of the zone satisfies, or null.</summary>
        private static SpawnSystem.SpawnData ZoneOk(WorldGenerator world, List<SpawnSystem.SpawnData> rules, Vector2 centre)
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
                        return rule;
                }
            }
            return null;
        }

        /// <summary>
        /// Edge if any neighbour 64 m away is another biome, asked of the seed noise directly. The game's
        /// own test (Heightmap.GetBiomeArea) is Edge when the zone's four corner biome sectors differ, so
        /// near a border the two can disagree; this one is the stricter, and tends to miss a zone rather
        /// than pin a wrong one.
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

        /// <param name="ruleCount">How many rules are open for this creature, <paramref name="rule"/> included.</param>
        private static string Describe(SpawnSystem.SpawnData rule, int ruleCount)
        {
            string text = rule.m_biome.ToString();

            if (rule.m_minDistanceFromCenter > 0f || rule.m_maxDistanceFromCenter > 0f)
                text += ", " + Mathf.RoundToInt(rule.m_minDistanceFromCenter) + "-"
                      + (rule.m_maxDistanceFromCenter > 0f ? Mathf.RoundToInt(rule.m_maxDistanceFromCenter).ToString() : "any") + "m from centre";

            text += rule.m_spawnAtDay && rule.m_spawnAtNight ? ", day+night" : rule.m_spawnAtNight ? ", night only" : ", day only";

            if (!string.IsNullOrEmpty(rule.m_requiredGlobalKey))
                text += ", since " + rule.m_requiredGlobalKey; // an open rule's key is one the world has
            if (rule.m_requiredEnvironments.Count > 0)
                text += ", weather: " + string.Join("/", rule.m_requiredEnvironments);
            if (ruleCount > 1)
                text += " (+" + (ruleCount - 1) + " more rule" + (ruleCount > 2 ? "s" : "") + ")";

            return text;
        }

        private static void Say(string text)
        {
            Events.FindSays(text);
            if (MessageHud.instance != null)
                MessageHud.instance.ShowMessage(MessageHud.MessageType.Center, text);
        }
    }
}
