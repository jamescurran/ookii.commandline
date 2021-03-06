# This script is used to create a distribution folder that can be packaged into a zip file for release.
# Before running this script, make sure you have built a Release version of the solution, and have created
# an up-to-date Documentation.chm file.
param(
    [parameter(Mandatory=$true, Position=0)][string]$TargetPath
)

$distItems = "Ookii.CommandLine\bin\Release\Ookii.CommandLine.dll","Ookii.CommandLine\bin\Release\Ookii.CommandLine.xml","Ookii.CommandLine\bin\Release\Ookii.CommandLine.pdb",
    "CommandLineSampleCS\bin\Release\CommandLineSampleCS.exe","ShellCommandSampleCS\bin\Release\ShellCommandSampleCS.exe",
    "..\..\Docs\User Guide.html","..\..\Docs\Help\Documentation.chm","..\..\Docs\license.txt","Snippets"
$nugetPackageName = "Ookii.CommandLine"
$nugetLibItems = "Ookii.CommandLine\bin\Release\Ookii.CommandLine.dll","Ookii.CommandLine\bin\Release\Ookii.CommandLine.xml","Ookii.CommandLine\bin\Release\Ookii.CommandLine.pdb"
$nugetSampleContentItems = "NuGet\SampleArguments.cs.pp","NuGet\SampleArguments.vb.pp"
$nugetSampleToolsItems = "NuGet\Install.ps1"
$unneededFolders = "bin","obj","TestResults","NuGet","Snippets" # Remove snippets from the source folder, no sense including it twice
$unneededFileExtensions = ".vssscc",".vspscc",".suo",".user"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
New-Item $TargetPath -ItemType Directory -Force | Out-Null
if( [System.IO.Directory]::GetFileSystemEntries($TargetPath).Length -gt 0 )
    { throw "Target directory not empty." }

$distPath = Join-Path $TargetPath dist
    
Write-Host "Copying source files..."
$targetSourcePath = Join-Path $distPath Source
New-Item $targetSourcePath -Type "directory" -Force | Out-Null
Copy-Item $(Join-Path $scriptPath *) $targetSourcePath -Recurse -Force
Get-ChildItem -LiteralPath $targetSourcePath -Recurse -Force | foreach { $_.Attributes = $_.Attributes -band (-bnot ([System.IO.FileAttributes]::ReadOnly -bor [System.IO.FileAttributes]::Hidden)) }

Write-Host "Removing unneeded files."
$itemsToDelete = Get-ChildItem -LiteralPath $targetSourcePath -Recurse -Force | 
    where { ($_.PSIsContainer -and $unneededFolders -icontains $_.Name) -or (-not $_.PSIsContainer -and $unneededFileExtensions -icontains [System.IO.Path]::GetExtension($_.Name)) }
    
$itemsToDelete | foreach { Remove-Item $_.FullName -Force -Recurse }

Write-Host "Removing source control bindings"
Get-ChildItem -LiteralPath $targetSourcePath -Recurse |
    where { [System.IO.Path]::GetExtension($_.Name) -ieq ".sln" } |
    foreach {
        $solution = Get-Content $_.FullName
        $inTfsBlock = $false
        $solution | 
            foreach { 
                if( $_.Trim() -eq "GlobalSection(TeamFoundationVersionControl) = preSolution" )
                    { $inTfsBlock = $true }
                
                if( $inTfsBlock )
                {
                    if( $_.Trim() -eq "EndGlobalSection" )
                        { $inTfsBlock = $false }
                }
                else
                    { $_ }
            } | 
            sc $_.FullName -Encoding UTF8
    }

Get-ChildItem -LiteralPath $targetSourcePath -Recurse | 
    where { ".csproj",".vbproj" -icontains [System.IO.Path]::GetExtension($_.Name) } |
    foreach {
        $xml = [xml](Get-Content $_.FullName)
        $xml.SelectNodes("//*[starts-with(local-name(), 'Scc')]") | foreach { $_.RemoveAll() }
        $xml.Project.PropertyGroup | where { $_.PreBuildEvent -and $_.PreBuildEvent.StartsWith("PowerShell.exe") } | foreach { $_.PreBuildEvent = "REM " + $_.PreBuildEvent }
        $xml.Save($_.FullName)
    }

Write-Host "Copying distribution items"    
$distItems | foreach { Copy-Item $(Join-Path $scriptPath $_) $distPath -Recurse }
Get-ChildItem -LiteralPath $distPath | foreach { $_.Attributes = $_.Attributes -band (-bnot ([System.IO.FileAttributes]::ReadOnly -bor [System.IO.FileAttributes]::Hidden)) } 

Write-Host "Creating files for NuGet"
$nugetSourcePath = Join-Path $scriptPath "NuGet"
$nugetPath = Join-Path $TargetPath "nuget"
$nugetDistPath = Join-Path $nugetPath $nugetPackageName
$nugetDistSourcePath = Join-Path (Join-Path $nugetDistPath "src") "Ookii.CommandLine"
$nugetLibPath = Join-Path $nugetDistPath "lib"
New-Item $nugetLibPath -ItemType Directory -Force | Out-Null
New-Item $nugetDistSourcePath -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $nugetSourcePath "$nugetPackageName.nuspec") $nugetDistPath
$nugetLibItems | ForEach-Object { Copy-Item (Join-Path $scriptPath $_) $nugetLibPath -Recurse }
Copy-Item (Join-Path (Join-Path $targetSourcePath "Ookii.CommandLine") "*") $nugetDistSourcePath -Recurse
Get-ChildItem $nugetDistSourcePath -Recurse | Where-Object { !$_.PSIsContainer -and $_.Extension -ne ".cs" } | Remove-Item

$nugetSamplePath = Join-Path $nugetPath "$nugetPackageName.Sample"
$nugetContentPath = Join-Path $nugetSamplePath "content"
$nugetToolsPath = Join-Path $nugetSamplePath "tools"
New-Item $nugetContentPath -ItemType Directory -Force | Out-Null
New-Item $nugetToolsPath -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $nugetSourcePath "$nugetPackageName.Sample.nuspec") $nugetSamplePath
$nugetSampleContentItems | ForEach-Object { Copy-Item (Join-Path $scriptPath $_) $nugetContentPath -Recurse }
$nugetSampleToolsItems | ForEach-Object { Copy-Item (Join-Path $scriptPath $_) $nugetToolsPath -Recurse }

Write-Host "Packing nuget packages"
nuget pack (Join-Path "$nugetDistPath" "$nugetPackageName.nuspec") -OutputDirectory $nugetPath -Symbols
nuget pack (Join-Path "$nugetSamplePath" "$nugetPackageName.Sample.nuspec") -OutputDirectory $nugetPath