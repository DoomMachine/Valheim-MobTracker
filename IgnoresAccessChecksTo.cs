using System;
using System.Runtime.CompilerServices;

// Lets the plugin reach the private game members it uses at run time: the ground-path guide's Pathfinding
// internals and Find area's spawn lists. The compiler sees them through the publicized copies made by
// tools/publicize.ps1. Written by hand here; BepInEx.AssemblyPublicizer.MSBuild used to generate it.
[assembly: IgnoresAccessChecksTo("assembly_utils")]
[assembly: IgnoresAccessChecksTo("assembly_valheim")]

namespace System.Runtime.CompilerServices
{
    [AttributeUsage(AttributeTargets.Assembly, AllowMultiple = true)]
    internal sealed class IgnoresAccessChecksToAttribute : Attribute
    {
        public IgnoresAccessChecksToAttribute(string assemblyName)
        {
        }
    }
}
