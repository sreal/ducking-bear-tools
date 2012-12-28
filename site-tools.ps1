##
# . ./site_tools.ps1
# sre, 2012-12-24
#
# ./Backup-Database -Config-File CONFIG.XML
# ./Backup-Folder   -Config-File CONFIG.XML
#
# Requirements: PowerShell v3 [PSScheduledJob]

Function Restore-Folder
{
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true)][String] $ConfigFile,
  [Parameter(Mandatory=$true)][String] $Folder,
  [Switch] $IgnoreBackup,
  [Switch] $IgnoreRemove
)

  Try {
    Write-Verbose 'Getting Configuration'
    $cfg = Get-Config $ConfigFile
    $environment = $cfg.Site.Setup.environment
    $root_dir    = $cfg.Site.root.location
    $psScripts     = $cfg.Site.Setup.Scripts.powershell


    Write-Verbose 'Validating Folder'
    if (-not ( Test-Path $Folder) ) {
      Write-Error "Folder not found. [$Folder]"
      Return
    }

    if (-not $IgnoreBackup) {
      Write-Verbose 'Backing up Current Site'
      Backup-Folder $ConfigFile -ErrorAction Continue
    }

    if (-not $IgnoreRemove) {
      Write-Verbose 'Removing Root Folder'
      Remove-Item -Recurse -Force $root_dir
    }

    Write-Verbose 'Copying Backup Folder to Root Folder'
    Copy-Item -Recurse $Folder $root_dir -Force

    while ($responce -ne 'y') {
      $responce = Read-Host '''
Have you made the file changes required?
For Example. Updates to the web.config. (y to continue)'
    }

    Write-Verbose 'Running Addition Setup Scripts'
    foreach ($script in $psScripts) {
      $file = $script.file -Replace '\[\[BASE\]\]', $root_dir
      $arguments = $script.arguments -Replace '\[\[BASE\]\]', $root_dir
      if (Test-Path $file) {
        &"$file $args"
        Write-Verbose "Script run [$file $args]"
      } else {
        Write-Verbose "Script not found [$file]"
      }
    }

    Write-Verbose "Folder Restore Completed"
    Write-Host "
  Folder restored.

Location:
  Root Directory:   $root_dir

Thanks for playing...
"
   } Catch [Exception] {
     Write-Error $_.Exception.Message
   }
}

Function Restore-Database {
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true)][String] $ConfigFile,
  [Parameter(Mandatory=$true)][String] $DatabaseBackup,
  [Switch] $IgnoreBackup
)
  Try {
        $SQL_restore_sync = "
USE MASTER

-- Create Database
IF NOT EXISTS (SELECT * FROM sys.databases WHERE NAME = '[[catalogue]]')
BEGIN
    CREATE DATABASE [[[catalogue]]]
        ON PRIMARY ( NAME='[[mdf_name]]', FILENAME=N'[[mdf_path]]' )
        LOG ON  ( NAME='[[ldf_name]]', FILENAME=N'[[ldf_path]]' )
END
GO

--Create Login
IF NOT EXISTS (SELECT * FROM sys.syslogins WHERE NAME = '[[username]]')
BEGIN
    CREATE LOGIN [[username]]
        WITH PASSWORD = '[[password]]',
        DEFAULT_DATABASE = [[[catalogue]]]
END
GO

-- Get the logical file names from the backup
CREATE TABLE #LOGICAL_NAME (
  LogicalName  nvarchar(128), PhysicalName nvarchar(260), Type char(1), FileGroupName nvarchar(128) null, Size   numeric(20, 0), MaxSize   numeric(20, 0), FileId   int null, CreateLSN    numeric(25,0) null, DropLSN     numeric(25,0) null, UniqueId  uniqueidentifier null, readonlyLSN     numeric(25,0) null, readwriteLSN     numeric(25,0) null, BackupSizeInBytes bigint null, SourceBlkSize  int null, FileGroupId  int null, LogGroupGuid  uniqueidentifier null, DifferentialBaseLsn numeric(25,0) null, DifferentialBaseGuid uniqueidentifier null, IsReadOnly  bit null, IsPresent  bit null, TDEThumbPrint varbinary(32) null
)
DECLARE @cmdstr varchar(255)
SELECT @cmdstr = 'restore filelistonly from disk=''[[backup]]'''
INSERT INTO #LOGICAL_NAME EXEC (@cmdstr)
DECLARE @mdf varchar(255)
DECLARE @ldf varchar(255)
SELECT @mdf = LogicalName FROM #LOGICAL_NAME where [Type] ='D'
SELECT @ldf = LogicalName FROM #LOGICAL_NAME where [Type] ='L'
DROP TABLE #LOGICAL_NAME

--Restore Backup
USE master
RESTORE DATABASE [[catalogue]]
    FROM DISK = N'[[backup]]'
    WITH MOVE @mdf TO N'[[mdf_path]]',
         MOVE @ldf TO N'[[ldf_path]]',
         REPLACE
GO

-- Create User or Sync
USE [[catalogue]]
IF NOT EXISTS (SELECT * FROM sys.syslogins WHERE NAME = '[[username]]')
  BEGIN
      CREATE LOGIN [[username]]
          WITH PASSWORD = '[[password]]',
          DEFAULT_DATABASE = [[[catalogue]]]
  END
ELSE
  BEGIN
    EXEC sp_change_users_login 'Update_One','[[username]]','[[username]]'
  END
GO
"

     if (-not $IgnoreBackup) {
       Write-Verbose 'Backing up Current Database'
       Backup-Database $ConfigFile -ErrorAction Continue
     }

     write-Verbose 'Getting Configuration'
     $cfg = Get-Config $ConfigFile

     $super_usr    = $cfg.Database.user.name
     $super_pwd    = $cfg.Database.user.password
     $server       = $cfg.Database.connection.server
     $catalogue    = $cfg.Database.connection.catalogue

     $mdf_name     = $cfg.Database.Files.mdf.name
     $mdf_location = $cfg.Database.Files.mdf.location
     $ldf_name     = $cfg.Database.Files.ldf.name
     $ldf_location = $cfg.Database.Files.ldf.location

     $username    = $cfg.Database.connection.username
     $password    = $cfg.Database.connection.password
     $mdf_path = Join-Path $mdf_location "$mdf_name.mdf"
     $ldf_path = Join-Path $ldf_location "$ldf_name.ldf"

     Write-Verbose "Injecting Config into Database Script"
     $SQL_restore_sync = $SQL_restore_sync.Replace( "[[backup]]",       $DatabaseBackup)
     $SQL_restore_sync = $SQL_restore_sync.Replace( "[[catalogue]]",    $catalogue     )
     $SQL_restore_sync = $SQL_restore_sync.Replace( "[[mdf_name]]",     $mdf_name      )
     $SQL_restore_sync = $SQL_restore_sync.Replace( "[[ldf_name]]",     $ldf_name      )
     $SQL_restore_sync = $SQL_restore_sync.Replace( "[[mdf_path]]", $mdf_path      )
     $SQL_restore_sync = $SQL_restore_sync.Replace( "[[ldf_path]]", $ldf_path      )
     $SQL_restore_sync = $SQL_restore_sync.Replace( "[[username]]",     $username      )
     $SQL_restore_sync = $SQL_restore_sync.Replace( "[[password]]",     $password      )

     Write-Verbose "Running SQL Backup Command"
     $sql_result = sqlcmd -S $server -U $super_usr -P $super_pwd -Q $SQL_restore_sync -V1
     $sql_success = $?
     if (-not $sql_success ) {
       Write-Error "Sql did not run successfully"
       Write-Verbose "$sql_result"
       Write-Debug $SQL_database_backup
     } else {
      Write-Host "
   Database restored.

   Location:
     From:   $DatabaseBackup
     To MDF: $mdf_path
     To LDF: $ldf_path

  Thanks for playing...
 "
    }


   } Catch [Exception] {
     Write-Error $_.Exception.Message
   }
}


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

    $backup_dir= Setup-Destination-Directory $backup_dir -Create -Date
    $backup_dir = Join-Path $backup_dir ("site-{0}" -f (Get-Date -Format yyyyMMddHHmm))
    $backup_dir= Setup-Destination-Directory $backup_dir -Create

    Write-Verbose "Copy File Includes"
    $files | % {
      $path = Join-Path $root_dir $_.path
      if ( -not (Test-Path $path) ) {
          Write-Error "Path Not Found [$path]"
          Return
      }

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



Function Backup-Database {
[CmdletBinding()]
Param(
  [String] $ConfigFile
)
  Try {
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
      Write-Verbose "$sql_result"
      Write-Error "Sql did not run successfully"
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
  } Catch [Exception] {
    Write-Error $_.Exception.Message
  }
}


Function Setup-Destination-Directory {
[CmdletBinding()]
Param(
  [string] $Directory,
  [switch] $Create,
  [switch] $Date
)
  Write-Verbose "Setting up backup location"
  if ($Date) {
    $Directory= "{0}\{1}" -F $Directory, (Get-Date -F yyyyMMdd)
  }
  if ($Create) {
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


Clear-host
#Restore-Database -ConfigFile configs/default.xml
Restore-Database -ConfigFile configs/default.xml -DatabaseBackup "D:\Backup\boo.bak" -Verbose
Restore-Folder   -ConfigFile configs/default.xml -Folder "C:\projects\tmp\umbraco\tmp\20121227\site-201212271627" -verbose
