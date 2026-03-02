@echo off
setlocal enabledelayedexpansion

echo ======================================
echo       VOLT-NET PUSH PIPELINE
echo ======================================

echo [1/5] Cleaning and formatting...
call dart fix --apply >nul 2>&1
call dart format . >nul 2>&1

echo [2/5] Running linter (analyze)...
call flutter analyze
if %errorlevel% neq 0 (
    echo [ERRO] Linter failed. Fix the issues before pushing.
    pause
    exit /b 1
)

echo [3/5] Running tests...
call flutter test
if %errorlevel% neq 0 (
    echo [ERRO] Tests failed. Process aborted.
    pause
    exit /b 1
)

:: Pega a branch atual
for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD') do set BRANCH=%%i
echo.
echo Current branch: !BRANCH!

:: PERGUNTA 1: MENSAGEM DO COMMIT
echo --------------------------------------
set /p MESSAGE="Enter commit message: "

if "!MESSAGE!"=="" (
    echo [ERRO] Commit message cannot be empty.
    pause
    exit /b 1
)

:: PERGUNTA 2: TIPO DE VERSAO
echo.
echo --------------------------------------
echo Select versioning type:
echo [1] feat     (New feature -> Minor bump)
echo [2] breaking (Major change -> Major bump)
echo [3] fix      (Patch/Other  -> Patch bump)
echo --------------------------------------
set /p CHOICE="Choose [1, 2 or 3]: "

if "!CHOICE!"=="1" (
    set FINAL_MSG=feat: !MESSAGE!
) else if "!CHOICE!"=="2" (
    set FINAL_MSG=BREAKING CHANGE: !MESSAGE!
) else (
    set FINAL_MSG=fix: !MESSAGE!
)

echo.
echo [4/5] Committing: "!FINAL_MSG!"
git add .
git commit -m "!FINAL_MSG!"

if %errorlevel% neq 0 (
    echo [AVISO] Nothing to commit.
    pause
    exit /b 0
)

echo [5/5] Pushing to origin !BRANCH!...
git push origin !BRANCH!

if %errorlevel% neq 0 (
    echo [ERRO] Push failed. Check your connection or conflicts.
) else (
    echo ======================================
    echo [SUCCESS] Pipeline finished!
    echo Version will be updated automatically on pub.dev.
    echo ======================================
)

pause
