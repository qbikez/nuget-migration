. $PSScriptRoot\..\src\Invoke-NugetMigration.ps1

ipmo require
req pester
req process
req pathutils


function get-msbuildPath($version = $null)
{
  try {
        if ($version -eq 15) {
            $paths = @(
                "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Preview\Enterprise\MSBuild\15.0\bin"
            )

            foreach($p in $paths) {
                if (Test-Path "$p\msbuild.exe") { return $p }
            }            
        }
        $versions = (gci HKLM:\SOFTWARE\Microsoft\MSBuild\ToolsVersions) | sort -Descending @{ expression={ 
        $_.Name | split-path -Leaf | % { 
            [double]::Parse($_, [System.Globalization.CultureInfo]::InvariantCulture) 
            }
        }}
        if ($version -ne $null) {
            $ver = $versions | ? {
                 ($_.Name | split-path -Leaf | % { 
            [double]::Parse($_, [System.Globalization.CultureInfo]::InvariantCulture) 
            }) -eq $version
            }
        }
        
        else {
            $ver = $versions | select -First 1
        }
        $path = Get-ItemProperty -path "hklm:/$($ver.Name)" -Name MSBuildToolsPath     
        $path = $path.MSBuildToolsPath  
        write-host "found msbuild version $($ver.Name) at $path"
        return $path
    }   
    catch {
        return $null
    }
}

get-msbuildpath -version 15 | Add-ToPath -first