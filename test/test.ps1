param ($path = ".")

import-module pester -MinimumVersion 3.3.14

$artifacts = "$path\artifacts"
if (!(test-path $artifacts)) { $null = new-item -type directory $artifacts }

write-host "running tests. artifacts dir = $((gi $artifacts).FullName)"

$r = Invoke-Pester "$path" -OutputFile "$artifacts\test-result.xml" -OutputFormat NUnitXml 

return $r
