@echo off
setlocal enabledelayedexpansion

echo --------------------------------------
echo [1/5] Limpando e formatando o codigo...
call dart fix --apply
call dart format .

echo --------------------------------------
echo [2/5] Rodando linter (flutter analyze)...
call flutter analyze
if %errorlevel% neq 0 (
    echo.
    echo [ERRO] O linter encontrou problemas. Corrija-os antes de subir.
    pause
    exit /b 1
)

echo --------------------------------------
echo [3/5] Rodando testes automatizados (flutter test)...
call flutter test
if %errorlevel% neq 0 (
    echo.
    echo [ERRO] Falha na execucao dos testes. O processo foi abortado.
    pause
    exit /b 1
)

:: Pega o nome da branch atual
for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD') do set BRANCH=%%i

echo --------------------------------------
echo Branch atual: !BRANCH!
set /p MESSAGE="Digite a mensagem do commit: "

:: Se a mensagem for vazia, cancela
if "!MESSAGE!"=="" (
    echo [ERRO] A mensagem de commit nao pode ser vazia.
    pause
    exit /b 1
)

echo --------------------------------------
echo [4/5] Preparando commit...

:: Adiciona tudo
git add .

:: Tenta commitar. Se nao houver mudanças, o git avisa.
git commit -m "!MESSAGE!"
if %errorlevel% neq 0 (
    echo [AVISO] Nada para commitar ou erro no commit.
    pause
    exit /b 0
)

echo --------------------------------------
echo [5/5] Enviando para o GitHub (origin !BRANCH!)...
git push origin !BRANCH!

if %errorlevel% neq 0 (
    echo [ERRO] Falha ao enviar para o GitHub. Verifique sua conexao ou conflitos.
) else (
    echo --------------------------------------
    echo [SUCESSO] Pipeline finalizada para !BRANCH!.
)

pause