<#
.SYNOPSIS
Script method wrapped the required methods for the automated tools.

.DESCRIPTION
./release-tools.ps1 is the wrapper script vcalled by the automated release processes.
On the build server, it wraps the calls that move a packaged release to the management gateway box and then into the release environment.
On the release server, it wraps the call to fiund and unpack the release scripts and call the installers within them.

.PARAMETER Action
Either

    Distribute  |  Release

Distrubte Called by the build server, local calls can also be made
Release: Called by the Schedule Task used to perform the nightly release.

.EXAMPLE
Move a release package into the release enviromnent, via the management box. This can be seen the in the Jenkins Job.
./release-tools.ps1 Distrubte

.EXAMPLE
Find and unpack the release script. Once unpacked run the installed defined in the configuration

.NOTES
Addition files requries are; ./remote-install-tools.ps1, and ./remote-install-tools.ps1.xml
This will not run as expected if either of the files are missing.
Is is expected that these 3 files are installed to:
  //BUILD-SERVER/D$/AdminScripts/*
  //RELEASE-SERVER/c$/adfc/AdminScripts/*
#>
Param (
  [Parameter(Mandatory=$true)][String] $Action,
  $Environments
)

################
# Send the build install package to each environment's release server
# Run from the BUILD SERVER

#distribute is expected to be run on the build server
Function Distribute-Package{
Param (
  [string] $Environment
)
    Write-Host "Distribute-Package"
    Import-Module D:\AdminScripts\remote-install-tools.psm1 #use a module instead of a dot load.

    Write-Host "Copying files to Management Box"
    $files = Copy-Build-To-Gateway -Environment $_ -Verbose
    Write-Host "Copying files to Release Box"
    Move-To-Release -Environment $_ -Files $files -Verbose

}

#release-pacakge should be run insdie the environment
Function Release-Package {
    Write-Host "Release-Package"
    Import-Module C:\adfc\AdminScripts\remote-install-tools.psm1

    Write-Host "Getting latest install scripts"
    $scripts = Expand-Latest-Release-Scripts -Verbose
    Write-Host "Running latest installers"
    Run-Installer -Verbose

}


#__main__
switch ($Action) {
  "Distribute"
  {
    $Environments | % {
      Distribute-Package $_ -Verbose
    }
  }
  "Release"
  {
    Write-Host "Releasing Project :)"
    Release-Package
  }
  default
  {
    Write-Error "No -Action Found. Valid"
  }

}
