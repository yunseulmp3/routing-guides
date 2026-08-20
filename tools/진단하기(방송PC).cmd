@echo off
chcp 65001 > nul
title 윤슬 라우팅 닥터 - 방송PC
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0routing-doctor.ps1" -Setup Stream
