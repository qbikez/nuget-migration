
function get-msbuildPath {
    [CmdletBinding()]
    param($version = $null)

    ipmo require
    req pathutils

    try {

        # check if msbuild 15 is on path
        $msbuild = where-is msbuild
        if ($msbuild -ne $null) {
            if ($v -ne $null) {
                $v = msbuild /version | select -last 1   
                if (!$v.startswith($version)) { $msbuild = $null }
            }
        }

        # if it isn't try to find it
        if ($msbuild -ne $null) {
            return $msbuild | select -ExpandProperty Source -First 1
        }

        if ($version -eq 15) {
            $paths = @(
                "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\*\MSBuild\15.0\Bin\"
                "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Preview\*\MSBuild\15.0\Bin\"
                "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\BuildTools\MSBuild\15.0\Bin\"
            )
            $expandendPaths = @()
            # expand wildcards
            foreach ($p in $paths) {
                if ($p.Contains("*")) {
                    $before = $p.substring(0, $p.indexof("*"))
                    if (test-path $before) {
                        $dirs = get-childitem $before -Directory | select -ExpandProperty Name
                        foreach ($d in $dirs) {
                            $path = $p.replace("*", $d)
                            if ($paths -contains $path) {
                                continue
                            }
                            $expandendPaths += $path
                            write-verbose "will search on path '$path'"                        
                        }
                    }
                    else {
                        write-verbose "checking path '$before'.. NOT FOUND"                        
                    }
                }
                else {
                    $expandendPaths += $p
                }
            }
            $paths = $expandendPaths
            foreach ($p in $paths) {
                write-verbose "looking for msbuild at path '$p'"
                if (Test-Path "$p\msbuild.exe") { return $p }
            }
                  
        }
        $versions = (gci HKLM:\SOFTWARE\Microsoft\MSBuild\ToolsVersions) | sort -Descending @{ expression = { 
                $_.Name | split-path -Leaf | % { 
                    [double]::Parse($_, [System.Globalization.CultureInfo]::InvariantCulture) 
                }
            }
        }
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