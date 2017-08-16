/* popen and pclose are not part of win 95 and nt,
   but it appears that _popen and _pclose "work".
   if this won't load, use the return NULL statements. */

#include <stdio.h>
FILE *popen(char *s, char *m) {
	return _popen(s, m);	/* return NULL; */
}

int pclose(FILE *f) {
	return _pclose(f);	/* return NULL; */
}

#include <windows.h>
#include <winbase.h>
#include <winsock.h>

/* system doesn't work properly in some 32/64 (WoW64) combinations */
int system(char *s) {
	int status, n;
	PROCESS_INFORMATION pinfo;
	STARTUPINFO si;
	char *cmd;
	char app[256];
	static char cmdexe[] = "\\cmd.exe";

	memset(&si, 0, sizeof(si));
	si.cb = sizeof(si);
//	si.dwFlags = STARTF_USESHOWWINDOW;
//	si.wShowWindow = SW_SHOW;

	n = GetSystemDirectory(app, sizeof(app)-sizeof(cmdexe));
	if(n > sizeof(app))
		return -1;
	strcat_s(app, sizeof(app), cmdexe);
	n = strlen(s)+20;
	cmd = malloc(n);
	if(cmd == NULL)
		return -1;
	strcpy_s(cmd, n, "cmd.exe /c");
	strcat_s(cmd, n, s);
	if(!CreateProcess(app, cmd, NULL, NULL, TRUE, CREATE_DEFAULT_ERROR_MODE, NULL/* env*/, NULL /*wdir*/, &si, &pinfo)){
		fprintf(stderr, "can't create process %s %d\n", s, GetLastError());
		free(cmd);
		return -1;
	}
	free(cmd);
	if(WaitForSingleObject(pinfo.hProcess, INFINITE) == WAIT_FAILED)
		return -1;
	if(!GetExitCodeProcess(pinfo.hProcess, &status))
		status = 1;
	//fprintf(stderr, "status %d\n", status);
	return status;
}
