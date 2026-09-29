using UnityEngine;
using UnityEngine.Audio;

namespace MobTracker
{
    /// <summary>
    /// A bell-ish ding synthesised at load, so the plugin ships no audio asset. It plays through the game's "GUI" mixer
    /// group, whose level the game sets from its Volume and Effect volume settings, so those apply on top of
    /// AlertVolume; an AudioSource outside the mixer would ignore them. Without that group it does not play.
    /// </summary>
    internal static class Ding
    {
        private static AudioSource _source;
        private static AudioClip _clip;
        private static float _nextLookup;
        private static bool _missingLogged;

        public static void Init(GameObject host)
        {
            // On a child of its own, as the arrow is: the manager object is shared with other plugins, whose
            // GetComponent<AudioSource>() must not find this one (nor this code theirs).
            var owner = new GameObject("MobTracker_Ding");
            owner.transform.SetParent(host.transform, false);
            _source = owner.AddComponent<AudioSource>();
            _source.playOnAwake = false;
            _source.spatialBlend = 0f;
            _clip = Build();
        }

        public static void Play()
        {
            if (_source == null || !Routed())
                return;

            _source.PlayOneShot(_clip, ModConfig.AlertVolume.Value);
        }

        /// <summary>
        /// Puts the source on the game's "GUI" mixer group, looked up when first needed (AudioMan does not exist yet
        /// while plugins load) and then at most once a second until found.
        /// </summary>
        private static bool Routed()
        {
            if (_source.outputAudioMixerGroup != null)
                return true;

            if (Time.unscaledTime < _nextLookup)
                return false;

            _nextLookup = Time.unscaledTime + 1f;
            AudioMixerGroup gui = FindGuiGroup();
            if (gui == null)
            {
                if (!_missingLogged && AudioMan.instance != null)
                {
                    _missingLogged = true;
                    MobTrackerPlugin.Log.LogWarning("The game's interface-sound mixer group was not found, so the alert ding does not play (it would ignore the game's volume settings).");
                }
                return false;
            }

            _source.outputAudioMixerGroup = gui;
            MobTrackerPlugin.Log.LogInfo("The alert ding plays on the game's " + gui.name + " mixer group.");
            return true;
        }

        /// <summary>
        /// The master mixer's "GUI" group. AudioMan.m_guiMixer would be the obvious way, but the game ships it empty (null
        /// in the _AudioManager prefab), so the group is found by name, as NuclearTrollstav finds it.
        /// </summary>
        private static AudioMixerGroup FindGuiGroup()
        {
            AudioMan audio = AudioMan.instance;
            if (audio == null || audio.m_masterMixer == null)
                return null;

            AudioMixer mixer = audio.m_masterMixer;
            try
            {
                foreach (AudioMixerGroup group in mixer.FindMatchingGroups("Master"))
                {
                    if (group != null && group.name == "GUI")
                        return group;
                }
            }
            catch (System.Exception)
            {
                // Looked for another way below.
            }

            foreach (AudioMixerGroup group in Resources.FindObjectsOfTypeAll<AudioMixerGroup>())
            {
                if (group != null && group.name == "GUI" && group.audioMixer == mixer)
                    return group;
            }
            return null;
        }

        private static AudioClip Build()
        {
            const int rate = 44100;
            const float seconds = 0.9f;
            const float fundamental = 1318.5f; // E6

            var samples = new float[(int)(rate * seconds)];
            for (int i = 0; i < samples.Length; i++)
            {
                float t = i / (float)rate;
                float attack = Mathf.Clamp01(t / 0.003f); // 3 ms ramp, otherwise the onset clicks
                float wave = 0.6f * Mathf.Sin(2f * Mathf.PI * fundamental * t) * Mathf.Exp(-5f * t)
                           + 0.3f * Mathf.Sin(2f * Mathf.PI * fundamental * 2f * t) * Mathf.Exp(-9f * t);
                samples[i] = attack * wave;
            }

            // Filled through the reader callback rather than SetData: Unity 6 added a
            // ReadOnlySpan overload of SetData, and net48 has no such type to resolve it against.
            // Reads are sequential; the running position keeps this right whether Unity asks for
            // the clip in one buffer or several.
            int position = 0;
            return AudioClip.Create("MobTracker_Ding", samples.Length, 1, rate, false, buffer =>
            {
                for (int i = 0; i < buffer.Length; i++)
                    buffer[i] = position < samples.Length ? samples[position++] : 0f;
            });
        }
    }
}
