. $PSScriptRoot\includes.ps1

Describe "migration build tests" {
    copy-item "$psscriptroot\input\*" "testdrive:" -Recurse
    remove-item "$psscriptroot\out" -Recurse -Force -Confirm:$false
    if (!(test-path "$psscriptroot\out\before")) { $null = mkdir "$psscriptroot\out\before" }
    if (!(test-path "$psscriptroot\out\after")) { $null = mkdir "$psscriptroot\out\after" }

    In "testdrive:\" {
        $root = $pwd.Path
        $projects = Get-ChildItem "." "*.csproj" -Recurse
        
        foreach ($project in $projects) {
            $reldir = get-relativepath "." $project.directory

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

                    $outDir = "$psscriptroot\out\before\$reldir"
                    if (!(test-path $outDir)) { $null = mkdir $outDir }
                    copy-item "*" $outDir -Recurse -Force
                    remove-item ".\bin" -Recurse -Force
                    remove-item ".\obj" -Recurse -Force

                    It "should migrate" {
                        $csproj = get-childitem "." "*.csproj"                        
                        #{
                            ConvertFrom-PackagesConfigToPackageReferences $csproj -verbose
                        #} | Should Not Throw
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

                    $outDir = "$psscriptroot\out\after\$reldir"
                    if (!(test-path $outDir)) { $null = mkdir $outDir }
                    copy-item "*" $outDir -Recurse -Force
                }
            }   
        }
    }

}
Describe "packages.config to PackageReferences migration tests" {  
    copy-item "$psscriptroot\input\*" "testdrive:" -Recurse
    In "testdrive:\" {
        $root = $pwd.Path
        $projects = Get-ChildItem "." "*.csproj" -Recurse
        foreach ($project in $projects) {
            $reldir = get-relativepath "." $project.directory

            Context "project: $($project.directory)" {                
                In "$($project.directory)" {   

                    It "should migrate" {
                        $csproj = get-childitem "." "*.csproj"                        
                        #{
                            ConvertFrom-PackagesConfigToPackageReferences $csproj -verbose
                        #} | Should Not Throw
                    }
                    
                    It "should remove obsolete compile entries" {
                        $csprojFiles = get-childitem "." "*.csproj"
                        $csproj = csproj\import-csproj $csprojFiles
                        $csproj.Xml.project.ItemGroup.Compile | Should BeNullOrEmpty
                    }
                }
            }   
        }
    }
    
}