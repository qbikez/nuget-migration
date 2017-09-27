# A good guide:
# http://www.natemcmaster.com/blog/2017/03/09/vs2015-to-vs2017-upgrade/
# 
$script:ns = 'http://schemas.microsoft.com/developer/msbuild/2003'

ipmo require
req csproj


function _doBackup {
    param($csproj)

    $dir = (get-item $csproj).Directory
    pushd 
    try {
        cd $dir
        $backupDir = "_backup"
        if (test-path $backupDir) {
            mv $backupDir "_backup_$(get-date -format "yyyyMMdd_HHmmss")"
        }
        $null = mkdir $backupDir

        cp *.csproj $backupDir
        cp *.nuspec $backupDir
        if (test-path packages.config) { cp packages.config $backupDir }
        if (test-path project.json) { cp project.json $backupDir }
    }
    finally {
        popd
    }
}

function ConvertFrom-PackagesConfigToPackageReferences {
    [CmdletBinding()]
    param(
        [Alias("csproj")]
        [Parameter(Mandatory = $true)]
        $project
    )
    $csproj = $project

    if ($csproj -isnot [csproj]) {
        $path = $csproj
        if ($path.endswith(".csproj")) {
            $csproj = csproj\import-csproj $path
        }
        elseif ($path.EndsWith(".sln")) {
            $sln = import-sln $path
            $projects = get-slnprojects -sln $sln
            $projects = $projects | % { get-item $_.fullname }
            foreach($project in $projects) {
                ConvertFrom-PackagesConfigToPackageReferences $project.FullName
            }
            return
        }
        else {
            throw "don't know how to handle file '$path'. Please specify a csproj or sln file"
        }        
    }
    
    Write-Verbose "migrating project '$($csproj.Name)' to PackageReference format"
    Write-Verbose "doing backup"
    _doBackup $csproj.path

    pushd
    
    try {
        cd (split-path -Parent $csproj.path)

        if ((test-path "packages.config")) {
            $null = _convertPackagesConfig $csproj
            $node = $csproj.Xml.project.ItemGroup.None | where { $_.Include -eq 'packages.config'} 
            if ($node -ne $null) {
                $null = $node.ParentNode.RemoveChild($node)
            }
            $null = remove-item "packages.config"
        }

        $null = Remove-ObsoleteProjectItems $csproj
        $null = _AddSdkAttribute $csproj
        
        $null = $csproj.save()

        Write-Verbose "Done"
    } finally {
        popd
    }
}

function _convertPackagesConfig {
    param($csproj)
    
    $packagesConfig = csproj\import-packagesConfig "packages.config"
    
    $oldRefs = csproj\get-nugetreferences $csproj

    write-verbose "will convert $($oldrefs) nuget references to PackageReferences"

    $newRefs = @()
    foreach ($pkg in $packagesConfig.packages) {
        $ref = New-NugetReferenceNode $csproj.xml
        $ref.Include = $pkg.Id
        $ref.Version = $pkg.Version
    
        $newRefs += $ref
    }
    $null = $oldRefs | % { $_.Node.ParentNode.RemoveChild($_.Node)}
    
    $other = get-nodes $csproj.xml -nodeName "ItemGroup"
    $lastItemGroup = $null
    if ($other.Count -gt 0) {
        $last = ([System.Xml.XmlNode]$other[$other.Count - 1].Node)
    }
    
    $itemgroup = [System.Xml.XmlElement]$csproj.xml.CreateNode([System.Xml.XmlNodeType]::Element, "", "ItemGroup", $ns)
    $newRefs | % {         
        $null = $itemgroup.AppendChild($_)        
    }

    if ($lastItemGroup -ne $null) {
        $null = $lastItemGroup.ParentNode.InsertAfter($itemgroup, $lastItemGroup)
        $lastItemGroup = $itemgroup
    }
    else {
        $null = $csproj.xml.project.AppendChild($itemgroup)
        $lastItemGroup = $itemgroup
    }   
}


function _AddSdkAttribute {
    param($csproj)

    $group = $null

    if ($csproj.xml.project.Sdk -ne $null) {
        write-verbose "project $csproj already has sdk=$($csproj.xml.project.Sdk)"
        $group = $csproj.xml.project.PropertyGroup | select -first 1
    }
    else {
        # Add Sdk attribute
        $attr = [System.Xml.XmlAttribute]$csproj.xml.CreateAttribute("Sdk")

        $null = $csproj.xml.project.Attributes.Append($attr)
        $csproj.xml.project.Sdk = "Microsoft.NET.Sdk"
    }

    if ($group -eq $null) { 
        $group = [System.Xml.XmlElement]$csproj.xml.CreateNode([System.Xml.XmlNodeType]::Element, "", "PropertyGroup", $ns)
        $csproj.Xml.project.InsertBefore($group, $csproj.Xml.project.FirstChild)
     }


    $targetFx = $csproj.xml.project.PropertyGroup.TargetFrameworkVersion |? { $_ -ne $null } 
    if (@($targetFx).Count -gt 1) {
        Write-Warning "project $csproj has $(@($targetFx).Count) TargetFrameworkVersions: $targetfx"
        $targetFx = $targetFx | select -first 1
    }
    if (@($targetFx).Count -eq 0) {
        Write-Warning "project $csproj has no TargetFrameworkVersion property"
        return
    }
    $targetFramework = $targetFx.Replace("v","net").Replace(".","")

    $null = _AddMsbuildProperty TargetFramework $targetFramework -group $group
    $null = _AddMsbuildProperty GenerateAssemblyInfo "$false" -group $group

    # remove obsolete target imports
    $toremove = '$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props','$(MSBuildToolsPath)\Microsoft.CSharp.targets','$(SolutionDir)\.nuget\NuGet.targets' 

    $imports = $csproj.xml.project.Import | ? { $_.Project -in $toremove }
    foreach($import in $imports) {
        Write-Verbose "removing '$($import.Project)' import"
        $null = $import.ParentNode.RemoveChild($import)
    }

    
}

function _AddMsbuildProperty {
    param([Parameter(Mandatory=$true)]$name, [Parameter(Mandatory=$true)]$value, [Parameter(Mandatory=$false)]$group)

    $addgroup = $false
    if ($group -eq $null) {
        $group = [System.Xml.XmlElement]$csproj.xml.CreateNode([System.Xml.XmlNodeType]::Element, "", "PropertyGroup", $ns)
        $addgroup = $false
    }
    
    if ($csproj.xml.project.PropertyGroup.$name -ne $null) {
        write-verbose "project $csproj already has '$name' property = '$($csproj.xml.project.PropertyGroup.$name)'"
    }
    else {
        Write-Verbose "adding property $name=$value"    
        $node = [System.Xml.XmlElement]$csproj.xml.CreateNode([System.Xml.XmlNodeType]::Element, "", $name, $ns)    
        $null = $group.AppendChild($node)
        $group.$name = $value
    }

    if ($addgroup) {
        $null = $csproj.Xml.project.InsertBefore($group, $csproj.Xml.project.FirstChild)
    }
    
}

function Remove-ObsoleteProjectItems {
    param([csproj]$csproj)

    foreach ($item in $csproj.Xml.project.ItemGroup) {
        if ($item.Compile -ne $null) {
            $null = $item.ParentNode.RemoveChild($item)
        }
    }
}


function New-NugetReferenceNode([System.Xml.xmldocument]$document) {
    <#
       <ProjectReference Include="..\xxx\xxx.csproj">
         <Project>{89c414d8-0258-4a94-8e45-88b338c15e7a}</Project>
         <Name>xxx</Name>
       </ProjectReference>
    #>
    $projectRef = [System.Xml.XmlElement]$document.CreateNode([System.Xml.XmlNodeType]::Element, "", "PackageReference", $ns)

    $idAttr = [System.Xml.XmlAttribute]$document.CreateAttribute("Include")
    $null = $projectRef.Attributes.Append($idAttr)
    $versionAttr = [System.Xml.XmlAttribute]$document.CreateAttribute("Version")
    $null = $projectRef.Attributes.Append($versionAttr)

    return $projectRef
}