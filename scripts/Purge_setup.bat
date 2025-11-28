@echo off
setlocal EnableDelayedExpansion

REM ============================================================
REM   RAS QA - Non-Interactive Purge (GitHub Actions Friendly)
REM   Runner: GitHub Actions (windows-latest)
REM   Auth:   aws-actions/configure-aws-credentials (Secrets)
REM   Defaults: REGION=us-east-1 (no prompts), no AWS profile usage
REM ============================================================

REM ---- Defaults (can be overridden by workflow env) ----
if not defined REGION (
  set "REGION=us-east-1"
)
REM Optional: set a default namespace if you want (comment out if not needed)
REM if not defined NAMESPACE (
REM   set "NAMESPACE=207891-ras-search-ai-qa"
REM )

REM Export AWS default region to avoid any CLI prompts or profile needs
set "AWS_DEFAULT_REGION=%REGION%"

echo ============================================================
echo   Inputs (with defaults applied)
echo     REGION     = %REGION%
echo     CLUSTER    = %CLUSTER%
echo     NAMESPACE  = %NAMESPACE%
echo     QUEUE      = %QUEUE%
echo ============================================================
echo.

REM ---- Validate required inputs ----
if not defined CLUSTER (
  echo [ERROR] CLUSTER env var is not set.
  exit /b 1
)
if not defined NAMESPACE (
  echo [ERROR] NAMESPACE env var is not set.
  exit /b 1
)
if not defined QUEUE (
  echo [ERROR] QUEUE env var is not set (expected: westlaw or deep-research).
  exit /b 1
)

REM ---- Configure kubeconfig for EKS (no --profile) ----
echo Updating kubeconfig (region=%REGION%, cluster=%CLUSTER%)...
aws eks --region %REGION% update-kubeconfig --name %CLUSTER%
if %errorlevel% neq 0 (
    echo [ERROR] Failed to update kubeconfig.
    exit /b 1
)

REM ---- Quick cluster context info (optional) ----
echo Current k8s context:
kubectl config current-context
if %errorlevel% neq 0 (
    echo [WARN] Unable to show current context.
)

REM ---- List pods for visibility ----
echo Listing pods in namespace: %NAMESPACE%
kubectl get pods -n %NAMESPACE%
if %errorlevel% neq 0 (
    echo [ERROR] kubectl get pods failed (namespace may be wrong or RBAC denied).
    exit /b 1
)

REM ---- Find running ai-rag-monitor pod (tolerant pattern) ----
echo Finding running ai-rag-monitor pod...
set "MONITOR_POD="
for /f "tokens=1" %%A in ('kubectl get pods -n %NAMESPACE% ^| findstr /r /i "ai-rag-monitor.*Running"') do (
    set "MONITOR_POD=%%A"
    goto :found
)

:found
if not defined MONITOR_POD (
    echo [ERROR] No running ai-rag-monitor pod found by pattern: ai-rag-monitor.*Running
    echo [INFO] Pods with "monitor" substring:
    kubectl get pods -n %NAMESPACE% | findstr /i monitor
    exit /b 1
)

echo Found pod: %MONITOR_POD%
echo.

REM ---- Purge selected queue (non-interactive; try bash then sh) ----
echo Purging queue: %QUEUE% ...

REM First try bash
kubectl exec %MONITOR_POD% -n %NAMESPACE% -- bash -lc "celery -A main.celery_app purge -Q %QUEUE%"
set "RET=%errorlevel%"
if %RET% neq 0 (
    echo [WARN] bash not available or purge failed with bash. Trying sh...
    kubectl exec %MONITOR_POD% -n %NAMESPACE% -- sh -lc "celery -A main.celery_app purge -Q %QUEUE%"
    set "RET=%errorlevel%"
)

if %RET% neq 0 (
    echo [ERROR] Purge command failed (exit code %RET%).
    exit /b %RET%
)

echo ✓ Purge completed for '%QUEUE%'.
exit /b 0
