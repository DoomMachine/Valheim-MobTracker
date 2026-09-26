using UnityEngine;

namespace MobTracker
{
    /// <summary>A bell-ish ding synthesised at load, so the plugin ships no audio asset.</summary>
    internal static class Ding
    {
        private static AudioSource _source;
        private static AudioClip _clip;

        public static void Init(GameObject host)
        {
            _source = host.AddComponent<AudioSource>();
            _source.playOnAwake = false;
            _source.spatialBlend = 0f;
            _clip = Build();
        }

        public static void Play()
        {
            _source.PlayOneShot(_clip, ModConfig.AlertVolume.Value);
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
