@echo off
chcp 65001 > nul
title 앱 지정 상세 덤프
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0앱지정-상세덤프.ps1"
