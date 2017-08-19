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

function Invoke-NugetMigration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $csproj
    )

    Write-Verbose "migrating project '$csproj' to PackageReference format"
    Write-Verbose "doing backup"
    _doBackup $csproj

    Write-Warning "This is not implemented yet"

    Write-Verbose "Done"
}