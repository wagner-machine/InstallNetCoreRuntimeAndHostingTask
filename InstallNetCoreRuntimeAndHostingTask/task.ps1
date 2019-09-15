  
[CmdletBinding()]
param() 
Trace-VstsEnteringInvocation $MyInvocation
try 
{
    $ErrorActionPreference = "Stop"

    Import-VstsLocStrings "$PSScriptRoot\Task.json" 

    $dotNetVersion = Get-VstsInput -Name version -Require
    $norestart = Get-VstsInput -Name norestart -Require
    
    $fileName = "dotnet-hosting-win.exe"
    $releasesJSONURL = "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/" + $dotNetVersion + "/releases.json"
    $webClient = new-Object System.Net.WebClient

    # Load releases.json
    Write-Host Load release data from: $releasesJSONURL
    $releases = $webClient.DownloadString($releasesJSONURL) | ConvertFrom-Json

    Write-Host Latest Release Version: $releases.'latest-release'
    Write-Host Latest Release Date: $releases.'latest-release-date'


    # Select the latest release
    $latestRelease = $releases.releases | Where-Object { ($_.'release-version' -eq $releases.'latest-release') -and ($_.'release-date' -eq $releases.'latest-release-date') }
        
    if ($latestRelease -eq $null)
    {
        Write-Host "##vso[task.logissue type=error;]No latest release found"
        [Environment]::Exit(1)
    }


    # Select the installer to download
    $file = $latestRelease.'aspnetcore-runtime'.files | Where-Object { $_.name -eq $fileName }
        
    if ($file -eq $null)
    {
        Write-Host "##vso[task.logissue type=error;]File $fileName not found in latest release"
        [Environment]::Exit(1)
    }

    $installerFolder = Join-Path "$(System.DefaultWorkingDirectory)" $releases.'latest-release'
    $installerFilePath = Join-Path $installerFolder $fileName
    $tmp = New-Item -Path $installerFolder -ItemType Directory

    # Download installer
    Write-Host Downloading $file.name from: $file.url
    $webClient.DownloadFile($file.url, $installerFilePath)
    Write-Host Downloaded $file.name to: $installerFilePath


    $logFolder = Join-Path $installerFolder "logs"
    $logFilePath = Join-Path $logFolder "$fileName.log"
    $tmp = New-Item -Path $logFolder -ItemType Directory

    # Execute installer
    $installationArguments = "/passive /log $logFilePath"
    if ($norestart)
    {
        $installationArguments += " /norestart"
    }
    Write-Host Execute $installerFilePath with the following arguments: $installationArguments
    Write-Host Executing...
    $process = Start-Process -FilePath $installerFilePath -ArgumentList $installationArguments -Wait -PassThru
    Write-Host Installer completed with exitcode: $process.ExitCode


    ## Upload installation logs
    $logFiles = Get-ChildItem $logFolder -Filter *.log
    foreach ($logFile in $logFiles) {
        $logFilePath = $logFile.FullName
        Write-Host Upload installation log: $logFilePath
        Write-Host "##vso[task.uploadfile]$logFilePath"
    }


    # Exit with error if installation failed
    if ($process.ExitCode -ne 0) {
        $exitCode = $process.ExitCode
        Write-Host "##vso[task.logissue type=error;]Installation failed with code: $exitCode. See attached logs for more details."
        [Environment]::Exit(1)
    }
}
finally
{
	Trace-VstsLeavingInvocation $MyInvocation
}