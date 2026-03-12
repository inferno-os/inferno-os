/*
 * InferNode Windows Launcher
 *
 * Starts llm9p.exe (if present and not already running) then launches
 * the InferNode emulator with Lucifer GUI.  Built as a Windows GUI
 * subsystem app so no console window flashes on double-click.
 *
 * Compile:
 *   cl /O2 /Fe:InferNode.exe infernode-launcher.c /link /subsystem:windows
 */

#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <TlHelp32.h>
#include <stdio.h>

static int
is_process_running(const char *name)
{
	HANDLE snap;
	PROCESSENTRY32 pe;
	int found = 0;

	snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
	if (snap == INVALID_HANDLE_VALUE)
		return 0;

	pe.dwSize = sizeof(pe);
	if (Process32First(snap, &pe)) {
		do {
			if (_stricmp(pe.szExeFile, name) == 0) {
				found = 1;
				break;
			}
		} while (Process32Next(snap, &pe));
	}
	CloseHandle(snap);
	return found;
}

int WINAPI
WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance,
	LPSTR lpCmdLine, int nCmdShow)
{
	char dir[MAX_PATH];
	char path[MAX_PATH];
	STARTUPINFOA si;
	PROCESS_INFORMATION pi;

	(void)hInstance;
	(void)hPrevInstance;
	(void)lpCmdLine;
	(void)nCmdShow;

	/* Get directory containing this exe */
	GetModuleFileNameA(NULL, dir, MAX_PATH);
	{
		char *slash = strrchr(dir, '\\');
		if (slash) *slash = '\0';
	}

	SetCurrentDirectoryA(dir);

	/* Start llm9p if not already running */
	_snprintf(path, sizeof(path), "%s\\llm9p.exe", dir);
	if (GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES && !is_process_running("llm9p.exe")) {
		char cmd[MAX_PATH + 64];
		_snprintf(cmd, sizeof(cmd),
			"\"%s\" -backend cli -addr :5640", path);

		memset(&si, 0, sizeof(si));
		si.cb = sizeof(si);
		si.dwFlags = STARTF_USESHOWWINDOW;
		si.wShowWindow = SW_HIDE;

		CreateProcessA(NULL, cmd, NULL, NULL, FALSE,
			CREATE_NO_WINDOW, NULL, dir, &si, &pi);
		CloseHandle(pi.hProcess);
		CloseHandle(pi.hThread);
		Sleep(1000);
	}

	/* Launch InferNode emu with Lucifer GUI */
	{
		char cmd[MAX_PATH * 2];
		_snprintf(cmd, sizeof(cmd),
			"\"%s\\o.emu.exe\" -c1 -g 1280x800"
			" -pheap=512m -pmain=512m -pimage=512m"
			" -r . lucifer",
			dir);

		memset(&si, 0, sizeof(si));
		si.cb = sizeof(si);

		if (!CreateProcessA(NULL, cmd, NULL, NULL, FALSE,
				0, NULL, dir, &si, &pi)) {
			MessageBoxA(NULL,
				"Failed to start InferNode.\n\n"
				"Make sure o.emu.exe and SDL3.dll are present.",
				"InferNode", MB_OK | MB_ICONERROR);
			return 1;
		}

		/* Wait for emu to exit */
		WaitForSingleObject(pi.hProcess, INFINITE);
		CloseHandle(pi.hProcess);
		CloseHandle(pi.hThread);
	}

	return 0;
}
