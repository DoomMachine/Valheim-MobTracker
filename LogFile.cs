using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using BepInEx.Configuration;
using BepInEx.Logging;

namespace MobTracker
{
    /// <summary>
    /// VerboseLog as a plain field - read at every verbose site before anything is put together - and the one way a
    /// verbose line is written: Info, which BepInEx's default disk log levels write to LogOutput.log, as they write every
    /// other MobTracker line. Asked again here, so a site that forgot to ask writes nothing while VerboseLog is off.
    /// </summary>
    internal static class ModLog
    {
        public static bool Verbose;

        public static void Event(string line)
        {
            if (Verbose)
                MobTrackerPlugin.Log.LogInfo(line);
        }
    }

    /// <summary>
    /// BepInEx/MobTracker.log (0.7.0): a copy, with date, time and frame, of what MobTracker's own log source writes - its
    /// warnings and errors with ErrorLog on, every line with VerboseLog on - plus the errors of MobTracker's code that
    /// reach BepInEx from elsewhere: an exception nobody caught (Unity's log, "Unity Log"), one thrown by a setting's
    /// change handler (BepInEx's own source), and BepInEx's warning about an unreadable value while MobTracker's settings
    /// are read. LogOutput.log and Player.log are not touched: BepInEx still writes every MobTracker line to them.
    ///
    /// A listener on BepInEx's logger runs inside every plugin's log call, on its thread, and BepInEx catches nothing
    /// around it: everything here is caught, nothing here logs (a failure is said by LogObserver, once, after the file is
    /// shut), and a line not MobTracker's is turned away before any work.
    ///
    /// Opened once per game start - at the start when a switch is on, else when one is first turned on - and never again
    /// after that (a second open would move this start's own lines to MobTracker-prev.log). The open takes the file
    /// first, so a second copy of the game fails there and touches nothing; then the last start's lines are copied to
    /// MobTracker-prev.log, and only if that worked is MobTracker.log emptied - otherwise they stay, under a line saying so.
    /// Free of game types (LogHost reads the frame and the game's version), so tools\log-harness compiles this file as
    /// it is.
    /// </summary>
    internal sealed class LogFile : ILogListener
    {
        public const string FileName = "MobTracker.log";
        public const string PrevName = "MobTracker-prev.log";
        private const string FileTag = "[File   :MobTracker] ";

        public static ConfigEntry<bool> ErrorLog;
        public static ConfigEntry<bool> VerboseLog;

        private static LogFile _tee;
        private static string _folder;
        private static string _gameFolder;
        private static string _userFolder;
        private static bool _opened;
        private static bool _binding;
        private static int _mainThread;
        // Said once in LogOutput.log by LogObserver (ReportNotice): why the file stopped.
        private static string _notice;
        private static readonly Stopwatch Clock = new Stopwatch();

        private readonly object _gate = new object();
        private readonly RepeatLimiter _repeats = new RepeatLimiter();
        private StreamWriter _writer;
        private long _written;

        /// <summary>
        /// First in MobTrackerPlugin.Awake, before ModConfig.Bind, whose own warnings (an unreadable star filter) must reach
        /// the file: binds the two switches, opens the file if one is on, and from then until Bound takes BepInEx's
        /// warnings as being about MobTracker's cfg. <paramref name="folder"/> is BepInEx's folder, beside LogOutput.log.
        /// </summary>
        public static void Start(ConfigFile config, string folder, string gameFolder)
        {
            ErrorLog = config.Bind("Logging", "ErrorLog", true, ErrorLogText);
            VerboseLog = config.Bind("Logging", "VerboseLog", false, VerboseLogText);
            ModLog.Verbose = VerboseLog.Value;
            _folder = folder;
            _gameFolder = gameFolder;
            _mainThread = Thread.CurrentThread.ManagedThreadId;
            Clock.Start();
            if (ErrorLog.Value || VerboseLog.Value)
                Open("at the game's start");
            _binding = true;
            ErrorLog.SettingChanged += ErrorLogChanged;
            VerboseLog.SettingChanged += VerboseLogChanged;
        }

        /// <summary>
        /// Right after ModConfig.Bind: BepInEx's warnings are no longer MobTracker's, and every setting as the game start
        /// read it goes into the file once. A line that cannot be written shuts the file, as in LogEvent, and LogObserver
        /// says so once: Bound runs in Awake, and a throw out of it would drop the plugin.
        /// </summary>
        public static void Bound(ConfigFile config)
        {
            _binding = false;
            LogFile tee = _tee;
            if (tee == null)
                return;
            try
            {
                tee.WriteFile(EventLines.Settings(Settings(config)));
            }
            catch (Exception e)
            {
                tee.Broke(e);
            }
        }

        /// <summary>Every setting of the cfg as "Section.Key" and its text in the file, in the order bound.</summary>
        public static List<KeyValuePair<string, string>> Settings(ConfigFile config)
        {
            var pairs = new List<KeyValuePair<string, string>>();
            foreach (KeyValuePair<ConfigDefinition, ConfigEntryBase> entry in config)
                pairs.Add(new KeyValuePair<string, string>(entry.Key.Section + "." + entry.Key.Key, entry.Value.GetSerializedValue()));
            return pairs;
        }

        /// <summary>The game quits (MobTrackerPlugin.OnDestroy): the listener goes, and a last line.</summary>
        public static void Stop()
        {
            LogFile tee = _tee;
            _tee = null;
            if (tee == null)
                return;
            try
            {
                Logger.Listeners.Remove(tee);
                tee.WriteFile(EventLines.Closing(tee.LeftOutInAll()));
            }
            catch (Exception)
            {
                // Closing anyway.
            }
            tee.Dispose();
        }

        /// <summary>LogObserver, every frame: why the file stopped, said once in LogOutput.log - the file is shut by then.</summary>
        public static void ReportNotice()
        {
            string notice = _notice;
            if (notice == null)
                return;
            _notice = null;
            MobTrackerPlugin.Log.LogWarning(notice);
        }

        private static void ErrorLogChanged(object sender, EventArgs args)
        {
            Switched("ErrorLog", ErrorLog.Value);
        }

        private static void VerboseLogChanged(object sender, EventArgs args)
        {
            ModLog.Verbose = VerboseLog.Value;
            Switched("VerboseLog", VerboseLog.Value);
        }

        /// <summary>
        /// A switch changed while the game runs: turned on, it opens the file if it never was in this game start (a failed
        /// open is tried again only then - a switch turned off opens nothing), and a Message line - written to
        /// MobTracker.log in every switch state, and to LogOutput.log - says what the file gets now.
        /// </summary>
        private static void Switched(string key, bool on)
        {
            if (on && !_opened)
                Open("when " + key + " was turned on");
            MobTrackerPlugin.Log.LogMessage(EventLines.LoggingSwitch(key, on, ErrorLog.Value, ModLog.Verbose));
        }

        /// <summary>
        /// Takes MobTracker.log (OpenOrCreate, sharing Read only, so a second copy of the game fails here and touches
        /// nothing), copies what it holds to MobTracker-prev.log and only then empties it, writes the header and starts
        /// listening. Every exception of the open is caught, and what the catch calls to let the file go catches its own
        /// (Dispose through Shut, CloseQuietly): one thrown out of Awake would drop the plugin. A failure is said with the
        /// exception's type only - an IOException's message holds the file's full path.
        /// </summary>
        private static void Open(string when)
        {
            FileStream file = null;
            LogFile tee = null;
            try
            {
                file = new FileStream(Path.Combine(_folder, FileName), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.Read);
                _opened = true;
                string kept = null;
                if (file.Length > 0)
                {
                    try
                    {
                        using (var prev = new FileStream(Path.Combine(_folder, PrevName), FileMode.Create, FileAccess.Write, FileShare.Read))
                        {
                            file.Position = 0;
                            file.CopyTo(prev);
                        }
                        file.SetLength(0);
                    }
                    catch (Exception e)
                    {
                        kept = e.GetType().Name;
                        file.Seek(0, SeekOrigin.End);
                    }
                }

                _userFolder = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                tee = new LogFile();
                tee._written = file.Length;
                var writer = new StreamWriter(file, new UTF8Encoding(false));
                writer.NewLine = "\r\n";
                writer.AutoFlush = true;
                tee._writer = writer;
                file = null;
                if (kept != null)
                    tee.WriteFile(EventLines.PrevNotWritten(kept));
                tee.WriteFile(EventLines.Header(MobTrackerPlugin.Version, GameVersion(), BepInExVersion(), when));
                tee.WriteFile(EventLines.HeaderSwitches(ErrorLog.Value, ModLog.Verbose));
                _tee = tee;
                Logger.Listeners.Add(tee);
            }
            catch (Exception e)
            {
                // Whatever holds the file lets it go: the writer, once it has it, else the stream.
                if (tee != null)
                    tee.Dispose();
                if (file != null)
                    CloseQuietly(file);
                MobTrackerPlugin.Log.LogWarning(EventLines.OpenFailed(e.GetType().Name));
            }
        }

        private static void CloseQuietly(FileStream file)
        {
            try
            {
                file.Dispose();
            }
            catch (Exception)
            {
                // Nothing more to do with it.
            }
        }

        private static string GameVersion()
        {
            try
            {
                return LogHost.GameVersion();
            }
            catch (Exception)
            {
                return "(unknown)";
            }
        }

        private static string BepInExVersion()
        {
            try
            {
                return typeof(ConfigFile).Assembly.GetName().Version.ToString();
            }
            catch (Exception)
            {
                return "(unknown)";
            }
        }

        private static string NameOf(ILogSource source)
        {
            return source == null ? "" : source.SourceName;
        }

        /// <summary>
        /// Every line of every log source, from every plugin's log call: MobTracker's own lines as the switches say
        /// (LogRules.ToFile), another source's only as LogRules.Foreign says. Never throws, never logs.
        /// </summary>
        public void LogEvent(object sender, LogEventArgs eventArgs)
        {
            if (_writer == null)
                return;
            try
            {
                int level = (int)eventArgs.Level;
                if (ReferenceEquals(eventArgs.Source, MobTrackerPlugin.Log))
                {
                    if (LogRules.ToFile(level, ErrorLog.Value, ModLog.Verbose))
                        Write(LogRules.Line(level, MobTrackerPlugin.Log.SourceName, LogRules.TextOf(eventArgs.Data)));
                    return;
                }

                string source = NameOf(eventArgs.Source);
                int take = LogRules.Foreign(source, level, ErrorLog.Value || ModLog.Verbose, _binding);
                if (take == LogRules.Skip)
                    return;
                string text = LogRules.TextOf(eventArgs.Data);
                if (take == LogRules.TakeIfOurs && !Ours(text))
                    return;
                Write(LogRules.Line(level, source, text));
            }
            catch (Exception e)
            {
                Broke(e);
            }
        }

        /// <summary>An error about MobTracker's code, and not one more of a storm (RepeatLimiter): a count of those left out first.</summary>
        private bool Ours(string text)
        {
            if (!LogRules.NamesMobTracker(text))
                return false;
            int leftOut;
            bool write;
            lock (_gate)
                write = _repeats.Write(LogRules.RepeatKey(text), Clock.Elapsed.TotalSeconds, out leftOut);
            if (write && leftOut > 0)
                WriteFile(EventLines.LeftOut(leftOut));
            return write;
        }

        private int LeftOutInAll()
        {
            lock (_gate)
                return _repeats.LeftOutInAll();
        }

        /// <summary>A line of the file's own (the header, a note): "[File   :MobTracker]", no BepInEx level.</summary>
        private void WriteFile(string text)
        {
            Write(FileTag + text);
        }

        /// <summary>
        /// One entry: the date, time and frame (the main thread's; "f-" on another), then the line with the game's and the
        /// user's folders written as &lt;game&gt; and &lt;user&gt;. At the cap: one last line, the file shut, and LogOutput.log told
        /// once (ReportNotice).
        /// </summary>
        private void Write(string line)
        {
            lock (_gate)
            {
                StreamWriter writer = _writer;
                if (writer == null)
                    return;
                int frame = -1;
                if (Thread.CurrentThread.ManagedThreadId == _mainThread)
                    frame = LogHost.Frame();
                string entry = LogRules.FileLine(DateTime.Now, frame, LogRules.Scrub(line, _gameFolder, _userFolder));
                long bytes = Encoding.UTF8.GetByteCount(entry) + 2;
                if (!LogRules.Fits(_written, bytes, LogRules.Cap))
                {
                    writer.WriteLine(LogRules.FileLine(DateTime.Now, frame, FileTag + EventLines.CapReached(LogRules.Cap)));
                    _notice = EventLines.CapReached(LogRules.Cap);
                    Shut();
                    return;
                }
                writer.WriteLine(entry);
                _written += bytes;
            }
        }

        /// <summary>A line could not be written: the file is shut, and LogObserver says why, once, outside this call.</summary>
        private void Broke(Exception e)
        {
            try
            {
                if (_notice == null)
                    _notice = EventLines.WriteFailed(e.GetType().Name);
                Dispose();
            }
            catch (Exception)
            {
                // Already shut.
            }
        }

        // Inside the lock.
        private void Shut()
        {
            StreamWriter writer = _writer;
            _writer = null;
            if (writer == null)
                return;
            try
            {
                writer.Dispose();
            }
            catch (Exception)
            {
                // Nothing more can be written to it either way.
            }
        }

        public void Dispose()
        {
            lock (_gate)
                Shut();
        }

        private const string ErrorLogText =
            "Copy every MobTracker warning and error - and an error of MobTracker's code that the game or BepInEx reports, and a " +
            "value in this file BepInEx could not read - into BepInEx/MobTracker.log, each with its date, time and frame. The " +
            "file starts afresh at each game start; the one before is kept as MobTracker-prev.log. LogOutput.log gets every " +
            "MobTracker line either way. With this and VerboseLog both off from the game's start, neither file is touched.";

        private const string VerboseLogText =
            "Also write a line for each of these MobTracker events - a tracking started, stopped, lost or reached and why, the " +
            "guide hidden or shown, the ground path found or not, each watch alert and what Auto-track did, a watched creature " +
            "that does not alert and why, what Always track nearest watched's looks found when they took nothing, the list " +
            "opened and closed, its key and its buttons, Find area's steps, each setting changed, a world entered or left - to " +
            "MobTracker.log and to LogOutput.log, to see what happened and when; the README's Known limits name what it does " +
            "not say yet. On, MobTracker.log gets every MobTracker line, whatever ErrorLog says. Off, none of these lines is " +
            "even put together. Changed in ConfigurationManager, it takes effect at once, also while the game runs - " +
            "unless the cfg cannot be saved then (read-only, or held by another program). Edited in this file by hand, it " +
            "is read only at the next start of the game - edit with the game closed: while it runs, any setting the game " +
            "saves writes its own values back over the file.";
    }
}
