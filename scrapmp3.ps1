# Directory containing your MP3 files
$karaokeDir = "C:\karaoke"
$imagesFolderName = "images"


# Get all .mp3 files in the specified directory
$mp3files = Get-ChildItem -Path $karaokeDir -Filter *.mp3


# Extract VQD token from DuckDuckGo search result HTML, handling various patterns
function Get-DuckDuckGoVQD($content) {
    $possibleVqd = @()
    if ($content -match "vqd='([a-zA-Z0-9\-]+)'") { $possibleVqd += $matches[1] }
    if ($content -match "vqd: '([a-zA-Z0-9\-]+)'") { $possibleVqd += $matches[1] }
    if ($content -match "vqd=([0-9\-]+)[^0-9\-]") { $possibleVqd += $matches[1] }
    if ($content -match "DDG\.deep\.initialize\('.*?vqd=([0-9\-]+)") { $possibleVqd += $matches[1] }
    if ($possibleVqd.Count -gt 0) { 
        return $possibleVqd[0]
    }
    return $null
}


# Find the first DuckDuckGo Image result for a given artist and title
function Get-FirstDuckDuckGoImage($artist, $title) {
    $searchTerm = "$artist $title cover"
    $encoded = [Uri]::EscapeDataString($searchTerm)
    $duckUrl = "https://duckduckgo.com/?q=$encoded&iar=images&iax=images&ia=images"
    $page = Invoke-WebRequest -Uri $duckUrl -UseBasicParsing
    $vqd = Get-DuckDuckGoVQD $page.Content


    if (-not $vqd) {
        Write-Host "⚠️  VQD not found for $artist - $title"
        $debugFile = Join-Path $pwd.Path "debug-duck.html"
        $page.Content | Out-File -FilePath $debugFile -Encoding utf8
        Write-Host "HTML saved in $debugFile for manual inspection."
        return $null
    }


    # Try both /i.js (classic) and /d.js (newer) endpoints depending on DDG version
    $jsonCandidates = @(
        "https://duckduckgo.com/i.js?l=fr-fr&o=json&q=$encoded&vqd=$vqd", 
        "https://duckduckgo.com/d.js?q=$encoded&vqd=$vqd&l=fr-fr&o=json"
    )


    foreach ($jsonUrl in $jsonCandidates) {
        Write-Host "DEBUG: JSON URL DuckDuckGo = $jsonUrl"
        try {
            $response = Invoke-WebRequest -Uri $jsonUrl -Headers @{ 'Referer' = $duckUrl } -UseBasicParsing -ErrorAction Stop
            $json = $response.Content | ConvertFrom-Json
            if ($json.results -and $json.results.Count -gt 0) {
                return $json.results[0].image
            }
        } catch {
            Write-Host "DEBUG: Failure or no image at $jsonUrl"
        }
    }
    return $null
}


# Main loop through all MP3 files
foreach ($file in $mp3files) {
    if ($file.BaseName -match "^(?<artist>.+?)\s*-\s*(?<title>.+?)(?:\s*-\s*.+)?$") {
        $artist = $matches['artist'].Trim()
        $title  = $matches['title'].Trim()
        Write-Host "**** Processing: $artist - $title ****"


        $imagesPath = Join-Path $file.Directory $imagesFolderName
        if (!(Test-Path $imagesPath)){ New-Item -Path $imagesPath -ItemType Directory | Out-Null }
        $imgPath = Join-Path $imagesPath ("$($file.BaseName)-image.jpg")


        # Skip download if the image already exists
        if (Test-Path $imgPath) {
            Write-Host "Image already exists for $($file.Name), skipping."
        } else {
            $imgUrl = Get-FirstDuckDuckGoImage $artist $title
            if ($imgUrl) {
                try {
                    Invoke-WebRequest -Uri $imgUrl -OutFile $imgPath
                    Write-Host "Image downloaded for $($file.Name)"
                } catch {
                    Write-Host "Error downloading image for $($file.Name)"
                }
            } else {
                Write-Host "❌ No image found for $($file.Name)"
            }
        }
        # Wait 5 seconds before next request
        Start-Sleep -Seconds 5
    } else {
        Write-Host "Unrecognized file format: $($file.Name)"
    }
}
