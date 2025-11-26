
@echo off
setlocal EnableDelayedExpansion

REM =========================
REM Inputs provided via env:
REM PROFILE, REGION, CLUSTER, NAMESPACE, QUEUE
REM (AWS OIDC is handled by the workflow, no CyberArk, no cloud-tool)
REM =========================

echo ============================================================
echo   RAS QA - Non-Interactive Purge (GitHub Actions Friendly)
echo ============================================================
echo.

REM ---- Configure kubeconfig for EKS ----
echo Updating kubeconfig...
aws eks --region %REGION% update-kubeconfig --name %CLUSTER% --profile %PROFILE%
if %errorlevel% neq 0 (
    echo [ERROR] Failed to update kubeconfig
    exit /b 1
)

REM ---- Find running ai-rag-monitor pod ----
echo Finding running ai-rag-monitor pod in namespace: %NAMESPACE% ...
set "MONITOR_POD="
for /f "tokens=1" %%A in ('kubectl get pods -n %NAMESPACE% ^| findstr /r "ai-rag-monitor-deployment-qa.*Running"') do (
    set "MONITOR_POD=%%A"
    goto :found
)

:found
if not defined MONITOR_POD (
    echo [ERROR] No running ai-rag-monitor pod found.
    kubectl get pods -n %NAMESPACE%
    exit /b 1
)

echo Found pod: %MONITOR_POD%
echo.

REM ---- Purge selected queue (non-interactive) ----
if not defined QUEUE (
    echo [ERROR] QUEUE env var not set (expected: westlaw or deep-research)
    exit /b 1
)

echo Purging queue: %QUEUE% ...
REM Important: no -it (no TTY in CI)
kubectl exec %MONITOR_POD% -n %NAMESPACE% -- bash -c "celery -A main.celery_app purge -Q %QUEUE%"
if %errorlevel% neq 0 (
    echo [ERROR] Purge command failed.
    exit /b 1
)

echo ✓ Purge completed for '%QUEUE%'.
exit /b 0
