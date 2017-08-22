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
        [Parameter(Mandatory = $true)]
        $csproj
    )

    if ($csproj -isnot [csproj]) {
        $csproj = csproj\import-csproj $csproj
    }
    
    Write-Verbose "migrating project '$($csproj.Name)' to PackageReference format"
    Write-Verbose "doing backup"
    _doBackup $csproj.path

    
    
    if ((test-path "packages.config")) {
        _convertPackagesConfig $csproj
        remove-item "packages.config"
    }

    Remove-ObsoleteProjectItems $csproj
    _AddSdkAttribute $csproj
    
    $csproj.save()

    Write-Verbose "Done"
}

function _convertPackagesConfig {
    param($csproj)
    
    $packagesConfig = csproj\import-packagesConfig "packages.config"
    
    $oldRefs = csproj\get-nugetreferences $csproj
    $newRefs = @()
    foreach ($pkg in $packagesConfig.packages) {
        $ref = New-NugetReferenceNode $csproj.xml
        $ref.Include = $pkg.Id
        $ref.Version = $pkg.Version
    
        $newRefs += $ref
    }
    $oldRefs | % { $_.Node.ParentNode.RemoveChild($_.Node)}
    
    $other = get-nodes $csproj.xml -nodeName "ItemGroup"
    $lastItemGroup = $null
    if ($other.Count -gt 0) {
        $last = ([System.Xml.XmlNode]$other[$other.Count - 1].Node)
    }
    
    $newRefs | % { 
        $itemgroup = [System.Xml.XmlElement]$csproj.xml.CreateNode([System.Xml.XmlNodeType]::Element, "", "ItemGroup", $ns)            
        $itemgroup.AppendChild($_)
        if ($lastItemGroup -ne $null) {
            $null = $lastItemGroup.ParentNode.InsertAfter($itemgroup, $lastItemGroup)
            $lastItemGroup = $itemgroup
        }
        else {
            $null = $csproj.xml.project.AppendChild($itemgroup)
            $lastItemGroup = $itemgroup
        }   
    }
}


function _AddSdkAttribute {
    param($csproj)

    if ($csproj.xml.project.Sdk -ne $null) {
        write-verbose "project $csproj already has sdk=$($csproj.xml.project.Sdk)"
        return
    }

    # Add Sdk attribute

    $attr = [System.Xml.XmlAttribute]$csproj.xml.CreateAttribute("Sdk")

    $null = $csproj.xml.project.Attributes.Append($attr)
    $csproj.xml.project.Sdk = "Microsoft.NET.Sdk"
    
    # Add TargetFramework property

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

    $group = [System.Xml.XmlElement]$csproj.xml.CreateNode([System.Xml.XmlNodeType]::Element, "", "PropertyGroup", $ns)

    Write-Verbose "adding property TargetFramework=$targetFramework"    
    $frameworkNode = [System.Xml.XmlElement]$csproj.xml.CreateNode([System.Xml.XmlNodeType]::Element, "", "TargetFramework", $ns)    
    $group.AppendChild($frameworkNode)
    $group.TargetFramework = $targetFramework

    # Add GenerateAssemblyInfo property
    
    Write-Verbose "adding property GenerateAssemblyInfo=$false"
    $asmNode = [System.Xml.XmlElement]$csproj.xml.CreateNode([System.Xml.XmlNodeType]::Element, "", "GenerateAssemblyInfo", $ns)
    $group.AppendChild($asmNode)
    $group.GenerateAssemblyInfo = "$false"

    write-verbose "adding PropertyGroup with new properties"
    $csproj.Xml.project.InsertBefore($group, $csproj.Xml.project.FirstChild)
    
    # remove obsolete target imports
    $toremove = '$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props','$(MSBuildToolsPath)\Microsoft.CSharp.targets' 

    $imports = $csproj.xml.project.Import | ? { $_.Project -in $toremove }
    foreach($import in $imports) {
        Write-Verbose "removing '$($import.Project)' import"
        $import.ParentNode.RemoveChild($import)
    }

    
}


function Remove-ObsoleteProjectItems {
    param([csproj]$csproj)

    foreach ($item in $csproj.Xml.project.ItemGroup) {
        if ($item.Compile -ne $null) {
            $item.ParentNode.RemoveChild($item)
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