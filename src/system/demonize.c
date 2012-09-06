#include <stdio.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/stat.h>

/*
 * Detach a daemon process from whoever/whatever started it.
 * Mostly lifted from an article in the July/August 1987 ;login:,
 * by Dave Lennert (hplabs!hpda!davel). Blame bugs on me.
 */
/*
 |  [mea@funic.funet.fi]  Lifted this from Rayan Zachariassens
 |			  ZMailer support library.  Handy.
 */

char *getenv();

void
detach()
{
	int fd;			/* file descriptor */
	int fds;

	/*
	 * If launched by init (process 1), there's no need to detach.
	 *
	 * Note: this test is unreliable due to an unavoidable race
	 * condition if the process is orphaned.
	 */
	if (getppid() == 1)
		goto out;
	/* Ignore terminal stop signals */
#ifdef	SIGTTOU
	signal(SIGTTOU, SIG_IGN);
#endif	/* SIGTTOU */
#ifdef	SIGTTIN
	signal(SIGTTIN, SIG_IGN);
#endif	/* SIGTTIN */
#ifdef	SIGTSTP
	signal(SIGTSTP, SIG_IGN);
#endif	/* SIGTSTP */
	/*
	 * Allow parent shell to continue.
	 * Ensure the process is not a process group leader.
	 */
	if (fork() != 0)
		exit(0);	/* parent */
	/* child */
	/*
	 * Disassociate from controlling terminal and process group.
	 *
	 * Ensure the process can't reacquire a new controlling terminal.
	 * This is done differently on BSD vs. AT&T:
	 *
	 *	BSD won't assign a new controlling terminal
	 *	because process group is non-zero.
	 *
	 *	AT&T won't assign a new controlling terminal
	 *	because process is not a process group leader.
	 *	(Must not do a subsequent setpgrp()!)
	 */
#if	defined(USE_BSDSETPGRP) || defined(sun)
	setpgrp(0, getpid());	/* change process group */
	if ((fd = open("/dev/tty", O_RDWR, 0)) >= 0) {
		ioctl(fd, TIOCNOTTY, 0);	/* lose controlling terminal */
		close(fd);
	}
#else	/* !USE_BSDSETPGRP */
	/* lose controlling terminal and change process group */
	setpgrp();
	signal(SIGHUP, SIG_IGN);	/* immunge from pgrp leader death */
	if (fork() != 0)		/* become non-pgrp-leader */
		exit(0);	/* first child */
	/* second child */
#endif	/* USE_BSDSETPGRP */

out:
	close(0);
	close(1);
	close(2);
	fds = getdtablesize();
	for (fd = 3; fd < fds; ++fd)
		(void) close(fd);	/* close almost all file descriptors */
	(void) umask(022); /* clear any inherited file mode creation mask */

	/* Clean out our environment from personal contamination */
/*	cleanenv(); */

#ifdef	USE_RLIMIT
	/* In case this place runs with cpu limits, remove them */
	{	struct rlimit rl;
		rl.rlim_cur = RLIM_INFINITY;
		rl.rlim_max = RLIM_INFINITY;
		(void) setrlimit(RLIMIT_CPU, &rl);
	}
#endif	/* USE_RLIMIT */
	return;
}


#ifdef	USE_NOFILE
#ifndef	NOFILE
#define	NOFILE 20
#endif	/* NOFILE */

int
getdtablesize()
{
	return NOFILE;
}

#endif	/* USE_NOFILE */


main(argc,argv,arge)
     int argc;
     char *argv[];
     char *arge[];
{
  char *path = getenv("PATH");
  char prog[1024];
  char *p,**pp;
  int i;
  struct stat stats;
  char *demonize_debug = getenv("DEMONIZE_DEBUG");

  if(argc < 2){
	printf("%s: too few arguments!\n",*argv);
	printf("  demonize executable-file-name <optional args>\n");
	printf("  Environment variable 'DEMONIZE_DEBUG' will cause debug printouts\n");
	exit(0);
  }
  ++argv;
  *prog = 0;
  if (!path) path = "/bin:/usr/bin";
  if (((*argv)[0] == '/') ||
      ((*argv)[0] == '.' && (*argv)[1] == '/') ||
      ((*argv)[0] == '.' && (*argv)[1] == '.' && (*argv)[2] == '/')) {
    strcpy( prog,*argv );
    if( stat(prog,&stats) == 0 ) {
      if (demonize_debug)
        printf("Preparing to execute: %s\n",prog);
      /* Check for executability... ?? */
    } else {
      fprintf(stderr,"Can't execute: %s\n",*argv);
      exit(1);
    }
  } else  
    for(;;) {
      strcpy(prog,path);
      p = (char*)strchr(prog,':');
      if(p) { *p++ = '/'; *p = 0; }
      strcat(prog,*argv);
      if( stat(prog,&stats) == 0 ) {
	if (demonize_debug)
	  printf("Preparing to execute: %s\n",prog);
	break;  /* Check for executability... ?? */
      }
      if(p = (char*)strchr(path,':')) path = ++p;
      else {
	fprintf(stderr,"Can't execute: %s\n",*argv);
	exit(1);
      }
    }
  
  detach();
  execve(prog,argv,arge);
}

