@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "LOG_SOURCE=D:\Steam\userdata\141261032\1066780\local\crash_dump\stdout.txt"
set "OUT_FILE=%~dp0EPOD-LOG.txt"

for /f "usebackq delims=" %%I in ("%LOG_SOURCE%") do (
  rem placeholder
)

if not exist "%LOG_SOURCE%" (
    echo ERROR: TF2 log not found at %LOG_SOURCE%
    echo.
    echo The source file does not exist, so no misleading EPOD log was created.
    exit /b 1
)

> "%OUT_FILE%" (
    echo EPOD Log Extract
    echo Generated: %date% %time%
    echo Source: %LOG_SOURCE%
    echo ============================================================
    echo.
)

findstr /I /R /C:"\[EPOD-UI\]" /C:"\[EPOD-TD\]" /C:"\[TD-UI\]" /C:"Lua exception" /C:"Error message:" /C:"epod_truck_distribution" "%LOG_SOURCE%" > "%TEMP%\epod_filtered.log"

if exist "%TEMP%\epod_filtered.log" (
    type "%TEMP%\epod_filtered.log" >> "%OUT_FILE%"
    del "%TEMP%\epod_filtered.log"
)

if not exist "%OUT_FILE%" (
    echo ERROR: Failed to create %OUT_FILE%
    exit /b 1
)

echo EPOD log extracted successfully.
echo %OUT_FILE%
exit /b 0
