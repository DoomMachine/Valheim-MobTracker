using System.Collections.Generic;
using UnityEngine;
using UnityEngine.AI;

namespace MobTracker
{
    /// <summary>One tracked creature, shown as a 3D arrow over the player or a line along the ground.</summary>
    internal class Tracker : MonoBehaviour
    {
        private static readonly Color GuideColor = new Color(1f, 0.78f, 0.1f, 1f);

        private const float PathInterval = 1f;
        private const float RequeryDistance = 1.5f; // a complete path is kept until either end moves this far
        private const float TileSize = 32f;          // Pathfinding.m_tileSize
        private const float PathStep = 2f;       // resample spacing, so the line follows the terrain
        private const float PathLift = 0.3f;     // above the ground, clear of z-fighting
        private const float ArrivedDistance = 5f; // a path ending this close to the target counts as complete
        private const int MaxPathPoints = 512;
        private const float MaxPathDistance = 250f; // beyond this the corridor is too many nav tiles to be worth building; arrow only
        private const float PointReachedDistance = 30f;

        public static Character Target { get; private set; }

        /// <summary>Separate from Target: a destroyed Unity object compares equal to null, and that is how "lost it" is noticed.</summary>
        public static bool IsTracking { get; private set; }

        /// <summary>A place rather than a creature (a spawn area): nothing to lose track of, done on arrival.</summary>
        private static bool _isPoint;
        private static Vector3 _point;

        public static bool IsTrackingCreature
        {
            get { return IsTracking && !_isPoint; }
        }

        /// <summary>What is tracked, as the verbose log names it - "Boar * (Boar)", or "Boar spawn area" - or null.</summary>
        internal static string Tracked
        {
            get { return !IsTracking ? null : _isPoint ? _targetName : EventLines.Creature(_targetName, _targetPrefab); }
        }

        internal static float TrackedSeconds
        {
            get { return Time.time - _since; }
        }

        internal static bool GuideHiddenNow
        {
            get { return _guideHidden; }
        }

        internal static bool TargetTamed
        {
            get { return _targetTamed; }
        }

        // Rules.GuideHidden's answer for this frame, also for the label in OnGUI.
        private static bool _guideHidden;

        private static string _targetName;
        // Kept for NearestWatched: a lost creature's own name and tameness may be gone with it.
        private static string _targetPrefab;
        private static bool _targetTamed;
        private static float _nextPath;
        // For the verbose log (Events, LogObserver): when this tracking began, and a count of tracking changes.
        private static float _since;
        internal static int Generation { get; private set; }

        private GameObject _arrow;
        private LineRenderer _line;
        private readonly List<Vector3> _points = new List<Vector3>();
        private NavMeshPath _navPath;
        private Vector3 _queriedFrom;
        private Vector3 _queriedTo;
        private float _lastKeepAlive = -1f;
        private bool _pathComplete;
        private float _distance;
        // The ground path's state as UpdatePath last left it (EventLines.Path*), and as the verbose log last said it.
        private int _pathState = -1;
        private int _loggedPathState = -1;
        private int _loggedGeneration = -1;
        private float _pathShortBy;
        private GUIStyle _hudStyle;

        public static void Track(Character character)
        {
            Events.TrackStarting(character); // before the fields change: it names what this replaces
            Target = character;
            IsTracking = true;
            _isPoint = false;
            _targetName = Creature.DisplayName(character);
            _targetPrefab = Creature.PrefabName(character);
            _targetTamed = character.IsTamed();
            _nextPath = 0f;
            _since = Time.time;
            Generation++;
        }

        public static void TrackPoint(Vector3 point, string name)
        {
            Events.TrackStartingArea(point, name);
            Target = null;
            IsTracking = true;
            _isPoint = true;
            _point = point;
            _targetName = name;
            _targetPrefab = null;
            _targetTamed = false;
            _nextPath = 0f;
            _since = Time.time;
            Generation++;
        }

        public static void Stop()
        {
            Events.TrackStopping();
            Target = null;
            IsTracking = false;
            Generation++;
        }

        private void Awake()
        {
            // Hidden/Internal-Colored ships inside "unity default resources", so unlike the game's
            // own shaders it cannot be stripped from the build. The others are fallbacks only.
            Shader shader = Shader.Find("Hidden/Internal-Colored") ?? Shader.Find("Sprites/Default") ?? Shader.Find("UI/Default");
            if (shader == null)
                MobTrackerPlugin.Log.LogError("No usable shader found; the tracking arrow and path will not render.");

            _arrow = new GameObject("MobTracker_Arrow");
            _arrow.transform.SetParent(transform, false);
            _arrow.AddComponent<MeshFilter>().sharedMesh = BuildArrowMesh();
            // ZWrite on + cull off: a convex mesh then draws correctly whatever the triangle winding.
            _arrow.AddComponent<MeshRenderer>().sharedMaterial = GuideMaterial(shader, zWrite: true, renderQueue: 2000);
            DisableShadows(_arrow.GetComponent<MeshRenderer>());
            _arrow.SetActive(false);

            var lineObject = new GameObject("MobTracker_Path");
            lineObject.transform.SetParent(transform, false);
            _line = lineObject.AddComponent<LineRenderer>();
            _line.useWorldSpace = true;
            _line.widthMultiplier = 0.25f;
            _line.numCornerVertices = 2;
            _line.startColor = _line.endColor = new Color(GuideColor.r, GuideColor.g, GuideColor.b, 0.85f);
            _line.sharedMaterial = GuideMaterial(shader, zWrite: false, renderQueue: 3100);
            DisableShadows(_line);
            _line.enabled = false;
        }

        private static Material GuideMaterial(Shader shader, bool zWrite, int renderQueue)
        {
            if (shader == null)
                return null;

            var material = new Material(shader) { hideFlags = HideFlags.HideAndDontSave };
            material.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
            material.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
            material.SetInt("_Cull", (int)UnityEngine.Rendering.CullMode.Off);
            material.SetInt("_ZWrite", zWrite ? 1 : 0);
            material.renderQueue = renderQueue;
            return material;
        }

        private static void DisableShadows(Renderer renderer)
        {
            renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            renderer.receiveShadows = false;
        }

        // LateUpdate, so the arrow sits on where the player ended up this frame rather than trailing it.
        private void LateUpdate()
        {
            Player player = Player.m_localPlayer;
            Events.TrackEnding(player); // why the tests below end the tracking, if they do
            if (IsTracking && player == null)
                Stop(); // logged out; nobody to tell

            if (IsTracking && !_isPoint && (Target == null || Target.IsDead()))
            {
                if (MessageHud.instance != null)
                    MessageHud.instance.ShowMessage(MessageHud.MessageType.TopLeft, "Lost track of " + _targetName);
                Stop();
                NearestWatched.Lost(_targetPrefab, _targetTamed); // lost, not stopped: the only place a re-track is scheduled
            }

            if (IsTracking && _isPoint && Utils.DistanceXZ(player.transform.position, _point) < PointReachedDistance)
            {
                if (MessageHud.instance != null)
                    MessageHud.instance.ShowMessage(MessageHud.MessageType.TopLeft, "Reached " + _targetName);
                Events.TrackReached();
                Stop();
            }

            if (!IsTracking)
            {
                _arrow.SetActive(false);
                _line.enabled = false;
                return;
            }

            // Tamed can happen while tracked. Read only while the creature is still on the network: in the frame the game
            // removes it, IsTamed already says false.
            if (!_isPoint && Target.GetZDOID() != ZDOID.None)
                _targetTamed = Target.IsTamed();

            // The guide hides whenever the game hides its own HUD or the player cannot be guided (Rules.GuideHidden);
            // the tracking goes on, and the guide comes back with the player (after a death the tracking usually ends first, when
            // the body is removed: Stop above). Each value is a plain call preflight traces.
            _guideHidden = Rules.GuideHidden(Hud.IsUserHidden(), InCutscene(player), player.IsDead(), WaitingForRespawn(),
                player.IsTeleporting());
            if (_guideHidden)
            {
                _arrow.SetActive(false);
                _line.enabled = false;
                return;
            }

            Vector3 from = player.transform.position;
            // A spawn area has no meaningful height; level with the player keeps the arrow flat.
            Vector3 to = _isPoint ? new Vector3(_point.x, from.y, _point.z) : Target.transform.position;
            _distance = Vector3.Distance(from, to);

            bool wantPath = ModConfig.Guide.Value == GuideMode.GroundPath && _distance < MaxPathDistance;
            if (wantPath && Time.time >= _nextPath)
            {
                _nextPath = Time.time + PathInterval;
                UpdatePath(from, to);
                LogPath();
            }

            _line.enabled = wantPath && _points.Count >= 2;

            // In path mode the arrow covers for a path that is missing or stops short: nav tiles
            // still building, a flying or swimming target, a cliff.
            bool showArrow = !wantPath || !_pathComplete;
            _arrow.SetActive(showArrow);
            if (!showArrow)
                return;

            Vector3 arrowPosition = from + Vector3.up * ModConfig.ArrowHeight.Value;
            Vector3 direction = (_isPoint ? to + Vector3.up * ModConfig.ArrowHeight.Value : Target.GetCenterPoint()) - arrowPosition;
            _arrow.transform.position = arrowPosition;
            _arrow.transform.localScale = Vector3.one * ModConfig.ArrowSize.Value;
            if (direction.sqrMagnitude > 0.0001f)
                _arrow.transform.rotation = Quaternion.LookRotation(direction);
        }

        /// <summary>
        /// Deliberately not Pathfinding.GetPath. GetPath pokes the 3x3 tiles round both ends on
        /// every call, and the game rebuilds any tile poked more than 5 s after its last build -
        /// re-collecting every collider in a 32 x 6000 x 32 m column on the main thread. Called
        /// once a second that kept the builder running back to back for as long as the track
        /// lasted. Here tiles are built once and then only kept alive (see KeepAlive), and the
        /// query skips GetPath's corner clean-up, which exists to smooth an agent's walk and costs
        /// a pile of navmesh raycasts a drawn line has no use for.
        /// </summary>
        private void UpdatePath(Vector3 from, Vector3 to)
        {
            Pathfinding pathfinding = Pathfinding.instance;
            if (pathfinding == null)
            {
                _points.Clear();
                _pathComplete = false;
                _pathState = EventLines.PathNoPathfinding;
                return;
            }

            // The tiles GetPath would ask for, plus the ones the straight line crosses: the game
            // never builds the middle of a long path by itself.
            // ponytail: corridor one tile wide. A detour wider than that stays a partial path
            // (arrow covers); widen it round the partial path's end if that turns out to matter.
            float now = Time.time;
            for (int x = -1; x <= 1; x++)
            {
                for (int z = -1; z <= 1; z++)
                {
                    Vector3 offset = new Vector3(x * TileSize, 0f, z * TileSize);
                    KeepAlive(pathfinding, from + offset, now);
                    KeepAlive(pathfinding, to + offset, now);
                }
            }
            float distance = Vector3.Distance(from, to);
            for (float d = TileSize / 2f; d < distance; d += TileSize / 2f)
                KeepAlive(pathfinding, Vector3.Lerp(from, to, d / distance), now);
            _lastKeepAlive = now;

            // A finished path stays right until somebody moves. An unfinished one is retried:
            // the tiles it is waiting for complete a few at a time.
            if (_pathComplete
                && Vector3.Distance(from, _queriedFrom) < RequeryDistance
                && Vector3.Distance(to, _queriedTo) < RequeryDistance)
                return;

            _queriedFrom = from;
            _queriedTo = to;
            _points.Clear();
            _pathComplete = false;

            var settings = pathfinding.GetSettings(Pathfinding.AgentType.Humanoid);
            var filter = new NavMeshQueryFilter { agentTypeID = settings.m_build.agentTypeID, areaMask = settings.m_areaMask };
            Vector3 start = from, end = to;
            if (!pathfinding.SnapToNavMesh(ref start, true, settings) || !pathfinding.SnapToNavMesh(ref end, true, settings))
            {
                _pathState = EventLines.PathNoGround;
                return;
            }

            if (_navPath == null)
                _navPath = new NavMeshPath();
            if (!NavMesh.CalculatePath(start, end, filter, _navPath) || _navPath.status == NavMeshPathStatus.PathInvalid)
            {
                _pathState = EventLines.PathNotFound;
                return;
            }

            Vector3[] corners = _navPath.corners;
            if (corners.Length < 2)
            {
                _pathState = EventLines.PathTooShort;
                return;
            }

            _pathComplete = Utils.DistanceXZ(corners[corners.Length - 1], to) < ArrivedDistance;
            _pathShortBy = Utils.DistanceXZ(corners[corners.Length - 1], to);
            _pathState = _pathComplete ? EventLines.PathComplete : EventLines.PathPartial;

            for (int i = 0; i < corners.Length - 1 && _points.Count < MaxPathPoints; i++)
            {
                Vector3 a = corners[i];
                Vector3 b = corners[i + 1];
                int steps = Mathf.Max(1, Mathf.CeilToInt(Vector3.Distance(a, b) / PathStep));
                for (int s = 0; s < steps; s++)
                    _points.Add(OnGround(Vector3.Lerp(a, b, s / (float)steps)));
            }
            _points.Add(OnGround(corners[corners.Length - 1]));

            _line.positionCount = _points.Count;
            _line.SetPositions(_points.ToArray());
        }

        /// <summary>The ground path's state, when it differs from the one last written for this tracking (verbose only).</summary>
        private void LogPath()
        {
            if (!ModLog.Verbose || (_pathState == _loggedPathState && Generation == _loggedGeneration))
                return;
            _loggedPathState = _pathState;
            _loggedGeneration = Generation;
            Events.GroundPath(_pathState, _points.Count, _pathShortBy);
        }

        /// <summary>
        /// Keeps a nav tile from timing out (30 s unpoked) without making it look stale. The game
        /// rebuilds on pokeTime - buildTime > 5 s, so a plain poke every second means a rebuild
        /// every five. If nobody else has poked the tile since our last tick, the time that passed
        /// is ours alone, and moving buildTime along with pokeTime hides it. A poke from a monster
        /// (pokeTime no longer the value we wrote) is left standing, so the AI still gets its
        /// rebuilds; an unbuilt tile gets a plain poke, which is what gets it built.
        /// </summary>
        private void KeepAlive(Pathfinding pathfinding, Vector3 point, float now)
        {
            var tile = pathfinding.GetNavTile(point, Pathfinding.AgentType.Humanoid);
            if (tile.m_data != null && tile.m_pokeTime == _lastKeepAlive)
                tile.m_buildTime += now - tile.m_pokeTime;

            tile.m_pokeTime = now;
        }

        /// <summary>
        /// Lifts a point up to the terrain where a straight segment between two corners would cut
        /// through a rise. Never lowers it: inside a dungeon or on a bridge the corner height is
        /// the right one and the terrain is somewhere far below.
        /// </summary>
        private static Vector3 OnGround(Vector3 point)
        {
            if (ZoneSystem.instance != null && ZoneSystem.instance.GetGroundHeight(point, out float height) && height > point.y)
                point.y = height;

            point.y += PathLift;
            return point;
        }

        /// <summary>
        /// Player.InCutscene, which also asks the game's video player (CinematicsManager.IsPlaying is not null-safe): an
        /// exception counts as no cutscene, so the guide is never hidden for good by a broken check.
        /// </summary>
        private static bool InCutscene(Player player)
        {
            try
            {
                return player.InCutscene();
            }
            catch (System.Exception)
            {
                return false;
            }
        }

        /// <summary>
        /// The game is between removing the dead body and spawning the player again (Game._RequestRespawn): in its first
        /// frame the body is still the local player but no longer reads as dead.
        /// </summary>
        private static bool WaitingForRespawn()
        {
            Game game = Game.instance;
            return game != null && game.WaitingForRespawn();
        }

        private void OnGUI()
        {
            if (!IsTracking || _guideHidden)
                return;

            if (_hudStyle == null)
            {
                _hudStyle = new GUIStyle(GUI.skin.label)
                {
                    alignment = TextAnchor.UpperCenter,
                    fontSize = 16,
                    fontStyle = FontStyle.Bold
                };
            }

            // Put back afterwards: GUI.matrix is IMGUI's global state, and other plugins draw after this one.
            Matrix4x4 matrix = GUI.matrix;
            GUI.matrix = Matrix4x4.Scale(Vector3.one * EntityListWindow.GuiScale);
            float width = Screen.width / EntityListWindow.GuiScale;
            string text = "Tracking: " + _targetName + " - " + Mathf.RoundToInt(_distance) + "m";

            _hudStyle.normal.textColor = Color.black;
            GUI.Label(new Rect(1f, 71f, width, 30f), text, _hudStyle);
            _hudStyle.normal.textColor = GuideColor;
            GUI.Label(new Rect(0f, 70f, width, 30f), text, _hudStyle);
            GUI.matrix = matrix;
        }

        /// <summary>
        /// A box shaft and a four-sided pyramid head along +Z, one unit long. Vertices are not
        /// shared, so each face carries its own colour: the shader is unlit, and a brightness
        /// baked from the face normal is what makes it read as a solid rather than a silhouette.
        /// </summary>
        private static Mesh BuildArrowMesh()
        {
            var vertices = new List<Vector3>();
            var colors = new List<Color>();
            var triangles = new List<int>();

            const float shaft = 0.07f, head = 0.2f, neck = 0.1f;
            Vector3 shaftCentre = new Vector3(0f, 0f, -0.2f);
            Vector3 headCentre = new Vector3(0f, 0f, 0.25f);

            Vector3[] back = Square(shaft, -0.5f);
            Vector3[] front = Square(shaft, neck);
            AddFace(vertices, colors, triangles, shaftCentre, back[0], back[1], back[2], back[3]);
            for (int i = 0; i < 4; i++)
                AddFace(vertices, colors, triangles, shaftCentre, back[i], back[(i + 1) % 4], front[(i + 1) % 4], front[i]);

            Vector3[] rim = Square(head, neck);
            Vector3 tip = new Vector3(0f, 0f, 0.5f);
            AddFace(vertices, colors, triangles, headCentre, rim[0], rim[1], rim[2], rim[3]);
            for (int i = 0; i < 4; i++)
                AddFace(vertices, colors, triangles, headCentre, rim[i], rim[(i + 1) % 4], tip);

            var mesh = new Mesh { name = "MobTracker_Arrow", hideFlags = HideFlags.HideAndDontSave };
            mesh.SetVertices(vertices);
            mesh.SetColors(colors);
            mesh.SetTriangles(triangles, 0);
            mesh.RecalculateBounds();
            return mesh;
        }

        private static Vector3[] Square(float half, float z)
        {
            return new[]
            {
                new Vector3(-half, -half, z), new Vector3(half, -half, z),
                new Vector3(half, half, z), new Vector3(-half, half, z)
            };
        }

        /// <summary>A triangle or quad fan, shaded by how much its outward normal faces a fixed light from above-front.</summary>
        private static void AddFace(List<Vector3> vertices, List<Color> colors, List<int> triangles, Vector3 solidCentre, params Vector3[] corners)
        {
            Vector3 normal = Vector3.Cross(corners[1] - corners[0], corners[2] - corners[0]).normalized;
            Vector3 faceCentre = Vector3.zero;
            foreach (Vector3 corner in corners)
                faceCentre += corner / corners.Length;
            if (Vector3.Dot(normal, faceCentre - solidCentre) < 0f)
                normal = -normal;

            float light = 0.45f + 0.55f * Mathf.Clamp01(Vector3.Dot(normal, new Vector3(0.3f, 0.9f, -0.3f).normalized) * 0.5f + 0.5f);
            Color color = new Color(GuideColor.r * light, GuideColor.g * light, GuideColor.b * light, 1f);

            int first = vertices.Count;
            foreach (Vector3 corner in corners)
            {
                vertices.Add(corner);
                colors.Add(color);
            }
            for (int i = 1; i < corners.Length - 1; i++)
            {
                triangles.Add(first);
                triangles.Add(first + i);
                triangles.Add(first + i + 1);
            }
        }
    }
}
