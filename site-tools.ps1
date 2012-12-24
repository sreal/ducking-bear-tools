
##
# . ./site_tools.ps1
# sre, 2012-12-24
#
# ./backup_database [-Config-File CONFIG.XML  |  -server SERVER -database DATABASE  -username USR -password PWD]
# ./backup_folder [-Config-File CONFIG.XML |-Source DIRECTORY -Destination DESTINATION ]
# ./setup_iis [-Config-File CONFIG.XML ]
#
# ./backup_database -Config-File RAAF-STAGE.xml
# ./backup_database -config-File RAAF-STAGE.xml
# ./setup_iis -Config-File RAAF-STAGE.xml

#./psake Backup-Database -Parameters { 'config-file' = 'config/RAAF-stage.xml' }


Function Backup-DataBase {
[CmdletBinding()]
Param(
  [string] $Config-File,
  [string] $Server,
  [string] $Database,
  [string] $Username,
  [string] $Password,
  [Switch] $Remote,
  [string] $Remote-Username,
  [string] $Remote-Password
)

}


Function Load-Config {
[CmdletBinding()]
Param(
  [Parameter][String] $File    = 'default.xml',
)

  Write-Verbose Testing File Path $File

  if (-not (Test-Path $File) ) {
    Write-Error File Path Not Valid  [ $File ]
    Exit
  }

  [xml]$xml = Get-Content $File
  return $xml.Project
}


Backup-DataBase -Config-File 'config/test.xml'