param(
    [string]$JavaHome = 'D:\develop\JAVA\jdk\ms-17.0.18',
    [string]$PythonExe = 'python',
    [switch]$SkipBuild,
    [switch]$UseLlm,
    [switch]$WithKnowledge,
    [switch]$WithOperations
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'scripts\dev\Start.ps1') @PSBoundParameters
