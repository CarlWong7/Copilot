$i=0
Import-Csv .\NIV-Bible-PDF.csv | Select-Object -First 80 | ForEach-Object {
  $i++; Write-Output ("{0:000}	BOOK={1}	CH={2}	V={3}" -f $i, $_.BOOK, $_.CHAPTER, $_.VERSE)
}
Write-Output "\nRows with empty BOOK:"
Import-Csv .\NIV-Bible-PDF.csv | Where-Object { -not $_.BOOK -or $_.BOOK -eq '' } | Select-Object -First 20 | ForEach-Object { Write-Output ("BOOK_EMPTY: CH={0} V={1} DESC={2}" -f $_.CHAPTER, $_.VERSE, ($_.DESCRIPTION -replace '\n',' ')) }
