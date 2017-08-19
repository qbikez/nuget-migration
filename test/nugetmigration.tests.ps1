. $PSScriptRoot\includes.ps1

Describe "Nuget migration tests" {
    copy-item "$psscriptroot\input\*" "testdrive:" -Recurse
    In "testdrive:\" {
        $root = $pwd.Path
        $projects = Get-ChildItem "." "*.csproj" -Recurse
        foreach ($project in $projects) {
            Context "project: $($project.directory)" {
                In "$($project.directory)" {   
                    It "should restore before" {
                        invoke nuget restore $($project.name)
                        $LASTEXITCODE | should be 0
                    }
                    It "should build before" {
                        invoke msbuild $($project.name)
                        $LASTEXITCODE | should be 0
                    }

                    It "should migrate" {
                        $csproj = get-childitem "." "*.csproj"                        
                        #{
                            invoke-nugetmigration $csproj -verbose
                        #} | Should Not Throw
                    }

                    It "should remove packages.config after migration" {
                        test-path "packages.config" | should be $false
                    }
                    It "Should do backup" {
                        $csproj = get-childitem "." "*.csproj"
                        test-path "_backup\$($csproj.name)" | should be $true
                    }                 
                   
                    It "should restore after" {
                        rmdir $root/packages -Force -Confirm:$false -Recurse
                        invoke msbuild /t:restore $($project.name)
                        $LASTEXITCODE | should be 0
                    }
                    It "should build after" {
                        invoke msbuild $($project.name)
                        $LASTEXITCODE | should be 0
                    }
                }
            }
        }
    }
    if (!(test-path "$psscriptroot\out\")) { $null = mkdir "$psscriptroot\out\" }
    copy-item "testdrive:\*"  "$psscriptroot\out\" -Recurse -Force
}