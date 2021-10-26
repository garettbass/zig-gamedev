@echo off
setlocal enableextensions enabledelayedexpansion
cd samples
for /D %%G in (*) do (
    cd %%G
    echo --- %%G --- output directory is "samples\%%G\zig-out\bin"
    zig build -Dtarget=x86_64-windows-gnu -Drelease-fast=true
    if exist imgui.ini del imgui.ini
    if exist zig-out\bin\*.pdb del zig-out\bin\*.pdb
    if exist zig-out\bin\imgui.ini del zig-out\bin\imgui.ini
    if exist zig-out\bin\d3d12\D3D12SDKLayers.dll del zig-out\bin\d3d12\D3D12SDKLayers.dll
    if exist zig-out\bin\d3d12\DirectML.Debug.dll del zig-out\bin\d3d12\DirectML.Debug.dll    
    if exist zig-out\bin\d3d12\*.pdb del zig-out\bin\d3d12\*.pdb
    if exist zig-cache rmdir /s /q zig-cache
    cd..
)
cd..