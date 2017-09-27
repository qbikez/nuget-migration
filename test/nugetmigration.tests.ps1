param($inputPath = $null)

. $PSScriptRoot\includes.ps1

if ($inputPath -ne $null) {
    $i = get-item $inputPath
    if ($i.PsIsContainer) {
        $inputDir = $i
    } else {
        $inputFile = split-path -Leaf $inputPath
        $inputDir = Split-Path -Parent $inputPath
    }
}
if ($inputDir -eq $null) { $inputDir = "$psscriptroot\input" }

if ($inputFile -ne $null) {
    if ($inputFile.EndsWith(".sln")) {
        $sln = import-sln "$inputDir\$inputFile"
        $projects = get-slnprojects -sln $sln
        $projects = $projects | % { get-item $_.fullname }
    }
    elseif ($inputFile.EndsWith(".csproj")) {
        $projects = @(get-item $inputFile)
    } 
    else {
        throw "unrecognized input file"
    }
}
else {
    $projects = Get-ChildItem $inputDir "*.csproj" -Recurse
}

$projects = $projects | % { 
    $null = $_ | add-member -name "RelDir" -value (get-relativepath "$inputDir" $_.directory) -membertype noteproperty
    $_
}

Describe "migration build tests" {
    copy-item "$inputDir\*" "testdrive:" -Recurse
    if (test-path "$psscriptroot\out") { remove-item "$psscriptroot\out" -Recurse -Force -Confirm:$false }
    if (!(test-path "$psscriptroot\out\before")) { $null = mkdir "$psscriptroot\out\before" }
    if (!(test-path "$psscriptroot\out\after")) { $null = mkdir "$psscriptroot\out\after" }

    In "testdrive:\" {
        $root = $pwd.Path
        foreach ($project in $projects) {
            $reldir = $project.RelDir

            Context "project: $($project.RelDir)" {                
                In "$($project.RelDir)" {   
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
                            ConvertFrom-PackagesConfigToPackageReferences $csproj.FullName -verbose
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
    copy-item "$inputDir\*" "testdrive:" -Recurse
    In "testdrive:\" {
        $root = $pwd.Path
        foreach ($project in $projects) {
            $reldir = $project.RelDir

            Context "project: $($project.RelDir)" {                
                In "$($project.RelDir)" {   

                    It "Should migrate" {
                        $csproj = get-childitem "." "*.csproj"                        
                        #{
                            ConvertFrom-PackagesConfigToPackageReferences $csproj -verbose
                        #} | Should Not Throw
                    }
                    
                    $csprojFiles = get-childitem "." "*.csproj"
                    $csproj = csproj\import-csproj $csprojFiles

                    It "Should remove obsolete compile entries" {
                        $csproj.Xml.project.ItemGroup.Compile | Should BeNullOrEmpty
                    }
                    It "Should add Sdk attribute" {
                        $csproj.Xml.project.Sdk | Should Not BeNullOrEmpty
                    }
                    It "Should remove obsolete target imports" {
                        $csproj.Xml.project.Import | where { $_.project -match "Microsoft.CSharp.targets" } | Should BeNullOrEmpty
                    }
                    It "Should not include packages.config" {
                        $csproj.Xml.project.ItemGroup.None | where { $_.Include -eq 'packages.config'} | Should BeNullOrEmpty                    
                    }
                }
            }   
        }
    }
}

Describe "nuget tests" {
    copy-item "$inputDir\*" "testdrive:" -Recurse
    if (test-path "$psscriptroot\out") { remove-item "$psscriptroot\out" -Recurse -Force -Confirm:$false }
    if (!(test-path "$psscriptroot\out\before")) { $null = mkdir "$psscriptroot\out\before" }
    if (!(test-path "$psscriptroot\out\after")) { $null = mkdir "$psscriptroot\out\after" }

    In "testdrive:\" {
        $root = $pwd.Path
        
        foreach ($project in $projects) {
            $reldir = $project.RelDir

            Context "project: $($project.RelDir)" {                
                In "$($project.RelDir)" {   
                    $versionStable = "1.2.3"
                    It "should pack stable before" {
                        Update-BuildVersion -version $versionStable  
                        $nuget = pack-nuget $($project.name) -Build -Stable
                        $nuget = split-path -leaf $nuget
                        $nugetname = $($project.name) -replace ".csproj",""
                        $nuget | should Be "$nugetname.$versionStable.nupkg"
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
                    It "should pack with msbuild after" {
                        invoke msbuild /t:pack $($project.name)
                        $LASTEXITCODE | should be 0
                    }

                    It "should pack stable with nupkg after" {
                        $nuget = pack-nuget $($project.name) -Build -Stable
                        $nuget = split-path -leaf $nuget
                        $nugetname = $($project.name) -replace ".csproj",""
                        $nuget | should Be "$nugetname.$versionStable.nupkg"
                    }

                    $outDir = "$psscriptroot\out\after\$reldir"
                    if (!(test-path $outDir)) { $null = mkdir $outDir }
                    copy-item "*" $outDir -Recurse -Force
                }
            }   
        }
    }

}