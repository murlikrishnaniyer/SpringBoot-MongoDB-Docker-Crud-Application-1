<#
PowerShell script to test the Spring Boot MongoDB API via a local port-forward.
Usage: .\scripts\test-api.ps1

What it does:
 - Starts `kubectl port-forward svc/spring-mongodb-crud-application 8080:8080 -n default` in background
 - Posts a JSON file to /addBook
 - GETs /findAllBooks and /findAllBooks/{id}
 - DELETEs /delete/{id}
 - Cleans up (removes temp file and stops port-forward)

This script uses curl.exe to avoid PowerShell's Invoke-WebRequest JSON quoting issues.
#>

Set-StrictMode -Version Latest

# Configuration
$serviceUrl = 'http://127.0.0.1:8080'
$namespace = 'default'
$svcName = 'spring-mongodb-crud-application'
$portLocal = 8080

# Temp file for POST body
$tempFile = Join-Path $env:TEMP "apibody-$(Get-Random).json"

# Start port-forward in background
Write-Output "Starting port-forward to $svcName:$portLocal in namespace $namespace..."
$pfProc = Start-Process -FilePath kubectl -ArgumentList @('port-forward', "svc/$svcName", "$portLocal`:8080", '-n', $namespace) -NoNewWindow -PassThru -WindowStyle Hidden

try {
    # Wait for the port-forward to open (simple loop)
    $maxWait = 30
    $ok = $false
    for ($i=0; $i -lt $maxWait; $i++) {
        try {
            $resp = Invoke-WebRequest -Uri "$serviceUrl/findAllBooks" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
            $ok = $true; break
        } catch {
            Start-Sleep -Seconds 1
        }
    }
    if (-not $ok) { throw "Port-forward did not become ready after $maxWait seconds." }
    Write-Output "Port-forward ready. Running API tests..."

    # 1) POST /addBook (file-based to avoid quoting issues)
    $body = @{ id = 42; bookName = 'CI Test Book'; authorName = 'Copilot' } | ConvertTo-Json -Depth 3
    Set-Content -Path $tempFile -Value $body -Encoding utf8
    Write-Output "POST /addBook -> sending file $tempFile"
    $post = & curl.exe -s -X POST "$($serviceUrl)/addBook" -H 'Content-Type: application/json' --data-binary "@$tempFile"
    Write-Output "Response: $post`n"

    # 2) GET /findAllBooks
    Write-Output "GET /findAllBooks"
    $all = & curl.exe -s "$($serviceUrl)/findAllBooks"
    Write-Output $all; Write-Output "`n"

    # 3) GET /findAllBooks/{id}
    Write-Output "GET /findAllBooks/42"
    $one = & curl.exe -s "$($serviceUrl)/findAllBooks/42"
    Write-Output $one; Write-Output "`n"

    # 4) DELETE /delete/{id}
    Write-Output "DELETE /delete/42"
    $del = & curl.exe -s -X DELETE "$($serviceUrl)/delete/42"
    Write-Output $del; Write-Output "`n"

    # 5) GET /findAllBooks (after delete)
    Write-Output "GET /findAllBooks (after delete)"
    $all2 = & curl.exe -s "$($serviceUrl)/findAllBooks"
    Write-Output $all2; Write-Output "`n"

} finally {
    # Cleanup
    if (Test-Path $tempFile) { Remove-Item -Force $tempFile }
    if ($pfProc -and -not $pfProc.HasExited) {
        Write-Output "Stopping port-forward (PID $($pfProc.Id))..."
        try { Stop-Process -Id $pfProc.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
}

Write-Output "Done."
