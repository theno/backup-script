:: config starts here
set host=username@hostname
:: config ends here

:: create wimage

set thisdir=%~dp0
for /f %%i in ('powershell -command "$([int]([Environment]::TickCount/(1000 * 60)))"') do set minutes_up=%%i
echo %minutes_up% > %thisdir%MINUTES_UP.txt
echo %date:~-4%-%date:~-7,2%-%date:~-10,2% %time:~-11,2%:%time:~-8,2% > %thisdir%START.txt
DEL /F /Q /A %thisdir%sources\install.wim
echo %date:~-4%-%date:~-7,2%-%date:~-10,2% > %thisdir%FLAG_NEW_WIMAGE_IN_PROGRESS.txt
echo | %thisdir%ctwimage2b-64.bat
move  %thisdir%FLAG_NEW_WIMAGE_IN_PROGRESS.txt  %thisdir%FLAG_NEW_WIMAGE_EXISTS.txt
echo %date:~-4%-%date:~-7,2%-%date:~-10,2% %time:~-11,2%:%time:~-8,2% > %thisdir%END.txt

:: push to backup server

set HOME=%USERPROFILE%
for /f %%i in ('c:\cygwin64\bin\cygpath.exe -u %thisdir%') do set thisdir_unix=%%i
c:\cygwin64\bin\ssh.exe %host% mkdir -p wimage-rampe
c:\cygwin64\bin\scp.exe %thisdir_unix%FLAG_NEW_WIMAGE_EXISTS.txt  %host%:wimage-rampe/FLAG_NEW_WIMAGE_IN_PROGRESS
c:\cygwin64\bin\scp.exe %thisdir_unix%START.txt  %host%:wimage-rampe/START
c:\cygwin64\bin\scp.exe %thisdir_unix%END.txt  %host%:wimage-rampe/END
c:\cygwin64\bin\scp.exe %thisdir_unix%MINUTES_UP.txt  %host%:wimage-rampe/MINUTES_UP
c:\cygwin64\bin\scp.exe %thisdir_unix%sources/install.wim  %host%:wimage-rampe/install.wim
c:\cygwin64\bin\ssh.exe %host% mv wimage-rampe/FLAG_NEW_WIMAGE_IN_PROGRESS  wimage-rampe/FLAG_NEW_WIMAGE_EXISTS

:: shutdown

if %minutes_up% LEQ 5 ( shutdown -s -f )
