#<#
#.SYNOPSIS
#CadetNet Remote Installer Tools
#
#.DESCRIPTION
#Script to handled the processed used in the remote install of CadetNet
#
#.EXAMPLE
#./remote-install.ps1
#Test the powersehll remoting of the current machine
#This should opnly need to be run from CDTSQL2
#
##>


<#
.SYNOPSIS
Load configuration values.
.DESCRIPTION
Get-RTConfig loads the xml configuration values from ./remove-install-tools.ps1.xml and returns the configuration node.
The configuration files is expected to be neamed <this-file-name-with-extension>.xml
This is expected to only be called in this file.
Basic xml format is:

  <Configuration>
    <!-- setup where the files are coming from -->
    <BuildServer releaseDirectory='[[directory-where-the-build-server-builds-to]]' />
    <!-- setup where the environments -->
    <Environments>
      <Environment Name='[[environment-identifier]]'
                   GatewayBox='[[management-box]]'
                   GatewayShare='[[temp-directory-onmanagement-box]]'
                   ReleaseBox='[[release-box]]'
                   ReleaseShare='[[storage-on-release-server_can-use-[[DATETIME]]'
                   RemoteUser="[[domain]]\[[username]]"
                   RemotePassword="[[password_as_b64]]" />
    </Environments>
    <!-- list the files that are created by the build server in releaseDirectory -->
    <ReleaseFiles>
      <!--  Note This muist be a flat directory of files. No directories or folders. -->
      <File format='[[ENVIRONMENT]]_[[DATE]].zip' />
      <File format='Release-Scripts-[[VERSION]].zip' InstallServer='[[installation-server]]' InstallLocation='[[path-to-installation-dir]]' >
        <InstallScript InstallScriptFormat="Installer-[[VERSION]]-[[ENVIRONMENT]].bat" Type='batch' Order='0'/>
        <InstallScript InstallScriptFormat="Installer2.ps1" Type='powershell' Order='1'/>
      </File>
    </ReleaseFiles>
  </Configuration>
.EXAMPLE
Load the configuration file
  $config = Get-RTConfig
  $build_server_release_directory = $config.BuildServer.releaseDirectory
#>
Function Get-RTConfig {
[CmdletBinding()]
Param ()
  $config_path =  $MyInvocation.ScriptName + ".xml"
  Write-Verbose "Getting Configuration $config_path"
  if (-not (Test-Path $config_path) ) {
    Write-Error "Configuration File Not Found"
    Exit  Write-Verbose "Getting Configuration"
  }

  [xml] $cfg = Get-Content $config_path
  $configuration =  $cfg.Configuration
  if ($configuration -eq $null) {
    Write-Error Invalid Configuration
  }
  $configuration
}


<#
.SYNOPSIS
Get the environment section from configuration
.DESCRIPTION
Get just the environment object required from a complete configuration xml object.
This is expected to only be called in this file.
.Parameter Config
The configuration object. This can be aquired with Get-RTConfig
.Parameter Name
The name or regular expression to be used when trying to match the environment name
.Parameter IsRegex
Switch to expect a regex as the name match and to use the RegexId valus in the configuration (See 'Get-Help Get-RTConfig' for configuration xml format)
.EXAMPLE
Get the environment using regex
  Get-RTEnvironment-Config $MyConfigObject '^[tT]est[eE]nv' -IsRegex
#>
Function Get-RTEnvironment-Config {
[CmdletBinding()]
Param ( $Config,
        [string] $Name,
        [switch] $IsRegex
)
  if ($IsRegex) {
    Write-Verbose "Matching Environment with -match $Name"
    $env_config = $Config.Environments.Environment | ? { $Name -match $_.RegexId  } | Select-Object -First 1
  } else {
    Write-Verbose "Matching Environment with -eq $Name"
    $env_config = $Config.Environments.Environment | ? { $Name -eq $_.Name } | Select-Object -First 1
  }

  if ($env_config -eq $null) {
    Write-Error "No configuration for environment found"
    Exit 0
  }
  $name = $env_config.Name
  Write-Verbose "Environment Config $name"
  $env_config
}

<#
.SYNOPSIS
Get script files.
.DESCRIPTION
Get the set ofscript files relatedc to running the current script. This includes the configuration file.
.EXAMPLE
Get the script files
  Get-Script-Files
#>
Function Get-Script-Files {
[CmdletBinding()]
Param ()
  Write-Verbose "Getting script files"
  $files = Get-Item $MyInvocation.PSCommandPath, ($MyInvocation.PSCommandPath + ".xml") | % {
    $_
  }
  return $files
}

<#
.SYNOPSIS
Copy the a package to the gateway box.
.DESCRIPTION
Finds and copies the latest package and moves it to the gateway box. Details of the actual location are pulled from the configuration file.
This is expected to be called from the build server.
.PARAMETER Environment
Name of the file on the management box. Expected to be the output of Copy-Build-To-Gateway
.EXAMPLE
Copy the package to the management box. Then move the package to the release server.
  $files = Copy-Build-To-Gateway 'TEST2010'
  Copy-Build-To-Gateway 'TEST2010' $files
#>
Function Copy-Build-To-Gateway {
[CmdletBinding()]
Param (
  [Parameter(Mandatory=$true)][string] $Environment
)
  Write-Host "Copy-Build-To-Gateway $Environment"
  $config = Get-RTConfig

  $latest = Get-ChildItem $config.BuildServer.releaseDirectory | Sort-Object Name -Descending | Select-Object -First 1
  Write-Verbose "Latest build directory $latest"
  if ($latest -eq $null) {
    Write-Error "There are no releases in the release directory"
    Exit 0
  }

  $latest = $latest.FullName
  $env_config = Get-RTEnvironment-Config $config $Environment


  $gateway       = $env_config.GatewayBox
  $gateway_share = $env_config.GatewayShare
  Write-Verbose "gateway:       $gateway"
  Write-Verbose "gateway_share:       $gateway_share"

  #remove the placeholders from the confgi file
  $release_files = $config.ReleaseFiles.File
  $files_match = $release_files | % {
    $name = $_.Format
    $name = $name -Replace '\[\[ENVIRONMENT\]\]', $environment
    $name = $name -Replace '\[\[VERSION\]\]', '*'
    $name = $name -Replace '\[\[DATE\]\]', '*'
    return $name
  }

  #NOTE. Be aware, this assumes ALL FILES are in the TOP leve. ie no directories or nesting
  $files = @()
  $files_match | % {
    $m = $_
    Write-Verbose "Finding files matching $m"
    Get-ChildItem $latest | ? { $_.Name -like $m } | % {
      Write-Verbose "Match Found: $_"
      #if ($_ -notin $files) {
      if (-not ($files -Contains $_)) {
        $files += $_
      }
    }
  }
  Write-Verbose "Adding configuration files to package"
  Get-Script-Files | % {
    $files += $_
  }

  $gateway_sharepath = Join-Path "\\$gateway" $gateway_share
  Write-Verbose "gateway_sharepath: $gateway_sharepath "
  if (-not (Test-Path $gateway_sharepath) ) {
    Write-Error "Gateway Share Path not found [$gateway_sharepath]"
  }

  Write-Verbose "Gateway Share Path $gateway_sharepath"
  $copied = @()
  $files | % {
    if (Test-Path $_.FullName) {
      Copy-Item $_.FullName $gateway_sharepath
      $copied += Join-Path  $gateway_sharepath $_.Name -Resolve #See NOTE above
    }
  }
  Write-Verbose "Files Copied from BUILD to environment Gateway"
  $copied | % { Write-Verbose "  $_" }
  $copied
}




<#
.SYNOPSIS
Move the package to the release server
.DESCRIPTION
Finds and move the release package to the release server.
This is expected to be called from teh build server.
.PARAMETER Environment
Name of the Enviroment to use. Must match Environment.name in from configuration file.
.PARAMETER File
List of file on the management box. This is the output of Copy-Builds-To-Gateway
.EXAMPLE
Copy the package to the TEST2010 Gateway box.
  $files = Copy-Build-To-Gateway 'TEST2010'
  Move-To-Release 'TEST2010' $files
#>
Function Move-To-Release {
[CmdletBinding()]
Param (
  [Parameter(Mandatory=$true)][string] $Environment,
  [Parameter(Mandatory=$true)] $Files
)
  Write-Host "Move-To-Release $Environment $Files"
  $config = Get-RTConfig
  $env_config = Get-RTEnvironment-Config $config $Environment

  $gateway       = $env_config.GatewayBox
  $release       = $env_config.ReleaseBox
  $release_share = $env_config.ReleaseShare
  $release_share = $release_share -Replace '\[\[DATETIME\]\]', (Get-Date -f yyyyMMddHHmm)
  $remote_user   = $env_config.RemoteUser
  $remote_pass   = $env_config.RemotePassword
  $remote_pass   = [System.Text.Encoding]::UNICODE.GetString([System.Convert]::FromBase64String($remote_pass))

  Write-Verbose "gateway:       $gateway"
  Write-Verbose "release:       $release"
  Write-Verbose "release_share: $release_share"
  Write-Verbose "remote_user:   $remote_user"

  $release_sharepath = Join-Path "\\$release" $release_share

  $password = ConvertTo-SecureString $remote_pass -AsPlainText -Force
  $credentials = New-Object System.Management.Automation.PsCredential($remote_user,$password)
  $moved = Invoke-Command -ComputerName $gateway -ArgumentList $release_sharepath,$Files -Credential $credentials -Authentication CredSSP -ScriptBlock {
    Param (
      [string] $release_sharepath,
      $files
    )
    if (-not (Test-Path $release_sharepath) ) {
      New-Item $release_sharepath -Type Directory  | Out-Null
    }
    Write-Verbose "Moving Files to $release_sharepath"
    $moved_files = @()
    $Files | % {
      $f = Get-Item $_ # -Resolve
      #Move-Item $f.FullName $release_sharepath -Force
      Copy-Item $f.FullName $release_sharepath -Force

      $moved_files += Join-Path $release_sharepath $f.Name
    }
    $moved_files
  }
  Write-Verbose "Files moved to Release Server"
  $moved | % { Write-Verbose "  $_" }
  $moved
}


<#
.SYNOPSIS
Find and unpack the latest release scripts
.DESCRIPTION
Finds the latest release script for the environment form a config. Release scripts are then unpacked to the required location defined in the configuration file.
This is expected to be called on the release server.
.EXAMPLE
Find and unpack the latest release scripts for the current environment
  Copy-Build-To-Gateway 'TEST2010'
#>
Function Expand-Latest-Release-Scripts {
[CmdletBinding()]
Param( )
  Write-Host "Expand-Latest-Release-Scripts"
  $config = Get-RTConfig
  $env_config = Get-RTEnvironment-Config $config $env:COMPUTERNAME -IsRegex

  $environment   = $env_config.Name
  $release       = $env_config.ReleaseBox
  $release_share = $env_config.ReleaseShare
  $release_share = $release_share -Replace '\[\[DATETIME\]\]', ''
  $remote_user   = $env_config.RemoteUser
  $remote_pass   = $env_config.RemotePassword
  $remote_pass   = [System.Text.Encoding]::UNICODE.GetString([System.Convert]::FromBase64String($remote_pass))

  Write-Verbose "release:       $release"
  Write-Verbose "release_share: $release_share"
  Write-Verbose "remote_user:   $remote_user"


  Write-Verbose "Getting Latest release files"
  $release_sharepath = Join-Path "\\$release" $release_share
  $latest_release = Get-ChildItem $release_sharepath | ? { $_.PSIsContainer }  | Sort-Object Name -Descending | Select-Object -First 1
  Write-Verbose "Latest Release directory is $latest_release"

  $release_sharepath = Join-Path "$release" $release_share
  Write-Verbose "Release Source path is $release_sharepath"

  $latest_sharepath = Join-Path "\\$release_sharepath" $latest_release
  Write-Verbose "Latest Sharepath  is $latest_sharepath"

  $install_scripts = @()
  $config.ReleaseFiles.File | ? { $_.InstallScript -ne $null } |  % {
    $file = $_
    Write-Verbose "Getting installer script details"


    $install_servers    = $file.InstallServer.Split(",")
    $install_location   = $file.InstallLocation


    $install_servers | % {
      $install_server = $_
      $install_script_share = Join-Path "\\$install_server" $install_location

      Write-Verbose "Installer script location  $install_script_share"

      $install_container_format    = $file.Format
      $install_container_format    = $install_container_format -Replace '\[\[DATETIME\]\]', '*'
      $install_container_format    = $install_container_format -Replace '\[\[VERSION\]\]', '*'
      $install_container_format    = $install_container_format -Replace '\[\[ENVIRONMENT\]\]', $environment
      Write-Verbose "Installer container format $install_container_format"

      $latest_install_container = Get-ChildItem $latest_sharepath | ? { $_.Name -like "$install_container_format" }
      if ($latest_install_container -eq $null) {
        Write-Verbose "$latest_sharepath"
        Write-Verbose "$install_container_format"
        Write-Error "Latest install package not found."
        return
      }
      $latest_install_container = Join-Path $latest_sharepath $latest_install_container
      Write-Verbose "Install container  $latest_install_container"

      $file.InstallScript | % {

        $install_script_format    = $_.InstallScriptFormat
        $install_script_format    = $install_script_format -Replace '\[\[DATETIME\]\]', '*'
        $install_script_format    = $install_script_format -Replace '\[\[VERSION\]\]', '*'
        $install_script_format    = $install_script_format -Replace '\[\[ENVIRONMENT\]\]', $environment
        Write-Verbose "Install script format    $install_script_format"

        try {
          Import-Module Pscx -Verbose:$false
        } catch {
          Write-Error "Unable to Import Pscx"
          Exit 0
        }
        $install_script_location = Join-Path $install_script_share $latest_release

        #if ( Test-Path $install_script_location ){
        #    Write-Verbose "Removing existing script from $install_script_location"
        #    Remove-Item $install_script_location -Recurse -Force
        #}

        if ( -not (Test-Path $install_script_location) ){
            Write-Verbose "Creating $install_script_location"
            New-Item $install_script_location -Type Directory | Out-Null
        }
        Expand-Archive $latest_install_container $install_script_location -Force | Out-Null
        $install_scripts += Get-ChildItem $install_script_location | ? { ($_.Name -like $install_script_format) -and (-not $_.PSIsContainer) }
      }
    }
  }
  Write-Verbose "Install Scripts"
  $install_scripts | % { Write-Verbose "  $_" }
  $install_scripts
}


<#
.SYNOPSIS
Dun the Installers defined in a configuration
.DESCRIPTION
Finds and runs the Installer scripts defined in the configuratioun for the environment.
The current environment is determined by interrogating env:machinename
This is expected to be called on the release server.
.EXAMPLE
Run the installer for the current environment
  Run-Installer
#>
Function Run-Installer {
[CmdLetBinding()]
Param()
  Write-Host "Run-Installer"
  $config = Get-RTConfig

  $env_config = Get-RTEnvironment-Config $config $env:COMPUTERNAME -IsRegex

  $environment   = $env_config.Name
  $remote_user   = $env_config.RemoteUser
  $remote_pass   = $env_config.RemotePassword
  $remote_pass   = [System.Text.Encoding]::UNICODE.GetString([System.Convert]::FromBase64String($remote_pass))
  Write-Verbose "environment:   $environment"
  Write-Verbose "remote_user:   $remote_user"

  Write-Verbose "Setting up remote user"

  $password = ConvertTo-SecureString $remote_pass -AsPlainText -Force
  $credentials = New-Object System.Management.Automation.PsCredential($remote_user,$password)


  $config.ReleaseFiles.File | ? { $_.InstallScript -ne $null } |  % {
    $file = $_
    $install_servers = $file.InstallServer.Split(",")

    $install_servers | % {
      $install_server = $_
      $install_location = $file.InstallLocation

      $install_script_share = Join-Path "\\$install_server" $install_location

      $latest = Get-ChildItem $install_script_share | ? { $_.PSIsContainer -and $_.name -match '\d{12}' } | Sort-Object Name -Descending | Select-Object -First 1
      $latest_scripts = Join-Path "$install_script_share" $latest

      Write-Verbose "Latest found script directory is $latest_scripts"

      $file.InstallScript | Sort-Object Order  | % {

        $install_script_format = $_.InstallScriptFormat
        $install_script_format    = $install_script_format -Replace '\[\[DATETIME\]\]', '*'
        $install_script_format    = $install_script_format -Replace '\[\[VERSION\]\]', '*'
        $install_script_format    = $install_script_format -Replace '\[\[ENVIRONMENT\]\]', $environment
        Write-Verbose "Trying to match $install_script_format"
        Write-Verbose "Trying to match in directory $latest_scripts"



        $latest_file = Get-ChildItem $latest_scripts | ? { $_.Name -like $install_script_format }
        $type = $_.Type
        Write-Verbose "Install Format $latest_file"

        $path = Join-Path $install_location $latest
        $path = $path -Replace '\$',':'

        Invoke-Command -ComputerName $install_server -ArgumentList $latest_file,$path,$type -Credential $credentials -Authentication CredSSP -ScriptBlock {
          Param (
            $latest_file,
            $path,
            [string] $type
          )


          Write-Verbose "Current path stored $inital_location"
          $inital_location = Resolve-Path .

          Write-Verbose "Setting path $path"
          Set-Location $path


          $filecommand = $latest_file.FullName
          switch ($type) {
            'powershell' {
              Write-Verbose "Running Powershell Script"
              powershell -ExecutionPolicy Bypass -file "$filecommand"
            }
            default {
              Write-Verbose "Running NOT Powershell Script"
              &"$filecommand"
            }
          }
          Write-Verbose "Returning to $inital_location"
          Set-Location $inital_location
        }
      }
    }
  }
}
