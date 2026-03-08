@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d "%~dp0"
echo Compiling InferNode.exe...
cl /O2 /MT /Fe:InferNode.exe infernode-launcher.c /link /subsystem:windows shell32.lib
if exist InferNode.exe (
    echo SUCCESS: InferNode.exe built
) else (
    echo FAILED to build InferNode.exe
)
del infernode-launcher.obj 2>nul
