using System;
using System.Collections.Generic;
using BepInEx.Configuration;
using UnityEngine;

namespace MobTracker
{
    /// <summary>
    /// Reads ListKey so that a key Valheim cannot read does nothing, instead of throwing on every frame - TomTom's
    /// Hotkeys (1.1.2), for one key. ZInput.IsKeyCodeValid lets through 30 KeyCodes that ZInput's KeyCode-to-Key
    /// table lacks on 1.0.16 (Plus, F13-F15, WheelUp, WheelDown, the shifted symbols...), and for each of them
    /// Keyboard.current[Key.None] throws ArgumentOutOfRangeException. The first failed read is caught, the key is
    /// remembered, one warning names the setting, and from then on the key reads as unbound until the setting
    /// changes (ModConfig.Bind calls Forget). Codes IsKeyCodeValid rejects (Mouse5, Mouse6, F16 and up) simply
    /// never fire.
    ///
    /// Not TomTom's: the left, right and middle mouse buttons are refused the same way. ZInput reads them from the
    /// mouse, so a list toggled by the left button would close on the press of every click inside it, before the
    /// release could reach one of its buttons (IMGUI buttons act on the release), and open on every attack; the right
    /// and middle buttons block, delete map pins and ping. The side buttons (Mouse3, Mouse4) work.
    /// </summary>
    internal static class Hotkeys
    {
        // KeyCodes refused. Kept as ints: List<int>.Contains compares without boxing, and it runs every frame.
        private static readonly List<int> Refused = new List<int>();

        /// <summary>True on the frame the setting's key goes down (ZInput.GetKeyDown).</summary>
        public static bool Pressed(ConfigEntry<KeyCode> setting)
        {
            KeyCode key = setting.Value;
            if (key == KeyCode.None)
                return false;
            if (Refused.Count > 0 && Refused.Contains((int)key))
                return false;
            if (ListKeys.IsClickButton((int)key))
            {
                Refuse(setting, key, "the left, right and middle mouse buttons belong to the game and to the window's own buttons");
                return false;
            }

            try
            {
                return ZInput.GetKeyDown(key, false);
            }
            catch (Exception e)
            {
                Refuse(setting, key, "Valheim cannot read this key (" + e.GetType().Name + ")");
                return false;
            }
        }

        /// <summary>Tries every key again, and warns again about one that still cannot be used.</summary>
        public static void Forget()
        {
            Refused.Clear();
        }

        private static void Refuse(ConfigEntry<KeyCode> setting, KeyCode key, string why)
        {
            Refused.Add((int)key);
            MobTrackerPlugin.Log.LogWarning(setting.Definition.Key + " = " + key + ": " + why + ", so it does nothing. Choose another key for "
                + setting.Definition.Key + ".");
        }

        /// <summary>A key that types or edits text (TomTom's Plugin.IsTextEditingKey).</summary>
        public static bool TypesText(KeyCode key)
        {
            if (key >= KeyCode.A && key <= KeyCode.Z) return true;
            if (key >= KeyCode.Alpha0 && key <= KeyCode.Alpha9) return true;
            if (key >= KeyCode.Keypad0 && key <= KeyCode.KeypadEquals) return true;   // includes KeypadEnter

            switch (key)
            {
                case KeyCode.Space:
                case KeyCode.Comma:
                case KeyCode.Period:
                case KeyCode.Minus:
                case KeyCode.Plus:
                case KeyCode.Equals:
                case KeyCode.Semicolon:
                case KeyCode.Colon:
                case KeyCode.Slash:
                case KeyCode.Backslash:
                case KeyCode.Quote:
                case KeyCode.BackQuote:
                case KeyCode.LeftBracket:
                case KeyCode.RightBracket:
                case KeyCode.Backspace:
                case KeyCode.Delete:
                case KeyCode.Return:
                case KeyCode.Tab:
                    return true;
                default:
                    return false;
            }
        }
    }

    /// <summary>
    /// Whether the player is typing into one of the game's own text fields, read from the game's own state. Not from
    /// TextInput.IsVisible or Chat.HasFocus: this plugin, TomTom, ConfigurationManager and MeasurementTracker force those
    /// to true while their windows are open, so they cannot tell a window from typing. Minimap.InTextInput and
    /// Console.IsVisible are asked as they are - no installed mod patches them.
    /// </summary>
    internal static class GameTyping
    {
        public static bool Any()
        {
            // A sign, a portal's tag or a pet's name (TextInput.RequestText); vanilla IsVisible reads this panel a frame late.
            TextInput text = TextInput.instance;
            if (text != null && text.m_panel != null && text.m_panel.activeSelf)
                return true;

            // Chat: m_input.isFocused as of the last Chat.Update, what Menu.Update reads too; m_input is Chatter's own
            // field while Chatter is on (ChatPanelController.ToggleChatter assigns it), so this holds with and without it.
            Chat chat = Chat.instance;
            if (chat != null && chat.m_wasFocused)
                return true;

            // The build menu's search box.
            Hud hud = Hud.instance;
            if (hud != null && hud.m_buildUi != null && hud.m_buildUi.SearchFieldFocused)
                return true;

            // The large map's pin name, and the console.
            return Minimap.InTextInput() || Console.IsVisible();
        }
    }
}
