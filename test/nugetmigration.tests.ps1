ipmo require
req pester

. $PSScriptRoot\includes.ps1

Describe "Nuget migration tests" {
    copy-item "$psscriptroot\input\*" "testdrive:" -Recurse
    In "testdrive:\" {
        It "Should do backup before processing csproj" {
            $csproj = "project1\project1.csproj"
            invoke-nugetmigration $csproj
            test-path "project1\_backup\project1.csproj" | should be $true
            test-path "project1\_backup\packages.config" | should be $true
        }  
    }
}