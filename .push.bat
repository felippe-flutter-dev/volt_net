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
echo 1. COMMIT SUBJECT (Short Summary)
echo ============================================================
set /p MESSAGE="Summary: "

if "!MESSAGE!"=="" (
    echo [ERROR] Summary is required.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo 2. EXTENDED DESCRIPTION (Optional - For the Robot/Changelog)
echo ============================================================
set /p DESC="Details (press Enter to skip): "

echo.
echo ============================================================
echo 3. VERSIONING STRATEGY (Semantic Versioning)
echo ============================================================
echo  [1] FEATURE (feat)      -> New functionalities.
echo  [2] BREAKING (major)    -> Incompatible changes.
echo  [3] BUG FIX / OTHER     -> Fixes, docs, or refactors. [Default]
echo ============================================================
set /p CHOICE="Selection [1, 2 or 3]: "

if "!CHOICE!"=="1" (
    set FINAL_SUBJ=feat: !MESSAGE!
) else if "!CHOICE!"=="2" (
    set FINAL_SUBJ=BREAKING CHANGE: !MESSAGE!
) else (
    set FINAL_SUBJ=fix: !MESSAGE!
)

echo.
echo [4/5] Committing changes...
git add .

:: Se houver descrição longa, faz commit com corpo
if "!DESC!"=="" (
    git commit -m "!FINAL_SUBJ!"
) else (
    git commit -m "!FINAL_SUBJ!" -m "!DESC!"
)

if %errorlevel% neq 0 (
    echo [SKIP] No changes detected.
    pause
    exit /b 0
)

echo [5/5] Pushing to origin !BRANCH!...
git push origin !BRANCH!

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Push failed.
) else (
    echo.
    echo ============================================================
    echo   SUCCESS: Pipeline completed!
    echo ============================================================
)

pause
