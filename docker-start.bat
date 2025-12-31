@echo off
REM Docker Compose startup helper script for Windows
REM This script validates the environment and starts Docker Compose

echo ======================================
echo SynQc Docker Compose Setup ^& Validation
echo ======================================
echo.

REM Check if Docker is running
docker info >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Docker is not running
    echo         Please start Docker Desktop and try again
    exit /b 1
)
echo [OK] Docker is running

REM Check if docker-compose exists
docker compose version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set COMPOSE_CMD=docker compose
    echo [OK] Docker Compose is available
) else (
    docker-compose --version >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        set COMPOSE_CMD=docker-compose
        echo [OK] Docker Compose is available
    ) else (
        echo [ERROR] Docker Compose not found
        echo         Please install Docker Compose
        exit /b 1
    )
)

REM Check for required files
set "MISSING_FILES="
if not exist "docker-compose.yml" set "MISSING_FILES=%MISSING_FILES% docker-compose.yml"
if not exist "backend\Dockerfile" set "MISSING_FILES=%MISSING_FILES% backend\Dockerfile"
if not exist "backend\pyproject.toml" set "MISSING_FILES=%MISSING_FILES% backend\pyproject.toml"
if not exist "web\Dockerfile" set "MISSING_FILES=%MISSING_FILES% web\Dockerfile"
if not exist "web\index.html" set "MISSING_FILES=%MISSING_FILES% web\index.html"
if not exist "web\nginx.conf" set "MISSING_FILES=%MISSING_FILES% web\nginx.conf"

if not "%MISSING_FILES%"=="" (
    echo [ERROR] Required files not found:%MISSING_FILES%
    exit /b 1
)
echo [OK] All required files present

REM Clean up if requested
if "%1"=="--clean" goto cleanup
if "%1"=="-c" goto cleanup
goto build

:cleanup
echo.
echo Cleaning up old containers and volumes...
%COMPOSE_CMD% down -v 2>nul
echo [OK] Cleanup complete

:build
REM Build and start services
echo.
echo Building and starting services...
echo This may take a few minutes on first run...
echo.

%COMPOSE_CMD% up --build -d

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Failed to start services
    echo         Check the logs with: %COMPOSE_CMD% logs
    exit /b 1
)

echo.
echo ======================================
echo [OK] Services started successfully!
echo ======================================
echo.
echo Services:
echo   - API:   http://localhost:8001
echo   - Docs:  http://localhost:8001/docs
echo   - Web:   http://localhost:8080
echo   - Redis: localhost:6379
echo.
echo To view logs:
echo   %COMPOSE_CMD% logs -f
echo.
echo To stop services:
echo   %COMPOSE_CMD% down
echo.
echo To rebuild after code changes:
echo   %COMPOSE_CMD% up --build -d
echo.
