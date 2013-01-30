Clear-Host
Write-Host Dot Loading Site-Tools.ps1.  -fore Gray
. D:\AdminScripts\site-tools.ps1
#. C:\projects\projects-current\site-tools\site-tools.ps1


Write-Host Generating Scheduled Tasks -fore Gray


Create-Schedule -ConfigFile "D:\AdminScripts\site-tools-config\raaf-stage.xml"    #-Verbose
Create-Schedule -ConfigFile "D:\AdminScripts\site-tools-config\youthhq-stage.xml" #-Verbose
Create-Schedule -ConfigFile "D:\AdminScripts\site-tools-config\omara-stage.xml"   #-Verbose
#Create-Schedule -ConfigFile "C:\projects\projects-current\site-tools\configs\default.xml" #-Verbose

Write-Host Generating Scheduled Tasks. -fore Gray



Get-ScheduledJob | Out-GridView -OutputMode Multiple -Title "Select Jobs To Run Now!" | % { 
  Write-Host Running $_.Name -Fore Green
  $_.Run()
}

Write-Host Actions Complete. -fore Green
#Backup-Folder    -ConfigFile "default.xml" -Verbose
#Backup-DataBase  -ConfigFile "default.xml" -Verbose
