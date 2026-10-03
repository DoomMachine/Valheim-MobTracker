using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;

namespace UnityEngine
{
    // Stand-in for the one Unity type ModConfig.cs names (0.7.1).
    public enum KeyCode { None = 0, F7 = 288, F8 = 289 }
}

namespace MobTracker
{
    // Stand-ins for what ModConfig.cs calls outside the files compiled here (0.7.1): Hotkeys.Forget, and Events.Watch's
    // handler on the whole cfg, which only notes each change it is told of.
    internal static class Hotkeys
    {
        public static int Forgot;
        public static void Forget() { Forgot++; }
    }

    internal static class Events
    {
        public static readonly List<string> Told = new List<string>();
        public static void Watch(ConfigFile config) { config.SettingChanged += (sender, args) => Told.Add(args.ChangedSetting.Definition.Key); }
    }

    /// <summary>Every line of every source, as BepInEx hands it out (0.7.1: BepInEx's own warnings too).</summary>
    internal sealed class AllLines : ILogListener
    {
        public readonly List<string> Lines = new List<string>();
        public void LogEvent(object sender, LogEventArgs e) { Lines.Add((e.Source == null ? "?" : e.Source.SourceName) + " " + e.Level + ": " + LogRules.TextOf(e.Data)); }
        public void Dispose() { }
    }

    // Stand-ins for the two game-side pieces LogFile.cs uses; LogFile.cs, LogRules.cs and EventLines.cs are the plugin's own.
    internal static class MobTrackerPlugin
    {
        internal static ManualLogSource Log;
        public const string Version = "0.8.0";
    }

    internal static class LogHost
    {
        public static int Frame() { return 42; }
        public static string GameVersion() { return "test"; }
    }

    /// <summary>What reaches BepInEx's log from MobTracker's source - LogOutput.log's side.</summary>
    internal sealed class Capture : ILogListener
    {
        public readonly List<string> Lines = new List<string>();
        public void LogEvent(object sender, LogEventArgs e)
        {
            if (ReferenceEquals(e.Source, MobTrackerPlugin.Log))
                Lines.Add(e.Level + ": " + LogRules.TextOf(e.Data));
        }
        public void Dispose() { }
    }

    internal sealed class Bomb
    {
        public override string ToString() { throw new InvalidOperationException("no text"); }
    }

    /// <summary>A setting whose text throws while armed, so a save fails after BepInEx has emptied the file (cfg-cut-short).</summary>
    public sealed class Cutter
    {
        public static bool Armed;
        public int N;
    }

    /// <summary>
    /// Each scenario runs in a process of its own (LogFile's state is static, once per game start, as in the game), in a
    /// folder of its own standing in for BepInEx's. Run with no scenario, it runs them all and exits 1 if any failed.
    /// </summary>
    public static class Program
    {
        private static int _failures;
        private static string _dir;
        private static ManualLogSource _bepinex, _unity, _other;
        private static Capture _capture;
        private static AllLines _all;

        private static readonly string[] Scenarios =
        {
            "first-start", "second-start", "verbose-live", "both-off", "foreign", "second-copy", "prev-read-only",
            "log-read-only", "retry-on-only", "cap", "write-fails", "bound-fails", "header-write-fails", "stop", "stop-write-fails",
            "scrub", "verbose-off",
            "cfg-read-only-start", "cfg-read-only-changes", "cfg-reset-once", "cfg-quit-retry", "cfg-start-file",
            "cfg-storm", "cfg-start-locked", "cfg-held-for-writing", "cfg-cut-short", "cfg-read-only-unwatch", "cfg-recovery-twice"
        };

        public static int Main(string[] args)
        {
            if (args.Length == 1)
                return RunAll(args[0]);
            if (args.Length != 2)
            {
                Console.WriteLine("usage: log-harness <empty scratch folder>");
                return 2;
            }
            _dir = Path.Combine(args[0], args[1]);
            Directory.CreateDirectory(_dir);
            MobTrackerPlugin.Log = Logger.CreateLogSource("MobTracker");
            _bepinex = Logger.CreateLogSource("BepInEx");    // BepInEx's own source has this name (ConfigFile's warnings)
            _unity = Logger.CreateLogSource("Unity Log");    // UnityLogSource's name
            _other = Logger.CreateLogSource("OtherMod");
            _capture = new Capture();
            Logger.Listeners.Add(_capture);
            _all = new AllLines();
            Logger.Listeners.Add(_all);
            Console.WriteLine("== " + args[1]);
            typeof(Program).GetMethod(args[1].Replace("-", ""), BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.IgnoreCase).Invoke(null, null);
            return _failures == 0 ? 0 : 1;
        }

        private static int RunAll(string root)
        {
            Directory.CreateDirectory(root);
            if (Directory.EnumerateFileSystemEntries(root).Any())
            {
                Console.WriteLine("the scratch folder is not empty: " + root);
                return 2;
            }
            int failed = 0;
            string exe = Assembly.GetExecutingAssembly().Location;
            foreach (string scenario in Scenarios)
            {
                var info = new ProcessStartInfo(exe, "\"" + root + "\" " + scenario) { UseShellExecute = false, RedirectStandardOutput = true, CreateNoWindow = true };
                using (Process p = Process.Start(info))
                {
                    Console.Write(p.StandardOutput.ReadToEnd());
                    p.WaitForExit();
                    if (p.ExitCode != 0)
                        failed++;
                }
            }
            Console.WriteLine(failed == 0 ? "LOG HARNESS PASSED - " + Scenarios.Length + " scenarios" : "LOG HARNESS FAILED - " + failed + " of " + Scenarios.Length + " scenarios");
            return failed == 0 ? 0 : 1;
        }

        // ---- helpers ----

        private static string LogPath { get { return Path.Combine(_dir, LogFile.FileName); } }
        private static string PrevPath { get { return Path.Combine(_dir, LogFile.PrevName); } }

        private static void Check(string what, bool ok, string detail = "")
        {
            Console.WriteLine((ok ? "  ok    " : "  FAIL  ") + what + (ok || string.IsNullOrEmpty(detail) ? "" : "  ->  " + detail));
            if (!ok)
                _failures++;
        }

        /// <summary>The file's lines, read as a player's editor would while the game holds it (sharing ReadWrite).</summary>
        private static string[] Read(string path)
        {
            if (!File.Exists(path))
                return null;
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var reader = new StreamReader(fs))
                return reader.ReadToEnd().Split(new[] { "\r\n" }, StringSplitOptions.None).Where(l => l.Length > 0).ToArray();
        }

        /// <summary>A line without its "2026-10-02 15:16:03.512 f42 " stamp (checked once, in FirstStart).</summary>
        private static string Body(string line)
        {
            var m = System.Text.RegularExpressions.Regex.Match(line, @"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3} f(\d+|-) ");
            return m.Success ? line.Substring(m.Length) : line;
        }

        private static string[] Bodies(string path)
        {
            string[] lines = Read(path);
            return lines == null ? null : lines.Select(l => l.StartsWith("    ", StringComparison.Ordinal) ? l : Body(l)).ToArray();
        }

        private static string Show(string[] lines)
        {
            return lines == null ? "(no file)" : "[" + string.Join(" | ", lines) + "]";
        }

        private static ConfigFile Cfg(string text)
        {
            string path = Path.Combine(_dir, "com.mobtracker.plugin.cfg");
            if (text != null)
                File.WriteAllText(path, text);
            return new ConfigFile(path, true);
        }

        /// <summary>
        /// The plugin's own order: ConfigSaver.Take, LogFile.Start, then the settings (ModConfig.Bind's stand-in), then
        /// LogFile.Bound and ConfigSaver.Watch.
        /// </summary>
        private static ConfigFile StartGame(string cfgText, Action whileBinding = null)
        {
            ConfigFile cfg = Cfg(cfgText);
            ConfigSaver.Take(cfg);
            LogFile.Start(cfg, _dir, Path.Combine(_dir, "game"));
            cfg.Bind("General", "ListKey", "F7", "stand-in");
            if (whileBinding != null)
                whileBinding();
            LogFile.Bound(cfg);
            ConfigSaver.Watch(cfg);
            return cfg;
        }

        private static string CfgPath { get { return Path.Combine(_dir, "com.mobtracker.plugin.cfg"); } }

        /// <summary>
        /// MobTrackerPlugin.Awake's order with the real settings (0.7.1): ConfigSaver.Take, LogFile.Start, ModConfig.Bind,
        /// LogFile.Bound, ConfigSaver.Watch, on a ConfigFile made as BaseUnityPlugin makes it (saveOnInit false, the plugin's
        /// metadata). With <paramref name="takeFirst"/> false, 0.7.0's order: no Take, no Watch - BepInEx saves at each Bind.
        /// </summary>
        private static ConfigFile StartPlugin(string path, bool takeFirst = true)
        {
            var cfg = new ConfigFile(path, false, new BepInPlugin("com.mobtracker.plugin", "MobTracker", MobTrackerPlugin.Version));
            if (takeFirst)
                ConfigSaver.Take(cfg);
            LogFile.Start(cfg, _dir, Path.Combine(_dir, "game"));
            ModConfig.Bind(cfg);
            LogFile.Bound(cfg);
            if (takeFirst)
                ConfigSaver.Watch(cfg);
            return cfg;
        }

        private static string Try(Action action)
        {
            try
            {
                action();
                return null;
            }
            catch (Exception e)
            {
                return e.GetType().Name + ": " + e.Message;
            }
        }

        /// <summary>A setting's text in the cfg ("Section"'s "Key = value" line), read while nothing holds it.</summary>
        private static string CfgValue(string key)
        {
            foreach (string line in File.ReadAllLines(CfgPath))
                if (line.StartsWith(key + " = ", StringComparison.Ordinal))
                    return line.Substring(key.Length + 3);
            return null;
        }

        private static int Count(string prefix)
        {
            return _capture.Lines.Count(l => l.StartsWith(prefix, StringComparison.Ordinal));
        }

        private static void Seed(string log, string prev)
        {
            if (log != null)
                File.WriteAllText(LogPath, log + "\r\n");
            if (prev != null)
                File.WriteAllText(PrevPath, prev + "\r\n");
        }

        // ---- scenarios ----

        private static void FirstStart()
        {
            StartGame(null, () => MobTrackerPlugin.Log.LogWarning("General.ListStarFilter is 'x': x ignored: not a star category."));
            MobTrackerPlugin.Log.LogInfo("MobTracker 0.8.0 loaded");
            MobTrackerPlugin.Log.LogError("an error");
            ModLog.Event("Track: not written - VerboseLog is off");
            string[] raw = Read(LogPath);
            string[] lines = Bodies(LogPath);
            Check("the first start makes MobTracker.log and no MobTracker-prev.log", raw != null && !File.Exists(PrevPath), Show(raw));
            Check("every entry starts with the date, the time to the millisecond and the frame",
                raw != null && raw.All(l => System.Text.RegularExpressions.Regex.IsMatch(l, @"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3} f42 ")), Show(raw));
            Check("the header, the switches, the warning ModConfig.Bind gave before the file had its settings line, the settings, the error - no Info line",
                lines != null && lines.SequenceEqual(new[]
                {
                    "[File   :MobTracker] MobTracker 0.8.0 - MobTracker.log opened at the game's start; Valheim test; BepInEx 5.4.23.3",
                    "[File   :MobTracker] Logging: ErrorLog on, VerboseLog off - MobTracker.log gets MobTracker's warnings and errors; LogOutput.log gets every MobTracker line as before",
                    "[Warning:MobTracker] General.ListStarFilter is 'x': x ignored: not a star category.",
                    "[File   :MobTracker] Settings: Logging.ErrorLog = 'true', Logging.VerboseLog = 'false', General.ListKey = 'F7'",
                    "[Error  :MobTracker] an error"
                }), Show(lines));
            Check("LogOutput.log's side gets every MobTracker line, the Info one too, and no verbose line",
                _capture.Lines.SequenceEqual(new[] { "Warning: General.ListStarFilter is 'x': x ignored: not a star category.", "Info: MobTracker 0.8.0 loaded", "Error: an error" }),
                string.Join(" | ", _capture.Lines));
            var head = new byte[3];
            using (var fs = new FileStream(LogPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                fs.Read(head, 0, 3);
            Check("UTF-8 without a byte-order mark", !(head.Length == 3 && head[0] == 0xEF && head[1] == 0xBB && head[2] == 0xBF));
        }

        private static void SecondStart()
        {
            Seed("LAST START", "START BEFORE");
            StartGame(null);
            string[] prev = Read(PrevPath);
            string[] log = Bodies(LogPath);
            Check("the last start's lines become MobTracker-prev.log (the start before is gone)", prev != null && prev.SequenceEqual(new[] { "LAST START" }), Show(prev));
            Check("MobTracker.log starts afresh with its header", log != null && log.Length == 3 && log[0].Contains("opened at the game's start"), Show(log));
        }

        private static void VerboseLive()
        {
            StartGame(null);
            MobTrackerPlugin.Log.LogInfo("an Info line with VerboseLog off");
            LogFile.VerboseLog.Value = true;
            Check("VerboseLog turned on sets the flag every verbose site asks", ModLog.Verbose, "");
            ModLog.Event("Track: started - Boar (Boar), no star, 20 m away");
            MobTrackerPlugin.Log.LogInfo("an Info line with VerboseLog on");
            LogFile.ErrorLog.Value = false;
            MobTrackerPlugin.Log.LogWarning("a warning with ErrorLog off, VerboseLog on");
            LogFile.VerboseLog.Value = false;
            MobTrackerPlugin.Log.LogError("an error with both off");
            ModLog.Event("Track: not written");
            string[] lines = Bodies(LogPath).Skip(3).ToArray();
            Check("the switches' notes, the verbose and Info lines while VerboseLog is on, and nothing once both are off",
                lines.SequenceEqual(new[]
                {
                    "[Message:MobTracker] Logging: VerboseLog turned on - MobTracker.log gets every MobTracker line, events included; LogOutput.log gets every MobTracker line as before",
                    "[Info   :MobTracker] Track: started - Boar (Boar), no star, 20 m away",
                    "[Info   :MobTracker] an Info line with VerboseLog on",
                    "[Message:MobTracker] Logging: ErrorLog turned off - MobTracker.log gets every MobTracker line, events included; LogOutput.log gets every MobTracker line as before",
                    "[Warning:MobTracker] a warning with ErrorLog off, VerboseLog on",
                    "[Message:MobTracker] Logging: VerboseLog turned off - MobTracker.log gets only these Logging notes and its closing line until ErrorLog or VerboseLog is turned on; LogOutput.log gets every MobTracker line as before"
                }), Show(lines));
            LogFile.Stop();
            Check("with both off, the closing line still comes at quit, as the last note says",
                Bodies(LogPath).Last() == "[File   :MobTracker] MobTracker.log closed - the game is quitting", Show(Bodies(LogPath)));
            Check("LogOutput.log's side gets the verbose line and the switch notes as well",
                _capture.Lines.Contains("Info: Track: started - Boar (Boar), no star, 20 m away") && _capture.Lines.Count(l => l.StartsWith("Message: Logging:")) == 3
                && !_capture.Lines.Contains("Info: Track: not written"), string.Join(" | ", _capture.Lines));
        }

        private static void BothOff()
        {
            Seed("LAST START", "START BEFORE");
            DateTime logTime = File.GetLastWriteTimeUtc(LogPath), prevTime = File.GetLastWriteTimeUtc(PrevPath);
            StartGame("[Logging]\r\nErrorLog = false\r\nVerboseLog = false\r\n");
            MobTrackerPlugin.Log.LogError("an error with both off from the start");
            Check("both off from the start: neither file is touched",
                Show(Read(LogPath)) == "[LAST START]" && Show(Read(PrevPath)) == "[START BEFORE]"
                && File.GetLastWriteTimeUtc(LogPath) == logTime && File.GetLastWriteTimeUtc(PrevPath) == prevTime, Show(Read(LogPath)) + " " + Show(Read(PrevPath)));
            LogFile.ErrorLog.Value = true;
            MobTrackerPlugin.Log.LogError("an error once ErrorLog is on");
            string[] log = Bodies(LogPath);
            Check("turning ErrorLog on opens the file then, keeping the last start's as MobTracker-prev.log",
                Show(Read(PrevPath)) == "[LAST START]" && log != null && log[0].EndsWith("opened when ErrorLog was turned on; Valheim test; BepInEx 5.4.23.3")
                && log.Last() == "[Error  :MobTracker] an error once ErrorLog is on", Show(log));
            LogFile.ErrorLog.Value = false;
            LogFile.ErrorLog.Value = true;
            Check("off and on again: no second start, MobTracker-prev.log unchanged",
                Show(Read(PrevPath)) == "[LAST START]" && Bodies(LogPath).Count(l => l.Contains("MobTracker.log opened")) == 1, Show(Bodies(LogPath)));
        }

        private static void Foreign()
        {
            string ours = "NullReferenceException: Object reference not set to an instance of an object\nStack trace:\n  at MobTracker.Tracker.LateUpdate () [0x0001b] in <abc>:0";
            StartGame(null, () => _bepinex.LogWarning("Config value of setting \"Tracking.GuideMode\" could not be parsed and will be ignored. Reason: r; Value: Foo"));
            _bepinex.LogWarning("Config value of setting \"Other.Plugin\" could not be parsed - after MobTracker's settings were read");
            _other.LogError("another plugin's error\n  at OtherMod.Thing.Update () [0x0] in <x>:0");
            _unity.LogError("NullReferenceException: vanilla\nStack trace:\nDamageText:LateUpdate ()");
            _unity.LogWarning("a Unity warning");
            for (int i = 0; i < 100; i++)
                _unity.LogError(ours);
            _bepinex.LogError(new InvalidOperationException("a setting's handler threw", null).ToString() + "\n  at MobTracker.ModConfig+<>c.<Bind>b__1 (System.Object sender) [0x0] in <abc>:0");
            _other.LogError(new Bomb());
            _unity.LogError(new Bomb());
            string[] lines = Bodies(LogPath).Skip(2).ToArray();
            Check("BepInEx's warning while MobTracker's settings are read, one error of MobTracker's code of a storm of 100, the handler's error - nothing else",
                lines.SequenceEqual(new[]
                {
                    "[Warning:   BepInEx] Config value of setting \"Tracking.GuideMode\" could not be parsed and will be ignored. Reason: r; Value: Foo",
                    "[File   :MobTracker] Settings: Logging.ErrorLog = 'true', Logging.VerboseLog = 'false', General.ListKey = 'F7'",
                    "[Error  : Unity Log] NullReferenceException: Object reference not set to an instance of an object",
                    "    Stack trace:",
                    "      at MobTracker.Tracker.LateUpdate () [0x0001b] in <abc>:0",
                    "[Error  :   BepInEx] System.InvalidOperationException: a setting's handler threw",
                    "      at MobTracker.ModConfig+<>c.<Bind>b__1 (System.Object sender) [0x0] in <abc>:0"
                }), Show(lines));
            Check("a line whose text cannot be read does not break the file", LogFileIsOpen(), "");
        }

        private static void SecondCopy()
        {
            Seed("FIRST COPY'S LINES", "START BEFORE");
            using (new FileStream(LogPath, FileMode.Open, FileAccess.ReadWrite, FileShare.Read))   // as the first copy holds it
            {
                StartGame(null);
                MobTrackerPlugin.Log.LogError("an error in the second copy");
            }
            Check("a second copy of the game cannot take the file and touches neither", Show(Read(LogPath)) == "[FIRST COPY'S LINES]" && Show(Read(PrevPath)) == "[START BEFORE]",
                Show(Read(LogPath)) + " " + Show(Read(PrevPath)));
            Check("it says so once in LogOutput.log, with the exception's type only",
                _capture.Lines.Count(l => l.StartsWith("Warning: MobTracker.log could not be opened (IOException;", StringComparison.Ordinal)) == 1, string.Join(" | ", _capture.Lines));
            Check("and its errors still reach LogOutput.log", _capture.Lines.Contains("Error: an error in the second copy"), "");
            Check("no path in what it says", !_capture.Lines.Any(l => l.Contains(_dir)), string.Join(" | ", _capture.Lines));
        }

        private static void PrevReadOnly()
        {
            Seed("LAST START", "START BEFORE");
            File.SetAttributes(PrevPath, FileAttributes.ReadOnly);
            try
            {
                StartGame(null);
                string[] log = Bodies(LogPath);
                Check("MobTracker-prev.log read-only: the last start's lines stay in MobTracker.log, under a line saying so",
                    Show(Read(PrevPath)) == "[START BEFORE]" && log != null && log[0] == "LAST START"
                    && log[1] == "[File   :MobTracker] === MobTracker-prev.log could not be written (UnauthorizedAccessException), so the last game start's lines are kept above this one ==="
                    && log[2].Contains("opened at the game's start"), Show(log));
            }
            finally
            {
                File.SetAttributes(PrevPath, FileAttributes.Normal);
            }
        }

        private static void LogReadOnly()
        {
            Seed("LAST START", "START BEFORE");
            File.SetAttributes(LogPath, FileAttributes.ReadOnly);
            try
            {
                StartGame(null);
                Check("MobTracker.log read-only: no file is written and nothing is touched", Show(Read(LogPath)) == "[LAST START]" && Show(Read(PrevPath)) == "[START BEFORE]", "");
                Check("an UnauthorizedAccessException is caught like an IOException, and said",
                    _capture.Lines.Any(l => l.StartsWith("Warning: MobTracker.log could not be opened (UnauthorizedAccessException;", StringComparison.Ordinal)), string.Join(" | ", _capture.Lines));
            }
            finally
            {
                File.SetAttributes(LogPath, FileAttributes.Normal);
            }
            LogFile.ErrorLog.Value = false;
            LogFile.ErrorLog.Value = true;
            Check("a failed open is tried again when a switch is turned on", Bodies(LogPath).Any(l => l.Contains("opened when ErrorLog was turned on")), Show(Bodies(LogPath)));
        }

        private static void RetryOnOnly()
        {
            // Both on from the start, and the open fails; then the file could be opened, but a switch is only turned off.
            Seed("LAST START", "START BEFORE");
            File.SetAttributes(LogPath, FileAttributes.ReadOnly);
            try
            {
                StartGame("[Logging]\r\nErrorLog = true\r\nVerboseLog = true\r\n");
            }
            finally
            {
                File.SetAttributes(LogPath, FileAttributes.Normal);
            }
            LogFile.VerboseLog.Value = false;
            LogFile.ErrorLog.Value = false;
            Check("a switch turned off does not try the failed open again: nothing is touched",
                Show(Read(LogPath)) == "[LAST START]" && Show(Read(PrevPath)) == "[START BEFORE]", Show(Read(LogPath)) + " " + Show(Read(PrevPath)));
            Check("and LogOutput.log still gets both switch notes",
                _capture.Lines.Count(l => l.StartsWith("Message: Logging: VerboseLog turned off", StringComparison.Ordinal)) == 1
                && _capture.Lines.Count(l => l.StartsWith("Message: Logging: ErrorLog turned off", StringComparison.Ordinal)) == 1, string.Join(" | ", _capture.Lines));
            LogFile.VerboseLog.Value = true;
            string[] log = Bodies(LogPath);
            Check("the next switch turned on tries it again, named after that switch, keeping the last start as MobTracker-prev.log",
                Show(Read(PrevPath)) == "[LAST START]" && log != null && log[0].EndsWith("opened when VerboseLog was turned on; Valheim test; BepInEx 5.4.23.3")
                && log.Count(l => l.Contains("MobTracker.log opened")) == 1, Show(log));
        }

        private static void Cap()
        {
            StartGame(null);
            string text = new string('x', 1000);
            for (int i = 0; i < 6000; i++)
                MobTrackerPlugin.Log.LogError(text);
            long size = new FileInfo(LogPath).Length;
            string[] lines = Bodies(LogPath);
            Check("the file stops at 5 MB with one last line", size <= LogRules.Cap + 400 && size > LogRules.Cap - 2000
                && lines.Last() == "[File   :MobTracker] " + EventLines.CapReached(LogRules.Cap), size + " bytes; last: " + lines.Last());
            int before = _capture.Lines.Count;
            LogFile.ReportNotice();
            LogFile.ReportNotice();
            Check("LogOutput.log is told once", _capture.Lines.Count == before + 1 && _capture.Lines.Last() == "Warning: " + EventLines.CapReached(LogRules.Cap), _capture.Lines.Last());
            MobTrackerPlugin.Log.LogError("after the cap");
            Check("nothing more is written after it", new FileInfo(LogPath).Length == size, "");
        }

        private static void WriteFails()
        {
            StartGame(null);
            // The writer's stream is closed under it, so the next line cannot be written.
            object tee = typeof(LogFile).GetField("_tee", BindingFlags.NonPublic | BindingFlags.Static).GetValue(null);
            var writer = (StreamWriter)typeof(LogFile).GetField("_writer", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(tee);
            writer.BaseStream.Dispose();
            bool threw = false;
            try
            {
                MobTrackerPlugin.Log.LogError("this line cannot be written");
                _other.LogInfo("another plugin's line after it");
            }
            catch (Exception)
            {
                threw = true;
            }
            Check("a line that cannot be written throws into no plugin's log call", !threw, "");
            Check("the file is shut", !LogFileIsOpen(), "");
            LogFile.ReportNotice();
            LogFile.ReportNotice();
            Check("LogOutput.log is told once, with the exception's type only",
                _capture.Lines.Count(l => l.StartsWith("Warning: MobTracker.log could not be written (ObjectDisposedException)", StringComparison.Ordinal)) == 1,
                string.Join(" | ", _capture.Lines));
        }

        private static void BoundFails()
        {
            // The writer's stream is closed between LogFile.Start and LogFile.Bound - while the settings are read - so the
            // settings line Bound writes cannot be written. Bound runs in Awake: a throw out of it would drop the plugin.
            string threw = null;
            try
            {
                StartGame(null, () =>
                {
                    object t = typeof(LogFile).GetField("_tee", BindingFlags.NonPublic | BindingFlags.Static).GetValue(null);
                    ((StreamWriter)typeof(LogFile).GetField("_writer", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(t)).BaseStream.Dispose();
                });
            }
            catch (Exception e)
            {
                threw = e.GetType().FullName;
            }
            Check("a settings line Bound cannot write throws nothing out of it (Awake goes on)", threw == null, threw ?? "");
            Check("the file is shut", !LogFileIsOpen(), "");
            bool later = false;
            try
            {
                MobTrackerPlugin.Log.LogError("an error after the file shut");
            }
            catch (Exception)
            {
                later = true;
            }
            LogFile.ReportNotice();
            LogFile.ReportNotice();
            Check("LogOutput.log is told once, with the exception's type only, and still gets the lines after it",
                !later && _capture.Lines.Count(l => l.StartsWith("Warning: MobTracker.log could not be written (ObjectDisposedException)", StringComparison.Ordinal)) == 1
                && _capture.Lines.Contains("Error: an error after the file shut"), string.Join(" | ", _capture.Lines));
        }

        private static void HeaderWriteFails()
        {
            // Open takes the file, but its first line cannot be written: another handle holds a byte-range lock on all of
            // it, as a full disk would fail the write. Open's catch shuts what it holds - the writer, whose own flush then
            // fails again - and nothing may leave LogFile.Start, first in Awake.
            Seed("LAST START", "START BEFORE");
            string threw = null;
            using (var holder = new FileStream(LogPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                holder.Lock(0, long.MaxValue);
                try
                {
                    StartGame(null);
                    MobTrackerPlugin.Log.LogError("an error after the failed open");
                }
                catch (Exception e)
                {
                    threw = e.GetType().FullName;
                }
                try
                {
                    holder.Unlock(0, long.MaxValue);
                }
                catch (Exception)
                {
                    // Closed with the handle either way.
                }
            }
            Check("a header that cannot be written throws nothing out of LogFile.Start (Awake goes on)", threw == null, threw ?? "");
            Check("no file is left open", !LogFileIsOpen(), "");
            Check("LogOutput.log is told once that the file could not be opened, by type only, and gets the lines after it",
                _capture.Lines.Count(l => l.StartsWith("Warning: MobTracker.log could not be opened (IOException;", StringComparison.Ordinal)) == 1
                && _capture.Lines.Contains("Error: an error after the failed open"), string.Join(" | ", _capture.Lines));
            string[] log = Read(LogPath);
            Check("the last start's lines are still in MobTracker.log", log != null && log.Length >= 1 && log[0] == "LAST START", Show(log));
        }

        private static void Stop()
        {
            StartGame(null);
            LogFile.Stop();
            Check("Stop takes the listener off BepInEx's log", !Logger.Listeners.Any(l => l is LogFile), "");
            Check("and writes a last line", Bodies(LogPath).Last() == "[File   :MobTracker] MobTracker.log closed - the game is quitting", Show(Bodies(LogPath)));
            MobTrackerPlugin.Log.LogError("after Stop");
            Check("nothing after it", !Bodies(LogPath).Any(l => l.Contains("after Stop")), "");
        }

        private static void StopWriteFails()
        {
            // The closing line cannot be written at quit (the stream is closed under the writer): nothing leaves Stop,
            // which runs in OnDestroy, the listener is off and the file is let go.
            StartGame(null);
            object tee = typeof(LogFile).GetField("_tee", BindingFlags.NonPublic | BindingFlags.Static).GetValue(null);
            var writer = (StreamWriter)typeof(LogFile).GetField("_writer", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(tee);
            writer.BaseStream.Dispose();
            string threw = null;
            try
            {
                LogFile.Stop();
            }
            catch (Exception e)
            {
                threw = e.GetType().FullName;
            }
            Check("a closing line that cannot be written throws nothing out of Stop (OnDestroy)", threw == null, threw ?? "");
            Check("the listener is off BepInEx's log", !Logger.Listeners.Any(l => l is LogFile), "");
            Check("the writer is let go", typeof(LogFile).GetField("_writer", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(tee) == null, "");
        }

        private static void Scrub()
        {
            StartGame(null);
            string game = Path.Combine(_dir, "game");
            string user = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            MobTrackerPlugin.Log.LogWarning("a sample line: Sharing violation on path " + game + "\\BepInEx\\config\\com.mobtracker.plugin.cfg");
            MobTrackerPlugin.Log.LogWarning("a file under " + user + "\\AppData");
            string[] lines = Bodies(LogPath);
            Check("the game's folder is written as <game>", lines.Contains("[Warning:MobTracker] a sample line: Sharing violation on path <game>\\BepInEx\\config\\com.mobtracker.plugin.cfg"), Show(lines));
            Check("the Windows user folder as <user>", lines.Contains("[Warning:MobTracker] a file under <user>\\AppData"), Show(lines));
            Check("LogOutput.log's side is as the game wrote it", _capture.Lines.Any(l => l.Contains(game)), "");
        }

        private static void VerboseOff()
        {
            StartGame(null);
            for (int i = 0; i < 10; i++)
                ModLog.Event("Track: verbose line " + i);
            Check("with VerboseLog off a verbose line reaches neither log", !_capture.Lines.Any(l => l.Contains("verbose line")) && !Bodies(LogPath).Any(l => l.Contains("verbose line")), "");
        }

        // ---- the cfg (0.7.1): ConfigSaver with the real settings ----

        private static void CfgReadOnlyStart()
        {
            const string text = "[Alerts]\r\n\r\nWatchlist = Troll\r\n\r\n[Tracking]\r\n\r\nArrowSize = 9\r\n";
            File.WriteAllText(CfgPath, text);
            File.SetAttributes(CfgPath, FileAttributes.ReadOnly);
            ConfigFile cfg = null;
            string thrown;
            try
            {
                thrown = Try(() => cfg = StartPlugin(CfgPath));
                Check("a read-only cfg at the start: nothing throws out of Awake's order", thrown == null, thrown);
                Check("every setting is bound, the stored values read and an out-of-range one moved into its range",
                    cfg != null && cfg.Count == 14 && ModConfig.Watchlist.Contains("Troll") && ModConfig.ArrowSize.Value == 3f, cfg == null ? "" : cfg.Count + " bound");
                Check("the cfg is not touched", File.ReadAllText(CfgPath) == text, File.ReadAllText(CfgPath));
                Check("one warning, at the game's start, naming the exception's type only",
                    Count("Warning: Settings could not be saved") == 1 && _capture.Lines.Contains("Warning: " + EventLines.CfgNotSaved("at the game's start", "UnauthorizedAccessException")),
                    string.Join(" | ", _capture.Lines));
                Check("and in MobTracker.log", Bodies(LogPath).Contains("[Warning:MobTracker] " + EventLines.CfgNotSaved("at the game's start", "UnauthorizedAccessException")), Show(Bodies(LogPath)));
                Check("no 'could not be parsed' warning from BepInEx (a save failing inside a Bind)", !_all.Lines.Any(l => l.Contains("could not be parsed")), string.Join(" | ", _all.Lines));
                thrown = Try(() => ModConfig.ToggleWatch("Serpent"));
                Check("a change after it: no throw, the parsed watchlist follows, no second warning", thrown == null && ModConfig.Watchlist.Contains("Serpent")
                    && Count("Warning: Settings could not be saved") == 1, thrown);
            }
            finally
            {
                File.SetAttributes(CfgPath, FileAttributes.Normal);
            }
        }

        private static void CfgReadOnlyChanges()
        {
            StartPlugin(CfgPath);
            Check("a writable start makes the cfg, and says nothing about it", File.Exists(CfgPath) && Count("Warning: Settings") == 0, string.Join(" | ", _capture.Lines));
            File.SetAttributes(CfgPath, FileAttributes.ReadOnly);
            string before = File.ReadAllText(CfgPath);
            var thrown = new List<string>();
            try
            {
                // As the window writes (EntityListWindow: Value), then as ConfigurationManager does (BoxedValue).
                thrown.Add(Try(() => ModConfig.ToggleWatch("Troll")));
                thrown.Add(Try(() => ModConfig.ListStarsText.Value = StarSets.Format(StarSets.Toggle(ModConfig.ListStars, StarFilter.OneStar))));
                thrown.Add(Try(() => ModConfig.AutoTrack.Value = false));
                thrown.Add(Try(() => ModConfig.AlertStarsText.BoxedValue = "TwoStars"));
                thrown.Add(Try(() => LogFile.VerboseLog.BoxedValue = true));
                thrown.Add(Try(() => ModConfig.ListKey.BoxedValue = UnityEngine.KeyCode.F8));
                Check("no write throws while the cfg is read-only - the window's or ConfigurationManager's", thrown.All(t => t == null), string.Join(" | ", thrown));
                Check("each parsed view follows its setting", ModConfig.Watchlist.Contains("Troll") && ModConfig.ListStars == StarSet.OneStar
                    && ModConfig.AlertStars == StarSet.TwoStars && ModConfig.AlertStarsRevision == 1, ModConfig.ListStars + " " + ModConfig.AlertStars + " " + ModConfig.AlertStarsRevision);
                Check("VerboseLog takes effect, with its note", ModLog.Verbose && Count("Message: Logging: VerboseLog turned on") == 1, string.Join(" | ", _capture.Lines));
                Check("a new ListKey is tried afresh", Hotkeys.Forgot == 1, Hotkeys.Forgot.ToString());
                Check("the handler on the whole cfg is told of every change", Events.Told.Count == 6, string.Join(",", Events.Told));
                Check("the file is not touched, and the failure is said once", File.ReadAllText(CfgPath) == before
                    && Count("Warning: Settings could not be saved to com.mobtracker.plugin.cfg after a change (UnauthorizedAccessException;") == 1
                    && Count("Warning: Settings could not be saved") == 1, string.Join(" | ", _capture.Lines));
            }
            finally
            {
                File.SetAttributes(CfgPath, FileAttributes.Normal);
            }
            ModConfig.Guide.Value = GuideMode.GroundPath;
            Check("the next change once it can be written: saved, said once, at Info", Count("Info: " + EventLines.CfgSavedAgain("after a change")) == 1, string.Join(" | ", _capture.Lines));
            Check("and the file has every change made while it could not be written",
                CfgValue("Watchlist") == "Troll" && CfgValue("ListStarFilter") == "OneStar" && CfgValue("AutoTrack") == "false" && CfgValue("AlertStarFilter") == "TwoStars"
                && CfgValue("VerboseLog") == "true" && CfgValue("ListKey") == "F8" && CfgValue("GuideMode") == "GroundPath", File.ReadAllText(CfgPath));
        }

        private static void CfgResetOnce()
        {
            ConfigFile cfg = StartPlugin(CfgPath);
            ModConfig.ToggleWatch("Troll");
            ModConfig.ListStarsText.Value = "OneStar";
            ModConfig.AlertStarsText.Value = "TwoStars";
            // Added after ConfigSaver's handler, so it reads the file after the saver had its turn at each of the reset's writes.
            var seen = new List<string>();
            cfg.SettingChanged += (sender, args) => seen.Add(CfgValue("Watchlist"));
            ModConfig.ResetSession();
            Check("the session reset's writes are not saved one by one", seen.Count == 3 && seen.All(v => v == "Troll"), string.Join(",", seen));
            Check("it saves once after them", CfgValue("Watchlist") == "" && CfgValue("ListStarFilter") == "All" && CfgValue("AlertStarFilter") == "All", File.ReadAllText(CfgPath));
            Check("the views follow, and a change is saved as it happens again after it", ModConfig.Watchlist.Count == 0 && ModConfig.ListStars == StarSet.All
                && ModConfig.AlertStars == StarSet.All && ConfigSaver.Each, ConfigSaver.Each.ToString());
            ModConfig.ToggleWatch("Boar");
            File.SetAttributes(CfgPath, FileAttributes.ReadOnly);
            try
            {
                string thrown = Try(ModConfig.ResetSession);
                Check("a read-only cfg: the reset throws nothing, its views follow, one warning after the reset", thrown == null && ModConfig.Watchlist.Count == 0
                    && Count("Warning: " + EventLines.CfgNotSaved("after the session reset", "UnauthorizedAccessException")) == 1, thrown);
            }
            finally
            {
                File.SetAttributes(CfgPath, FileAttributes.Normal);
            }
        }

        private static void CfgQuitRetry()
        {
            StartPlugin(CfgPath);
            File.SetAttributes(CfgPath, FileAttributes.ReadOnly);
            try
            {
                ModConfig.AutoTrack.Value = false;
            }
            finally
            {
                File.SetAttributes(CfgPath, FileAttributes.Normal);
            }
            Check("a change while read-only is not in the file", CfgValue("AutoTrack") == "true", CfgValue("AutoTrack"));
            ConfigSaver.Stop();
            Check("at quit, once the file can be written, it is saved, and said", CfgValue("AutoTrack") == "false"
                && Count("Info: " + EventLines.CfgSavedAgain("as the game quits")) == 1, string.Join(" | ", _capture.Lines));
            File.SetAttributes(CfgPath, FileAttributes.ReadOnly);
            try
            {
                ConfigSaver.Stop();
                Check("a quit with no failed save tries nothing (no warning on a read-only file)", Count("Warning: Settings could not be saved") == 1, string.Join(" | ", _capture.Lines));
            }
            finally
            {
                File.SetAttributes(CfgPath, FileAttributes.Normal);
            }
        }

        private static void CfgStartFile()
        {
            // 0.7.0's order (BepInEx saves at each Bind) in a folder of its own, then 0.7.1's: the same file either way.
            const string text = "[Alerts]\r\n\r\nWatchlist = Troll\r\nGone = 1\r\n\r\n[Tracking]\r\n\r\nArrowSize = 9\r\n\r\n[Zzz]\r\n\r\nOther = x\r\n";
            string old = Path.Combine(_dir, "old");
            Directory.CreateDirectory(old);
            File.WriteAllText(Path.Combine(old, "com.mobtracker.plugin.cfg"), text);
            StartPlugin(Path.Combine(old, "com.mobtracker.plugin.cfg"), false);
            File.WriteAllText(CfgPath, text);
            StartPlugin(CfgPath);
            string mine = File.ReadAllText(CfgPath);
            Check("the start writes the file BepInEx's per-Bind saves would have left, byte for byte", mine == File.ReadAllText(Path.Combine(old, "com.mobtracker.plugin.cfg")), mine);
            Check("every setting with its description, a value moved into its range, keys MobTracker no longer has kept",
                Regex.Matches(mine, "^## ", RegexOptions.Multiline).Count >= 14 && CfgValue("ArrowSize") == "3" && CfgValue("Gone") == "1" && CfgValue("Other") == "x"
                && CfgValue("Watchlist") == "Troll", mine);
        }

        /// <summary>
        /// ConfigurationManager's text box writes at every keystroke: 500 changes on a read-only cfg each take effect, with
        /// one warning for them all and nothing thrown.
        /// </summary>
        private static void CfgStorm()
        {
            StartPlugin(CfgPath);
            File.SetAttributes(CfgPath, FileAttributes.ReadOnly);
            try
            {
                int told = Events.Told.Count, revision = ModConfig.AlertStarsRevision;
                var thrown = new List<string>();
                for (int i = 0; i < 500; i++)
                {
                    string text = i % 2 == 0 ? "OneStar" : "TwoStars";
                    string t = Try(() => ModConfig.AlertStarsText.BoxedValue = text);
                    if (t != null)
                        thrown.Add(t);
                }
                Check("500 changes on a read-only cfg: none throws", thrown.Count == 0, string.Join(" | ", thrown.Take(3)));
                Check("each is handled: the Alerts: row's revision and the handler on the whole cfg count all 500, and the view holds the last",
                    ModConfig.AlertStarsRevision == revision + 500 && Events.Told.Count == told + 500 && ModConfig.AlertStars == StarSet.TwoStars,
                    (ModConfig.AlertStarsRevision - revision) + " " + (Events.Told.Count - told) + " " + ModConfig.AlertStars);
                Check("one warning for them all", Count("Warning: Settings could not be saved") == 1, string.Join(" | ", _capture.Lines));
                Check("and one in MobTracker.log", Bodies(LogPath).Count(l => l.Contains("Settings could not be saved")) == 1, Show(Bodies(LogPath)));
            }
            finally
            {
                File.SetAttributes(CfgPath, FileAttributes.Normal);
            }
        }

        /// <summary>
        /// A cfg another program has open when the game starts, sharing reading only: BepInEx reads it, every setting is
        /// bound, and the start's save fails with one IOException warning that names no path.
        /// </summary>
        private static void CfgStartLocked()
        {
            File.WriteAllText(CfgPath, "[Alerts]\r\n\r\nWatchlist = Troll\r\n");
            ConfigFile cfg = null;
            string thrown;
            using (new FileStream(CfgPath, FileMode.Open, FileAccess.Read, FileShare.Read))
                thrown = Try(() => cfg = StartPlugin(CfgPath));
            Check("a cfg another program reads, sharing reading only, at the start: nothing throws, every setting is bound and read",
                thrown == null && cfg != null && cfg.Count == 14 && ModConfig.Watchlist.Contains("Troll"), thrown ?? (cfg == null ? "" : cfg.Count + " bound"));
            string[] warnings = _capture.Lines.Where(l => l.StartsWith("Warning: Settings could not be saved", StringComparison.Ordinal)).ToArray();
            Check("one warning, an IOException, by type only - no path", warnings.Length == 1
                && warnings[0] == "Warning: " + EventLines.CfgNotSaved("at the game's start", "IOException") && !warnings[0].Contains(_dir), Show(warnings));
        }

        /// <summary>
        /// A known limit: a cfg another program holds open for writing - or for reading, sharing nothing - when the game
        /// starts makes BepInEx's ConfigFile constructor throw, before any MobTracker code runs. Rewrite this only if
        /// BepInEx changes.
        /// </summary>
        private static void CfgHeldForWriting()
        {
            File.WriteAllText(CfgPath, "[Alerts]\r\n\r\nWatchlist = Troll\r\n");
            foreach (FileShare share in new[] { FileShare.Read, FileShare.None })
            {
                FileAccess access = share == FileShare.Read ? FileAccess.ReadWrite : FileAccess.Read;
                string thrown;
                using (new FileStream(CfgPath, FileMode.Open, access, share))
                    thrown = Try(() => new ConfigFile(CfgPath, false, new BepInPlugin("com.mobtracker.plugin", "MobTracker", MobTrackerPlugin.Version)));
                Check("a cfg another program holds (" + access + ", sharing " + share + ") at the start: BepInEx's ConfigFile constructor throws an IOException",
                    thrown != null && thrown.StartsWith("IOException:", StringComparison.Ordinal), thrown ?? "no throw");
            }
        }

        /// <summary>
        /// BepInEx's Save empties the file as it opens it: a save that fails after that (a full disk, say - here a setting
        /// whose text throws) leaves it cut short, and the next save that works - at a change, or at the quit - writes it
        /// whole again.
        /// </summary>
        private static void CfgCutShort()
        {
            TomlTypeConverter.AddConverter(typeof(Cutter), new TypeConverter
            {
                ConvertToString = (o, t) => { if (Cutter.Armed) throw new IOException("Disk full (simulated)"); return ((Cutter)o).N.ToString(); },
                ConvertToObject = (s, t) => new Cutter { N = int.Parse(s) }
            });
            ConfigFile cfg = StartPlugin(CfgPath);
            cfg.Bind("Zz", "Cutter", new Cutter { N = 1 }, "a setting whose text throws while armed");
            ModConfig.ToggleWatch("Troll");
            int whole = File.ReadAllText(CfgPath).Length;
            Cutter.Armed = true;
            ModConfig.Guide.Value = GuideMode.GroundPath;
            Cutter.Armed = false;
            Check("a save that fails after the file is opened leaves it cut short, and says so once", CfgValue("Watchlist") == null
                && File.ReadAllText(CfgPath).Length < whole / 4 && Count("Warning: " + EventLines.CfgNotSaved("after a change", "IOException")) == 1,
                File.ReadAllText(CfgPath).Length + " of " + whole + " | " + string.Join(" | ", _capture.Lines));
            ModConfig.AutoTrack.Value = false;
            Check("the next save that works writes the whole file again, with every change", CfgValue("Watchlist") == "Troll" && CfgValue("GuideMode") == "GroundPath"
                && CfgValue("AutoTrack") == "false" && CfgValue("Cutter") == "1" && Count("Info: " + EventLines.CfgSavedAgain("after a change")) == 1,
                File.ReadAllText(CfgPath));
            Cutter.Armed = true;
            ModConfig.Guide.Value = GuideMode.Arrow;
            Cutter.Armed = false;
            Check("cut short again by the next failed save", CfgValue("Watchlist") == null, File.ReadAllText(CfgPath));
            ConfigSaver.Stop();
            Check("a file cut short by the last save is written whole at the quit", CfgValue("Watchlist") == "Troll" && CfgValue("GuideMode") == "Arrow"
                && Count("Info: " + EventLines.CfgSavedAgain("as the game quits")) == 1, File.ReadAllText(CfgPath));
        }

        /// <summary>
        /// Writes back to a default with the cfg read-only - Unwatch of the last type, the last star taken off: the views
        /// follow, so the session reset (which skips settings at their default) finds nothing left behind, however often it
        /// runs, and a later Watch gives that type only, not the unwatched one with it.
        /// </summary>
        private static void CfgReadOnlyUnwatch()
        {
            StartPlugin(CfgPath);
            ModConfig.ToggleWatch("Troll");
            ModConfig.ListStarsText.Value = "OneStar";
            File.SetAttributes(CfgPath, FileAttributes.ReadOnly);
            try
            {
                var thrown = new List<string>();
                thrown.Add(Try(() => ModConfig.ToggleWatch("Troll")));
                thrown.Add(Try(() => ModConfig.ListStarsText.Value = StarSets.Format(StarSets.Toggle(ModConfig.ListStars, StarFilter.OneStar))));
                Check("written back to their defaults on a read-only cfg: nothing throws, and the views follow", thrown.All(t => t == null)
                    && ModConfig.WatchlistEntry.Value == "" && ModConfig.Watchlist.Count == 0 && ModConfig.ListStarsText.Value == "All" && ModConfig.ListStars == StarSet.All,
                    string.Join(" | ", thrown) + " " + ModConfig.ListStarsText.Value + " / " + ModConfig.ListStars);
                int lines = _capture.Lines.Count;
                thrown.Add(Try(ModConfig.ResetSession));
                thrown.Add(Try(ModConfig.ResetSession));
                Check("two session resets find nothing to set back: nothing thrown, nothing said, nothing left behind", thrown.All(t => t == null)
                    && _capture.Lines.Count == lines && ModConfig.Watchlist.Count == 0 && ModConfig.ListStars == StarSet.All, Show(_capture.Lines.Skip(lines).ToArray()));
                thrown.Add(Try(() => ModConfig.ToggleWatch("Serpent")));
                Check("a later Watch gives that type only, not the unwatched one with it", thrown.All(t => t == null) && ModConfig.WatchlistEntry.Value == "Serpent"
                    && ModConfig.Watchlist.Count == 1, ModConfig.WatchlistEntry.Value);
            }
            finally
            {
                File.SetAttributes(CfgPath, FileAttributes.Normal);
            }
        }

        /// <summary>
        /// After a failed save and the save that works again, later saves that work say nothing more, nor does the quit:
        /// "saved again" comes once per run of failures.
        /// </summary>
        private static void CfgRecoveryTwice()
        {
            StartPlugin(CfgPath);
            File.SetAttributes(CfgPath, FileAttributes.ReadOnly);
            try
            {
                ModConfig.AutoTrack.Value = false;
            }
            finally
            {
                File.SetAttributes(CfgPath, FileAttributes.Normal);
            }
            ModConfig.Guide.Value = GuideMode.GroundPath;
            ModConfig.AutoTrack.Value = true;
            ModConfig.Guide.Value = GuideMode.Arrow;
            Check("one failure, one recovery line, then silence at later saves that work", Count("Warning: Settings could not be saved") == 1
                && Count("Info: Settings saved to com.mobtracker.plugin.cfg again") == 1 && CfgValue("GuideMode") == "Arrow", string.Join(" | ", _capture.Lines));
            ConfigSaver.Stop();
            Check("and no retry line at quit after a recovery", Count("Info: Settings saved to com.mobtracker.plugin.cfg again") == 1, string.Join(" | ", _capture.Lines));
        }

        private static bool LogFileIsOpen()
        {
            object tee = typeof(LogFile).GetField("_tee", BindingFlags.NonPublic | BindingFlags.Static).GetValue(null);
            return tee != null && typeof(LogFile).GetField("_writer", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(tee) != null;
        }
    }
}
