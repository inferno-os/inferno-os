#include	<sys/types.h>
#include	<signal.h>
#include 	<pwd.h>
#include	<sys/time.h>
#include	<sys/resource.h>
#include	<sys/wait.h>
#include	<fcntl.h>

#include	"dat.h"
#include	"fns.h"
#include	"error.h"

enum
{
	Debug = 0
};

/*
 * os-specific devcmd support.
 * this version should be reasonably portable across Unix systems.
 */
typedef struct Targ Targ;
struct Targ
{
	int	fd[2];	/* fd[0] is standard input, fd[1] is standard output */
	char**	args;
	char*	dir;
	int	pid;
	int	wfd;	/* child writes errors that occur after the fork or on exec */
	int	uid;
	int	gid;
};

extern int gidnobody;
extern int uidnobody;

static int
childproc(Targ *t)
{
	int i, nfd;

	if(Debug)
		print("devcmd: '%s'", t->args[0]);

	nfd = getdtablesize();
	for(i = 0; i < nfd; i++)
		if(i != t->fd[0] && i != t->fd[1] && i != t->wfd)
			close(i);

	dup2(t->fd[0], 0);
	dup2(t->fd[1], 1);
	dup2(t->fd[1], 2);
	close(t->fd[0]);
	close(t->fd[1]);

	if(t->gid != -1){
		if(setgid(t->gid) < 0 && getegid() == 0){
			fprint(t->wfd, "can't set gid %d: %s", t->gid, strerror(errno));
			_exit(1);
		}
	}

	if(t->uid != -1){
		if(setuid(t->uid) < 0 && geteuid() == 0){
			fprint(t->wfd, "can't set uid %d: %s", t->uid, strerror(errno));
			_exit(1);
		}
	}

	if(t->dir != nil && chdir(t->dir) < 0){
		fprint(t->wfd, "can't chdir to %s: %s", t->dir, strerror(errno));
		_exit(1);
	}

	signal(SIGPIPE, SIG_DFL);

	execvp(t->args[0], t->args);
	if(Debug)
		print("execvp: %s\n",strerror(errno));
	fprint(t->wfd, "exec failed: %s", strerror(errno));

	_exit(1);
}

void*
oscmd(char **args, int nice, char *dir, int *rfd, int *sfd)
{
	Targ *t;
	int r, fd0[2], fd1[2], wfd[2], n, pid;

	t = mallocz(sizeof(*t), 1);
	if(t == nil)
		return nil;

	fd0[0] = fd0[1] = -1;
	fd1[0] = fd1[1] = -1;
	wfd[0] = wfd[1] = -1;
	if(pipe(fd0) < 0 || pipe(fd1) < 0 || pipe(wfd) < 0)
		goto Error;
	if(fcntl(wfd[1], F_SETFD, FD_CLOEXEC) < 0)	/* close on exec to give end of file on success */
		goto Error;

	t->fd[0] = fd0[0];
	t->fd[1] = fd1[1];
	t->wfd = wfd[1];
	t->args = args;
	t->dir = dir;
	t->gid = up->env->gid;
	if(t->gid == -1)
		t->gid = gidnobody;
	t->uid = up->env->uid;
	if(t->uid == -1)
		t->uid = uidnobody;

	signal(SIGCHLD, SIG_DFL);
	switch(pid = fork()) {
	case -1:
		goto Error;
	case 0:
		setpgid(0, getpid());
		if(nice)
			oslopri();
		childproc(t);
		_exit(1);
	default:
		t->pid = pid;
		if(Debug)
			print("cmd pid %d\n", t->pid);
		break;
	}

	close(fd0[0]);
	close(fd1[1]);
	close(wfd[1]);

	n = read(wfd[0], up->genbuf, sizeof(up->genbuf)-1);
	close(wfd[0]);
	if(n > 0){
		close(fd0[1]);
		close(fd1[0]);
		free(t);
		up->genbuf[n] = 0;
		if(Debug)
			print("oscmd: bad exec: %q\n", up->genbuf);
		error(up->genbuf);
		return nil;
	}

	*sfd = fd0[1];
	*rfd = fd1[0];
	return t;

Error:
	r = errno;
	if(Debug)
		print("oscmd: %q\n",strerror(r));
	close(fd0[0]);
	close(fd0[1]);
	close(fd1[0]);
	close(fd1[1]);
	close(wfd[0]);
	close(wfd[1]);
	error(strerror(r));
	return nil;
}

int
oscmdkill(void *a)
{
	Targ *t = a;

	if(Debug)
		print("kill: %d\n", t->pid);
	return kill(-t->pid, SIGTERM);
}

int
oscmdwait(void *a, char *buf, int n)
{
	Targ *t = a;
	int s;

	if(waitpid(t->pid, &s, 0) == -1){
		if(Debug)
			print("wait error: %d [in %d] %q\n", t->pid, getpid(), strerror(errno));
		return -1;
	}
	if(WIFEXITED(s)){
		if(WEXITSTATUS(s) == 0)
			return snprint(buf, n, "%d 0 0 0 ''", t->pid);
		return snprint(buf, n, "%d 0 0 0 'exit: %d'", t->pid, WEXITSTATUS(s));
	}
	if(WIFSIGNALED(s)){
		if(WTERMSIG(s) == SIGTERM || WTERMSIG(s) == SIGKILL)
			return snprint(buf, n, "%d 0 0 0 killed", t->pid);
		return snprint(buf, n, "%d 0 0 0 'signal: %d'", t->pid, WTERMSIG(s));
	}
	return snprint(buf, n, "%d 0 0 0 'odd status: 0x%x'", t->pid, s);
}

void
oscmdfree(void *a)
{
	free(a);
}
