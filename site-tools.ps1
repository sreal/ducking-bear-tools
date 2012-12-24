
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
  [String] $ConfigFile,
  [string] $Server,
  [string] $Database,
  [string] $Username,
  [string] $Password,
  [Switch] $Remote,
  [string] $RemoteUsername,
  [string] $RemotePassword
)

  $SQL_database_backup = "
BEGIN TRY
    BEGIN TRANSACTION

USE [[catalogue]]

        BACKUP DATABASE [[catalogue]]
        TO DISK = '[[backup]]'
            WITH FORMAT,
              NAME = 'Full Backup of [[catalogue]] dated [[date]]'

    COMMIT TRAN
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN
END CATCH
GO
"


  Write-Verbose 'Getting Configuration'
  $cfg = Get-Config $ConfigFile

  $super_usr = $cfg.Database.user.name
  $super_pwd = $cfg.Database.user.password
  $backup_dir= $cfg.Database.backup.dir
  $server    = $cfg.Database.connection.server
  $catalogue = $cfg.Database.connection.catalogue
  $usr       = $cfg.Database.connection.username
  $pwd       = $cfg.Database.connection.password

  $date      = Get-Date -Format yyyyMMdd
  $time      = Get-Date -Format HHmm

  Write-Verbose "Setting up backup location"
  $backup_dir= "{0}\{1}" -F $backup_dir, $date
  New-Item $backup_dir -Type Directory -ErrorAction SilentlyContinue

  $backup    = "{0}\{1}{2}_{3}.bak" -F $backup_dir, $date, $time, $catalogue


  Write-Verbose "Injecting Config into Database Script"
  $SQL_database_backup = $SQL_database_backup.Replace( "[[catalogue]]", $catalogue)
  $SQL_database_backup = $SQL_database_backup.Replace( "[[backup]]", $backup)
  $SQL_database_backup = $SQL_database_backup.Replace( "[[date]]", (Get-Date -Format yyyyMMdd))
  $SQL_database_backup = $SQL_database_backup.Replace( "[[time]]", (Get-Date -Format HHmm))

  Write-Verbose "Running SQL Command"
  $sql_result = sqlcmd -S $server -U $super_usr -P $super_pwd -Q $SQL_database_backup -V1
  $sql_success = $?
  if (-not $sql_success ) {
    Write-Error "Sql did not run successfully"
    Write-Verbose "$sql_result"
    Write-Verbose $SQL_database_backup
    Exit
  }

  Write-Verbose "SQL Command Finished"
  Write-Host "
Database successfully backed up.

Location:
  Server: $server
  File:   $backup

Thanks for playing...
"

}


Function Get-Config {
[CmdletBinding()]
Param(
  [string]$File
)

  Write-Verbose "Testing File Path $File"

  if (-not (Test-Path $File) ) {
    Write-Error File Path Not Valid  [ $File ]
    Exit
  }

  [xml]$xml = Get-Content $File
  return $xml.Project
}


Backup-DataBase -ConfigFile "config/default.xml" -Verbose
