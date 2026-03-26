@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul 2>&1
set CMAKE_GENERATOR=Ninja
set VULKAN_SDK=C:\VulkanSDK\1.4.341.1
cd /d C:\Users\voron\Documents\Projects\latera\rust
for /d %%i in (target\debug\build\llama-cpp-sys-2-*) do rmdir /s /q "%%i" 2>nul
cargo clippy --features vulkan > C:\Users\voron\Documents\Projects\latera\clippy_output.txt 2>&1
echo EXIT_CODE=%ERRORLEVEL% >> C:\Users\voron\Documents\Projects\latera\clippy_output.txt
