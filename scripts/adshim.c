/* This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
 *
 * adshim: two glibc functions that the Autodarts board binary needs and that Alpine's musl libc
 * (with gcompat) does not provide. Built by autodarts-install.sh and loaded with LD_PRELOAD.
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <time.h>
#include <resolv.h>

/* glibc 2.30+: wait on a condition with a timeout measured on the given clock. musl only has
 * pthread_cond_timedwait (CLOCK_REALTIME), so convert the deadline to that clock. */
int pthread_cond_clockwait(pthread_cond_t *c, pthread_mutex_t *m,
                           clockid_t clk, const struct timespec *abs)
{
    if (clk == CLOCK_REALTIME)
        return pthread_cond_timedwait(c, m, abs);
    struct timespec now, rt, ts;
    clock_gettime(clk, &now);
    clock_gettime(CLOCK_REALTIME, &rt);
    long long ns = (long long)(abs->tv_sec - now.tv_sec) * 1000000000LL
                 + (abs->tv_nsec - now.tv_nsec);
    if (ns < 0) ns = 0;
    ns += (long long)rt.tv_sec * 1000000000LL + rt.tv_nsec;
    ts.tv_sec  = ns / 1000000000LL;
    ts.tv_nsec = ns % 1000000000LL;
    return pthread_cond_timedwait(c, m, &ts);
}

/* glibc's internal name for resolver initialisation. */
int __res_init(void) { return res_init(); }
