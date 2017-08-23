. $PSScriptRoot\..\src\NugetMigration.ps1

ipmo require
req pester
req process
req pathutils

. $PSScriptRoot\..\scripts\_helpers.ps1

# check if msbuild 15 is on path
$msbuild = where-is msbuild
if ($msbuild -ne $null) {
    $v = msbuild /version | select -last 1   
    if (!$v.startswith("15.")) { $msbuild = $null }
}

# if it isn't try to find it
if ($msbuild -eq $null) {
    get-msbuildpath -version 15 |? { $_ -ne $null } | Add-ToPath -first
}

$msbuild = where-is msbuild

write-verbose "msbuild found at:" -Verbose
$msbuild | format-table | out-string | write-verbose -Verbose