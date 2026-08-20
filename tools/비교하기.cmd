@echo off
chcp 65001 > nul
title 윤슬 라우팅 닥터 - 기준선 비교
if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0routing-doctor.ps1" -Compare pick
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0routing-doctor.ps1" -Compare "%~1"
)
