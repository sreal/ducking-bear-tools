Function Check-Handle-Regex {
Param (
[string] $regex
)
    $handle = D:\apps\sysinternals.bin\handle.exe
    foreach ($line in $handle) {
       if ($line -match '\S+\spid:') {
           $exe = $line
       }
       elseif ($line -match $regex)  {
           "$exe - $line"
       }
    }
}
