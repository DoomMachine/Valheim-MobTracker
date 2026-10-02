using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace MobTracker
{
    /// <summary>
    /// MobTracker.log's decisions (0.7.0), free of game and BepInEx types so the test project links this file: which of
    /// MobTracker's own lines the file takes (ToFile), which lines of other log sources it looks at (Foreign) and which of
    /// those are about MobTracker's code (NamesMobTracker), how a line looks (Line, FileLine), what is kept out of it
    /// (Scrub), its size limit (Fits) and how a storm of one repeated error is thinned (RepeatLimiter).
    /// </summary>
    public static class LogRules
    {
        // BepInEx.Logging.LogLevel's values (BepInEx 5.4.23.3, decompiled): tools\preflight.ps1 checks they still agree.
        public const int Fatal = 1;
        public const int Error = 2;
        public const int Warning = 4;
        public const int Message = 8;
        public const int Info = 16;
        public const int Debug = 32;

        /// <summary>The most MobTracker.log holds in one game start: 5 MB, then a last line says it stopped.</summary>
        public const long Cap = 5L * 1024 * 1024;

        /// <summary>Foreign: another source's line is not looked at.</summary>
        public const int Skip = 0;
        /// <summary>Foreign: written as it is (BepInEx's warning about a value of MobTracker's cfg it could not read).</summary>
        public const int Take = 1;
        /// <summary>Foreign: written only when its stack trace has a frame of MobTracker's code, and the repeat limit allows.</summary>
        public const int TakeIfOurs = 2;

        /// <summary>
        /// Whether a line of MobTracker's own log source goes to MobTracker.log. Message is MobTracker.log's own notes
        /// (a switch turned on or off): always. Fatal, Error and Warning: with ErrorLog on, or VerboseLog on. Info and
        /// Debug: with VerboseLog on. VerboseLog on means everything, whatever ErrorLog says.
        /// </summary>
        public static bool ToFile(int level, bool errorLog, bool verbose)
        {
            if ((level & Message) != 0)
                return true;
            if ((level & (Fatal | Error | Warning)) != 0)
                return errorLog || verbose;
            return verbose;
        }

        /// <summary>
        /// What MobTracker.log does with a line of another log source (not MobTracker's own). With both switches off,
        /// nothing. While MobTracker's settings are being read (binding), BepInEx's own warnings - "could not be parsed and
        /// will be ignored" - are about MobTracker's cfg: taken. An error or a fatal one from Unity's log ("Unity Log": an
        /// exception nobody caught) or from BepInEx (a setting's change handler that threw) is taken if it is about
        /// MobTracker's code. Anything else - every other plugin's lines, Unity's info and warnings - is skipped.
        /// </summary>
        public static int Foreign(string sourceName, int level, bool anySwitch, bool binding)
        {
            if (!anySwitch)
                return Skip;
            if (binding && sourceName == "BepInEx" && (level & Warning) != 0)
                return Take;
            if ((level & (Fatal | Error)) != 0 && (sourceName == "Unity Log" || sourceName == "BepInEx"))
                return TakeIfOurs;
            return Skip;
        }

        /// <summary>A line's text: what BepInEx was given, a string or an exception (whose text has its stack trace).</summary>
        public static string TextOf(object data)
        {
            if (data == null)
                return "";
            try
            {
                return data.ToString();
            }
            catch (Exception e)
            {
                return "(the text of this line could not be read: " + e.GetType().Name + ")";
            }
        }

        /// <summary>
        /// True when a stack trace in the text has a frame of MobTracker's code: a line that, without its leading spaces
        /// and an "at ", starts with "MobTracker." - every MobTracker type is in that namespace - in Mono's form
        /// ("  at MobTracker.Tracker.LateUpdate () [0x00012] in &lt;...&gt;:0") and in Unity's ("MobTracker.Tracker:LateUpdate ()").
        /// The first line - the exception's own message - is not a frame, so a message that only names MobTracker does
        /// not count.
        /// </summary>
        public static bool NamesMobTracker(string text)
        {
            if (string.IsNullOrEmpty(text))
                return false;
            string[] lines = text.Split('\n');
            for (int i = 1; i < lines.Length; i++)
            {
                if (OurFrame(lines[i]) != null)
                    return true;
            }
            return false;
        }

        /// <summary>The frame a stack-trace line names, without its indent and "at ", when it is MobTracker's code; else null.</summary>
        private static string OurFrame(string line)
        {
            string frame = line.Trim(' ', '\t', '\r');
            if (frame.StartsWith("at ", StringComparison.Ordinal))
                frame = frame.Substring(3);
            return frame.StartsWith("MobTracker.", StringComparison.Ordinal) ? frame : null;
        }

        /// <summary>
        /// The key one repeated error is counted under: its first line (exception type and message) and its first
        /// MobTracker frame, so the same throw from another place counts apart.
        /// </summary>
        public static string RepeatKey(string text)
        {
            if (text == null)
                return "";
            string[] lines = text.Split('\n');
            string frame = "";
            for (int i = 1; i < lines.Length && frame.Length == 0; i++)
                frame = OurFrame(lines[i]) ?? "";
            return lines[0].TrimEnd('\r') + "|" + frame;
        }

        /// <summary>A level's name as BepInEx writes it: Fatal, Error, Warning, Message, Info, Debug.</summary>
        public static string LevelName(int level)
        {
            switch (level)
            {
                case Fatal: return "Fatal";
                case Error: return "Error";
                case Warning: return "Warning";
                case Message: return "Message";
                case Info: return "Info";
                case Debug: return "Debug";
                default: return level.ToString(CultureInfo.InvariantCulture);
            }
        }

        /// <summary>
        /// A line as BepInEx writes it to LogOutput.log (LogEventArgs.ToString): "[Info   :MobTracker] text" - the level
        /// padded to 7, the source to 10.
        /// </summary>
        public static string Line(int level, string sourceName, string text)
        {
            return string.Format(CultureInfo.InvariantCulture, "[{0,-7}:{1,10}] {2}", LevelName(level), sourceName, text);
        }

        /// <summary>
        /// "2026-10-02 15:16:03.512 f48211 " and the line; frame -1 (not on the game's main thread): "f-". A line of several
        /// (a stack trace) is written with CRLF between them and each further one indented by four spaces, so every
        /// entry of the file starts with its date and time.
        /// </summary>
        public static string FileLine(DateTime now, int frame, string line)
        {
            string body = (line ?? "").Replace("\r\n", "\n").Replace('\r', '\n').TrimEnd('\n').Replace("\n", "\r\n    ");
            return now.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture)
                   + (frame >= 0 ? " f" + frame.ToString(CultureInfo.InvariantCulture) + " " : " f- ") + body;
        }

        /// <summary>
        /// The text with the game's folder and the Windows user folder written as &lt;game&gt; and &lt;user&gt;, wherever they
        /// appear in full (in any case); the longer one first, as one can hold the other. A folder shorter than 4
        /// characters, or none, is skipped.
        /// </summary>
        public static string Scrub(string text, string gameFolder, string userFolder)
        {
            if (string.IsNullOrEmpty(text))
                return text;
            bool gameFirst = (gameFolder ?? "").Length >= (userFolder ?? "").Length;
            text = Replace(text, gameFirst ? gameFolder : userFolder, gameFirst ? "<game>" : "<user>");
            return Replace(text, gameFirst ? userFolder : gameFolder, gameFirst ? "<user>" : "<game>");
        }

        private static string Replace(string text, string folder, string with)
        {
            if (string.IsNullOrEmpty(folder))
                return text;
            folder = folder.TrimEnd('\\', '/');
            if (folder.Length < 4)
                return text;
            var result = new StringBuilder(text.Length);
            int start = 0;
            while (true)
            {
                int at = text.IndexOf(folder, start, StringComparison.OrdinalIgnoreCase);
                if (at < 0)
                    break;
                result.Append(text, start, at - start).Append(with);
                start = at + folder.Length;
            }
            return start == 0 ? text : result.Append(text, start, text.Length - start).ToString();
        }

        /// <summary>Whether a line of <paramref name="lineBytes"/> still fits under the cap after <paramref name="written"/> bytes.</summary>
        public static bool Fits(long written, long lineBytes, long cap)
        {
            return written + lineBytes <= cap;
        }

        /// <summary>
        /// An exception as an error line names it: "Type: message", then each inner exception's " &lt;- Type: message" -
        /// HarmonyX wraps a patch's real cause in "Patching exception in method ...". No stack trace.
        /// </summary>
        public static string Describe(Exception e)
        {
            if (e == null)
                return "(no exception)";
            var text = new StringBuilder();
            int depth = 0;
            for (Exception x = e; x != null && depth < 5; x = x.InnerException, depth++)
            {
                if (depth > 0)
                    text.Append(" <- ");
                text.Append(x.GetType().Name).Append(": ").Append(x.Message);
            }
            return text.ToString();
        }
    }

    /// <summary>
    /// Thins a storm of one repeated error (an Update that throws on every frame): the first of a key is written, the
    /// same key again within <see cref="Window"/> seconds of the last one written is only counted, and the next one
    /// after that is written with the count of those left out. At most <see cref="MaxKeys"/> keys are remembered; past
    /// that the oldest is forgotten.
    /// </summary>
    public class RepeatLimiter
    {
        public const double Window = 60.0;
        public const int MaxKeys = 32;

        private class Seen
        {
            public double WrittenAt;
            public int Left;
        }

        private readonly Dictionary<string, Seen> _seen = new Dictionary<string, Seen>();
        private readonly List<string> _order = new List<string>();

        /// <summary>True: write it; <paramref name="leftOut"/> how many of the key were left out since the last written.</summary>
        public bool Write(string key, double now, out int leftOut)
        {
            leftOut = 0;
            Seen seen;
            if (!_seen.TryGetValue(key, out seen))
            {
                if (_order.Count >= MaxKeys)
                {
                    _seen.Remove(_order[0]);
                    _order.RemoveAt(0);
                }
                _seen[key] = new Seen { WrittenAt = now };
                _order.Add(key);
                return true;
            }

            if (now - seen.WrittenAt < Window)
            {
                seen.Left++;
                return false;
            }

            leftOut = seen.Left;
            seen.Left = 0;
            seen.WrittenAt = now;
            return true;
        }

        /// <summary>The counts still left out, for a last line when the file closes; each key once, then forgotten.</summary>
        public int LeftOutInAll()
        {
            int all = 0;
            foreach (Seen seen in _seen.Values)
                all += seen.Left;
            _seen.Clear();
            _order.Clear();
            return all;
        }
    }

    /// <summary>
    /// A setting's changes as the verbose log writes them: the first change of a setting at once, and when the same
    /// setting changes again within <see cref="Quiet"/> seconds (a ConfigurationManager slider dragged, a value typed
    /// key by key), the rest are gathered into one line once it has held still that long - its value then, the value
    /// before the first change, and how many changes there were. One change alone writes no second line.
    /// </summary>
    public class SettingSettler
    {
        public const double Quiet = 1.0;

        private class Burst
        {
            public string Was;
            public string Now;
            public int Changes;
            public double Last;
            public double First;
        }

        private readonly Dictionary<string, Burst> _bursts = new Dictionary<string, Burst>();

        /// <summary>A burst is under way (Due has something to look at).</summary>
        public bool Busy
        {
            get { return _bursts.Count > 0; }
        }

        /// <summary>A change: returns the line to write at once, or null when it joins a burst already under way.</summary>
        public string Changed(string key, string was, string now, double t)
        {
            Burst burst;
            if (_bursts.TryGetValue(key, out burst) && t - burst.Last < Quiet)
            {
                burst.Now = now;
                burst.Changes++;
                burst.Last = t;
                return null;
            }

            _bursts[key] = new Burst { Was = was, Now = now, Changes = 1, Last = t, First = t };
            return EventLines.Setting(key, now, was);
        }

        /// <summary>Lines for the bursts that have held still since <see cref="Quiet"/> seconds, each once.</summary>
        public List<string> Due(double t)
        {
            var lines = new List<string>();
            var done = new List<string>();
            foreach (KeyValuePair<string, Burst> pair in _bursts)
            {
                if (t - pair.Value.Last < Quiet)
                    continue;
                done.Add(pair.Key);
                if (pair.Value.Changes > 1)
                    lines.Add(EventLines.SettingSettled(pair.Key, pair.Value.Now, pair.Value.Was, pair.Value.Changes, pair.Value.Last - pair.Value.First));
            }
            foreach (string key in done)
                _bursts.Remove(key);
            return lines;
        }
    }
}
