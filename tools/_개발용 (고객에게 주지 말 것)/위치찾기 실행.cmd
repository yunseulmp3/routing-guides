@echo off
chcp 65001 > nul
title 앱별 오디오 장치 지정 - 위치 찾기
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0앱지정-위치찾기.ps1"
