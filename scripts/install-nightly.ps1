#
# Download and install the nightly build of Swift.
#

$webroot="https://download.swift.org/development/windows10"

# Get the name of the latest build
$latest=Invoke-RestMethod $webroot/latest-build.json

echo "Latest build is $($latest.dir)"

# Fetch the installer
$installer=Join-Path $Env:Temp install-swift.exe
echo "Downloading to $installer"

$webClient = New-Object net.webclient
$webClient.Downloadfile("$webroot/$($latest.dir)/$($latest.download)", "$installer")

# Run the installer
echo "Installing Swift"
Start-Process "$installer" -NoNewWindow -Wait -ArgumentList "/q","/jm"

# Delete the installer
Remove-Item "$installer"

# Update Path
$env:Path=(
  [System.Environment]::GetEnvironmentVariable("Path","Machine"),
  [System.Environment]::GetEnvironmentVariable("Path","User")
) -match '.' -join ';'

# Update SDKROOT
$env:SDKROOT=[System.Environment]::GetEnvironmentVariable("SDKROOT","User")

# Display the newly installed Swift version
swiftc --version
