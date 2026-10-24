@echo off
echo [mircoduck-lew Source] https://github.com/lucienxxxxxx/mircoduck-lew
setlocal
set "MICRODUCK_CONSOLE_ROOT=%~dp0"
cd /d "%TEMP%"
set "PYTHONUTF8=1"
where py >nul 2>nul
if errorlevel 1 goto use_python
py -3 "%MICRODUCK_CONSOLE_ROOT%console.py" --dashboard --feetech --open
goto finish
:use_python
python "%MICRODUCK_CONSOLE_ROOT%console.py" --dashboard --feetech --open
:finish
if errorlevel 1 pause
endlocal
