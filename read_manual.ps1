$c = Get-Content 'GUN-TACTYX-manual.htm' -Raw
Write-Output $c.Substring(0, 20000)
