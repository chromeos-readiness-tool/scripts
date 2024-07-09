# Function to get the installed .NET Framework version
function Get-DotNetFrameworkVersion {
    $regPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
    $regValueName = "Release"
    
    if (Test-Path $regPath) {
        $releaseKey = (Get-ItemProperty -Path $regPath).$regValueName
        return $releaseKey
    } else {
        return $null
    }
}

# Function to check if the .NET Framework version is at least 4.8
function Is-DotNetFrameworkVersionAtLeast48 {
    param (
        [int]$releaseKey
    )

    # .NET Framework version 4.8 release key is 528040 or greater
    return $releaseKey -ge 528040
}

# Main script execution
$dotNetVersion = Get-DotNetFrameworkVersion

if ($dotNetVersion -eq $null -or -not (Is-DotNetFrameworkVersionAtLeast48 -releaseKey $dotNetVersion)) {
    Write-Host "You are not eligible to install ChromeOS Readiness Tool. Download .NET Framework 4.8 or later from this link: https://dotnet.microsoft.com/en-us/download/dotnet-framework"
} else {
    Write-Host ".NET Framework version is 4.8 or later. You are eligible to install this ChromeOS Readiness Tool."
}
