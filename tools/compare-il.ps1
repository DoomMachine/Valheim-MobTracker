<#
.SYNOPSIS
  Compares two builds of a plugin member by member and instruction by instruction (Mono.Cecil).

.DESCRIPTION
  Tells whether two builds compile to the same code - used to show that this repository's build of the author's
  source matches the author's own build. It compares every type (nested ones too), its attributes, base type,
  interfaces and custom attributes; every field (type, flags, constant);
  every method (signature, flags, parameters, custom attributes, locals, exception handlers and each IL
  instruction with its operand - branch targets as instruction indices, floats by their bits); properties and
  events; the assembly references and assembly-level attributes. Prints the first difference in each method
  (-Context N shows the lines around it) and exits 1 if there is any in code; assembly-level attribute differences (version stamps and the like) are listed separately
  and do not fail unless -Strict is given.

.EXAMPLE
  .\compare-il.ps1 -Left <original.dll> -Right build\MobTracker.dll
#>
param(
    [Parameter(Mandatory = $true)] [string]$Left,
    [Parameter(Mandatory = $true)] [string]$Right,
    [string]$ValheimDir = $(if ($env:VALHEIM) { $env:VALHEIM } else { "E:\SteamLibrary\steamapps\common\Valheim" }),
    [switch]$Strict,
    [int]$Context = 0     # lines of each method's description to show around its first difference
)
$ErrorActionPreference = "Stop"
Add-Type -Path (Join-Path $ValheimDir "BepInEx\core\Mono.Cecil.dll")

function Read-Mod([string]$path) {
    $r = New-Object Mono.Cecil.DefaultAssemblyResolver
    $r.AddSearchDirectory((Join-Path $ValheimDir "valheim_Data\Managed"))
    $r.AddSearchDirectory((Join-Path $ValheimDir "BepInEx\core"))
    $p = New-Object Mono.Cecil.ReaderParameters
    $p.AssemblyResolver = $r
    $p.InMemory = $true
    return [Mono.Cecil.ModuleDefinition]::ReadModule((Resolve-Path $path).Path, $p)
}

function Format-Attrs($provider) {
    $out = @()
    foreach ($ca in $provider.CustomAttributes) {
        $args = @($ca.ConstructorArguments | ForEach-Object { "$($_.Value)" }) -join ", "
        $named = @($ca.Properties + $ca.Fields | ForEach-Object { "$($_.Name)=$($_.Argument.Value)" }) -join ", "
        $out += ("{0}({1}{2})" -f $ca.AttributeType.FullName, $args, $(if ($named) { "; " + $named } else { "" }))
    }
    return (@($out | Sort-Object) -join " | ")
}

function Format-Operand($ins, $index) {
    $op = $ins.Operand
    if ($null -eq $op) { return "" }
    if ($op -is [Mono.Cecil.Cil.Instruction]) { return "->" + $index[$op] }
    if ($op -is [Mono.Cecil.Cil.Instruction[]]) { return "->[" + (@($op | ForEach-Object { $index[$_] }) -join ",") + "]" }
    if ($op -is [Mono.Cecil.Cil.VariableDefinition]) { return "V" + $op.Index }
    if ($op -is [Mono.Cecil.ParameterDefinition]) { return "P" + $op.Index }
    if ($op -is [single]) { return "f:" + [BitConverter]::ToString([BitConverter]::GetBytes([single]$op)) }
    if ($op -is [double]) { return "d:" + [BitConverter]::ToString([BitConverter]::GetBytes([double]$op)) }
    if ($op -is [string]) { return '"' + $op + '"' }
    if ($op -is [Mono.Cecil.MemberReference]) { return $op.FullName }
    return "$op"
}

function Describe-Method($m) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("attrs " + $m.Attributes + " impl " + $m.ImplAttributes)
    $lines.Add("custom " + (Format-Attrs $m))
    foreach ($p in $m.Parameters) {
        $c = ""; if ($p.HasConstant) { $c = " = " + $p.Constant }
        $lines.Add(("param {0} {1} {2}{3} [{4}]" -f $p.Index, $p.ParameterType.FullName, $p.Name, $c, (Format-Attrs $p)))
    }
    $lines.Add("return " + $m.ReturnType.FullName + " [" + (Format-Attrs $m.MethodReturnType) + "]")
    foreach ($g in $m.GenericParameters) { $lines.Add("generic " + $g.Name) }
    if ($m.HasBody) {
        $b = $m.Body
        $lines.Add("initlocals " + $b.InitLocals)
        foreach ($v in $b.Variables) { $lines.Add("local " + $v.Index + " " + $v.VariableType.FullName) }
        $ins = @($b.Instructions)
        $index = @{}
        for ($k = 0; $k -lt $ins.Count; $k++) { $index[$ins[$k]] = $k }
        for ($k = 0; $k -lt $ins.Count; $k++) { $lines.Add(("{0,4} {1} {2}" -f $k, $ins[$k].OpCode.Name, (Format-Operand $ins[$k] $index))) }
        foreach ($h in $b.ExceptionHandlers) {
            $ct = ""; if ($h.CatchType) { $ct = $h.CatchType.FullName }
            $ends = { param($i) if ($i) { $index[$i] } else { "end" } }
            $lines.Add(("handler {0} try {1}-{2} handler {3}-{4} {5}" -f $h.HandlerType, $index[$h.TryStart], (& $ends $h.TryEnd), $index[$h.HandlerStart], (& $ends $h.HandlerEnd), $ct))
        }
    }
    return $lines
}

function All-Types($module) {
    $list = @()
    $stack = New-Object System.Collections.Stack
    foreach ($t in $module.Types) { $stack.Push($t) }
    while ($stack.Count -gt 0) {
        $t = $stack.Pop(); $list += $t
        foreach ($n in $t.NestedTypes) { $stack.Push($n) }
    }
    return $list
}

$a = Read-Mod $Left
$b = Read-Mod $Right
$diffs = New-Object System.Collections.Generic.List[string]
$note = New-Object System.Collections.Generic.List[string]
$methodsCompared = 0; $instructionsCompared = 0

# Compiler-emitted marker types that a newer compiler may add or drop; compared, but reported as notes.
$markerTypes = @("Microsoft.CodeAnalysis.EmbeddedAttribute", "System.Runtime.CompilerServices.RefSafetyRulesAttribute")

$ta = @{}; foreach ($t in (All-Types $a)) { $ta[$t.FullName] = $t }
$tb = @{}; foreach ($t in (All-Types $b)) { $tb[$t.FullName] = $t }
foreach ($name in @($ta.Keys + $tb.Keys | Sort-Object -Unique)) {
    if (-not $ta.ContainsKey($name) -or -not $tb.ContainsKey($name)) {
        $msg = "type {0} only in {1}" -f $name, $(if ($ta.ContainsKey($name)) { "left" } else { "right" })
        if ($markerTypes -contains $name) { $note.Add($msg) } else { $diffs.Add($msg) }
        continue
    }
    $x = $ta[$name]; $y = $tb[$name]
    $bx = ""; if ($x.BaseType) { $bx = $x.BaseType.FullName }
    $by = ""; if ($y.BaseType) { $by = $y.BaseType.FullName }
    if ($x.Attributes -ne $y.Attributes) { $diffs.Add("type $name attributes $($x.Attributes) vs $($y.Attributes)") }
    if ($bx -ne $by) { $diffs.Add("type $name base $bx vs $by") }
    $ix = (@($x.Interfaces | ForEach-Object { $_.InterfaceType.FullName }) | Sort-Object) -join ","
    $iy = (@($y.Interfaces | ForEach-Object { $_.InterfaceType.FullName }) | Sort-Object) -join ","
    if ($ix -ne $iy) { $diffs.Add("type $name interfaces $ix vs $iy") }
    if ((Format-Attrs $x) -ne (Format-Attrs $y)) { $diffs.Add("type $name custom attributes: " + (Format-Attrs $x) + "  vs  " + (Format-Attrs $y)) }

    $fx = @{}; foreach ($f in $x.Fields) { $fx[$f.Name] = $f }
    $fy = @{}; foreach ($f in $y.Fields) { $fy[$f.Name] = $f }
    foreach ($fn in @($fx.Keys + $fy.Keys | Sort-Object -Unique)) {
        if (-not $fx.ContainsKey($fn) -or -not $fy.ContainsKey($fn)) { $diffs.Add("field $name::$fn only in " + $(if ($fx.ContainsKey($fn)) { "left" } else { "right" })); continue }
        $p = $fx[$fn]; $q = $fy[$fn]
        $sp = "{0} {1} {2} {3}" -f $p.FieldType.FullName, $p.Attributes, $p.Constant, (Format-Attrs $p)
        $sq = "{0} {1} {2} {3}" -f $q.FieldType.FullName, $q.Attributes, $q.Constant, (Format-Attrs $q)
        if ($sp -ne $sq) { $diffs.Add("field $name::$fn  $sp  vs  $sq") }
    }

    $mx = @{}; foreach ($m in $x.Methods) { $mx[$m.FullName] = $m }
    $my = @{}; foreach ($m in $y.Methods) { $my[$m.FullName] = $m }
    foreach ($mn in @($mx.Keys + $my.Keys | Sort-Object -Unique)) {
        if (-not $mx.ContainsKey($mn) -or -not $my.ContainsKey($mn)) { $diffs.Add("method $mn only in " + $(if ($mx.ContainsKey($mn)) { "left" } else { "right" })); continue }
        $dx = Describe-Method $mx[$mn]; $dy = Describe-Method $my[$mn]
        $methodsCompared++
        if ($mx[$mn].HasBody) { $instructionsCompared += $mx[$mn].Body.Instructions.Count }
        $n = [Math]::Max($dx.Count, $dy.Count)
        for ($k = 0; $k -lt $n; $k++) {
            $l = $null; $r = $null
            if ($k -lt $dx.Count) { $l = $dx[$k] }
            if ($k -lt $dy.Count) { $r = $dy[$k] }
            if ($l -ne $r) {
                $msg = "method $mn`n      left : $l`n      right: $r"
                if ($Context -gt 0) {
                    $lo = [Math]::Max(0, $k - $Context)
                    $msg += "`n      --- left ---"
                    for ($j = $lo; $j -lt [Math]::Min($dx.Count, $k + $Context); $j++) { $msg += "`n        " + $dx[$j] }
                    $msg += "`n      --- right ---"
                    for ($j = $lo; $j -lt [Math]::Min($dy.Count, $k + $Context); $j++) { $msg += "`n        " + $dy[$j] }
                }
                $diffs.Add($msg); break
            }
        }
    }

    $px = (@($x.Properties | ForEach-Object { "{0} {1} {2} {3}" -f $_.PropertyType.FullName, $_.Name, $_.GetMethod, $_.SetMethod }) | Sort-Object) -join "; "
    $py = (@($y.Properties | ForEach-Object { "{0} {1} {2} {3}" -f $_.PropertyType.FullName, $_.Name, $_.GetMethod, $_.SetMethod }) | Sort-Object) -join "; "
    if ($px -ne $py) { $diffs.Add("type $name properties: $px  vs  $py") }
    $ex = (@($x.Events | ForEach-Object { $_.FullName }) | Sort-Object) -join "; "
    $ey = (@($y.Events | ForEach-Object { $_.FullName }) | Sort-Object) -join "; "
    if ($ex -ne $ey) { $diffs.Add("type $name events: $ex  vs  $ey") }
}

$ra = (@($a.AssemblyReferences | ForEach-Object { $_.Name }) | Sort-Object) -join ", "
$rb = (@($b.AssemblyReferences | ForEach-Object { $_.Name }) | Sort-Object) -join ", "
if ($ra -ne $rb) { $diffs.Add("assembly references: $ra  vs  $rb") }
$aa = @($a.Assembly.CustomAttributes | ForEach-Object { $_.AttributeType.FullName + "(" + (@($_.ConstructorArguments | ForEach-Object { "$($_.Value)" }) -join ", ") + ")" }) | Sort-Object
$ab = @($b.Assembly.CustomAttributes | ForEach-Object { $_.AttributeType.FullName + "(" + (@($_.ConstructorArguments | ForEach-Object { "$($_.Value)" }) -join ", ") + ")" }) | Sort-Object
$attrDiff = @(Compare-Object $aa $ab | ForEach-Object { "{0} {1}" -f $(if ($_.SideIndicator -eq "<=") { "left only :" } else { "right only:" }), $_.InputObject })
if ((Format-Attrs $a) -ne (Format-Attrs $b)) { $attrDiff += ("module attributes: " + (Format-Attrs $a) + "  vs  " + (Format-Attrs $b)) }

Write-Output ("types {0} / {1}; methods compared {2}; instructions compared {3}; assembly references: {4}" -f $ta.Count, $tb.Count, $methodsCompared, $instructionsCompared, $ra)
foreach ($d in $note) { Write-Output "  note  $d" }
foreach ($d in $attrDiff) { Write-Output "  assembly attribute  $d" }
foreach ($d in $diffs) { Write-Output "  DIFF  $d" }
if ($diffs.Count -gt 0 -or ($Strict -and $attrDiff.Count -gt 0)) { Write-Output ("NOT EQUIVALENT - {0} code difference(s)" -f $diffs.Count); exit 1 }
Write-Output "EQUIVALENT - every type, member, attribute and IL instruction matches"
exit 0
