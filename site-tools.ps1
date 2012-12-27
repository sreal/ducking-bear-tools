##
# . ./site_tools.ps1
# sre, 2012-12-24
#
# ./Backup-Database -Config-File CONFIG.XML
# ./Backup-Folder   -Config-File CONFIG.XML
#
# Requirements: PowerShell v3 [PSScheduledJob]


Function Backup-Folder {
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true)][String] $ConfigFile
)
  Try {
    Write-Verbose 'Getting Configuration'
    $cfg = Get-Config $ConfigFile
    $backup_dir= $cfg.Backup.site.location
    $root_dir  = $cfg.Site.root.location
    $files     = $cfg.Site.Include

    $backup_dir= Setup-Destination-Directory $backup_dir -create
    Write-Verbose "Copy File Includes"
    $files | % {
      $path = Join-Path $root_dir $_.path
      if ($_.path -eq '*') {
          Copy-Item $path $backup_dir -Recurse -Force
      } else {
        if (Test-Path -PathType Leaf $path) {
            Copy-Item -Force $path $backup_dir
        }
        if (Test-Path -PathType Container $path) {
            Copy-Item -Recurse -Force $path $backup_dir
        }
      }
    }

    Write-Verbose "Folder Backup Completed"
    Write-Host "
  Folder successfully backed up.

Location:
  Files:   $backup_dir

Thanks for playing...
"
  } Catch [Exception] {
    Write-Error $_.Exception.Message
  }
}



Function Backup-DataBase {
[CmdletBinding()]
Param(
  [String] $ConfigFile
)
  $SQL_database_backup = "
USE [[catalogue]]
BACKUP DATABASE [[catalogue]]
    TO DISK = '[[backup]]'
        WITH FORMAT,
            NAME = 'Full Backup of [[catalogue]] to [[backup]]'
GO
"


  Write-Verbose 'Getting Configuration'
  $cfg = Get-Config $ConfigFile

  $super_usr = $cfg.Database.user.name
  $super_pwd = $cfg.Database.user.password
  $server    = $cfg.Database.connection.server
  $catalogue = $cfg.Database.connection.catalogue
  $usr       = $cfg.Database.connection.username
  $pwd       = $cfg.Database.connection.password
  $backup_dir= $cfg.Backup.database.location

  $date      = Get-Date -Format yyyyMMdd
  $time      = Get-Date -Format HHmm

  $backup_dir= Setup-Destination-Directory $backup_dir
  $backup    = "{0}\{1}{2}_{3}.bak" -F $backup_dir, $date, $time, $catalogue

  Write-Verbose "Injecting Config into Database Script"
  $SQL_database_backup = $SQL_database_backup.Replace( "[[catalogue]]", $catalogue)
  $SQL_database_backup = $SQL_database_backup.Replace( "[[backup]]", $backup)

  Write-Verbose "Running SQL Backup Command"

  $sql_result = sqlcmd -S $server -U $super_usr -P $super_pwd -Q $SQL_database_backup -V1
  $sql_success = $?
  if (-not $sql_success ) {
    Write-Error "Sql did not run successfully"
    Write-Verbose "$sql_result"
    Write-Debug $SQL_database_backup
  } else {

    Write-Host "
Database successfully backed up.

Location:
  Server: $server
  File:   $backup

Thanks for playing...
"
  }
}


Function Setup-Destination-Directory {
[CmdletBinding()]
Param(
  [string] $Directory,
  [switch] $create
)
  Write-Verbose "Setting up backup location"
  $Directory= "{0}\{1}" -F $Directory, (Get-Date -F yyyyMMdd)
  if ($create) {
    if (-not (Test-Path $Directory) ) {
      New-Item $Directory -Type Directory | Out-Null
    }
  }
  $Directory
}


Function Get-Config {
[CmdletBinding()]
Param(
  [string]$File
)
  if (-not (Test-Path $File) ) {
    Write-Error "File Path Not Valid  [ $File ]"
    Exit
  }
  [xml]$xml = Get-Content $File
  return $xml.Project
}


Function Create-Schedule {
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true)][String] $ConfigFile
)
  Try {
    Import-Module PSScheduledJob

    $this_file = $PSCommandPath

    Write-Verbose 'Getting Configuration'
    $cfg = Get-Config $ConfigFile
    $name = $cfg.Schedule.Job.name
    $time = $cfg.Schedule.Job.time

    Write-Verbose 'Unregistering Job'
    Unregister-ScheduledJob $name -ErrorAction SilentlyContinue


    Write-Verbose 'Creating Trigger'
    $trigger = New-JobTrigger -Daily -At $time

    Write-Verbose 'Creating Options'
    $option = New-ScheduledJobOption -RunElevated

    Write-Verbose 'Registering Job'
    Register-ScheduledJob -Name $name -Trigger $trigger  -ArgumentList $ConfigFile,$this_file  -ScriptBlock {
        $ConfigFile,$this_file = $args
        . $this_file
        Backup-Folder   -ConfigFile $ConfigFile
        Backup-Database -ConfigFile $ConfigFile
      }
  } Catch [Exception] {
  } Finally {
    Remove-Module PSScheduledJob
  }

}
