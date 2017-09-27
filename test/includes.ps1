. $PSScriptRoot\..\src\NugetMigration.ps1

ipmo require
req pester 4.0.8
req process
req pathutils

# for some reason, process output gets colored in red when launching tests from vscode
$env:PS_PROCESS_OUTPUT="verbose"
# set this to true to see invoked process output
$env:PS_PROCESS_VERBOSE=$false

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