param(
  [Parameter(Mandatory=$true)] [string]$PdfPath,
  [Parameter(Mandatory=$true)] [string]$OutCsv
)

# Use curl.exe (the native curl) to avoid PowerShell's alias
$curl = "curl.exe"
if (-not (Get-Command $curl -ErrorAction SilentlyContinue)) {
  Write-Error "curl.exe not found in PATH"
  exit 1
}

& $curl -v -F "file=@$PdfPath" http://localhost:8080/convert -o $OutCsv
Write-Output "Saved CSV to $OutCsv"
