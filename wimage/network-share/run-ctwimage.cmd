set thisdir=%~dp0
echo %date:~-4%-%date:~-7,2%-%date:~-10,2% %time:~-11,2%:%time:~-8,2% > %thisdir%START
DEL /F /Q /A %thisdir%ctwimage\sources\install.wim
echo %date:~-4%-%date:~-7,2%-%date:~-10,2% > %thisdir%FLAG_NEW_CTWIMAGE_IN_PROGRESS
echo | %thisdir%ctwimage\ctwimage2b-64.bat
move  %thisdir%FLAG_NEW_CTWIMAGE_IN_PROGRESS  %thisdir%FLAG_NEW_CTWIMAGE_EXISTS
echo %date:~-4%-%date:~-7,2%-%date:~-10,2% %time:~-11,2%:%time:~-8,2% > %thisdir%END
