& "$PSScriptRoot\lib\init.ps1"

install-module require -MinimumVersion 1.1.7.110 -verbose
ipmo require
req pester 4.0.8 -SkipPublisherCheck

. $PSScriptRoot\_helpers.ps1


$p = get-msbuildpath -version 15

if ($p -eq $null) {
    # build tools aren't enough: https://github.com/dotnet/sdk/issues/892
    # this version is missing nuget restore targets, which are installed with vs2017 ('Nuget package manager' component)
    # see also https://stackoverflow.com/questions/42696948/how-can-i-install-the-vs2017-version-of-msbuild-on-a-build-server-without-instal

    # nuget restore targets are imported in C:\Program Files (x86)\Microsoft Visual Studio\2017\BuildTools\MSBuild\15.0\Microsoft.Common.Targets\ImportAfter\Microsoft.NuGet.ImportAfter.targets
    # from $(MSBuildExtensionsPath)\..\Common7\IDE\CommonExtensions\Microsoft\NuGet\NuGet.targets
    # or $(NuGetRestoreTargets) if it is set
    

    choco install -y microsoft-build-tools -v 15.0.26228.0
}
