@echo off
setlocal enabledelayedexpansion

echo ============================================================
echo             VOLT-NET: HIGH PERFORMANCE PUSH
echo ============================================================

echo [1/5] Cleaning and formatting code...
call dart fix --apply >nul 2>&1
call dart format . >nul 2>&1

echo [2/5] Running static analysis (Linter)...
call flutter analyze
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Analysis failed. Please fix the warnings above.
    pause
    exit /b 1
)

echo [3/5] Running automated tests...
call flutter test
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Tests failed. Aborting push to protect the repo.
    pause
    exit /b 1
)

:: Get current branch
for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD') do set BRANCH=%%i
echo.
echo Working on branch: [!BRANCH!]

echo ============================================================
echo 1. COMMIT MESSAGE
echo ============================================================
set /p MESSAGE="Describe your changes: "

if "!MESSAGE!"=="" (
    echo [ERROR] Message is required.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo 2. VERSIONING STRATEGY (Semantic Versioning)
echo ============================================================
echo  [1] FEATURE (feat)      -> Use for NEW functionalities.
echo                             Increments MINOR (ex: 1.0.0 to 1.1.0)
echo.
echo  [2] BREAKING (major)    -> Use for INCOMPATIBLE changes.
echo                             Increments MAJOR (ex: 1.0.0 to 2.0.0)
echo.
echo  [3] BUG FIX / OTHER     -> Use for fixes, docs, or refactors.
echo                             Increments PATCH (ex: 1.0.0 to 1.0.1)
echo ============================================================
echo.
set /p CHOICE="Select the level of change [1, 2 or 3] (Default is 3): "

if "!CHOICE!"=="1" (
    set FINAL_MSG=feat: !MESSAGE!
) else if "!CHOICE!"=="2" (
    set FINAL_MSG=BREAKING CHANGE: !MESSAGE!
) else (
    set FINAL_MSG=fix: !MESSAGE!
)

echo.
echo ------------------------------------------------------------
echo Summary: !FINAL_MSG!
echo ------------------------------------------------------------
echo.

echo [4/5] Committing changes...
git add .
git commit -m "!FINAL_MSG!"

if %errorlevel% neq 0 (
    echo [SKIP] No changes detected to commit.
    pause
    exit /b 0
)

echo [5/5] Pushing to origin !BRANCH!...
git push origin !BRANCH!

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Push failed. Check your connection or git conflicts.
) else (
    echo.
    echo ============================================================
    echo   SUCCESS: Pipeline completed for !BRANCH!
    echo   The CI/CD will now handle the release on pub.dev.
    echo ============================================================
)

pause
