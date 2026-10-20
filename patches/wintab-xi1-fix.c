/*
 * wintab-xi1-fix.so — LD_PRELOAD shim for Wine's X11 driver (winex11.so).
 *
 * Problem: winex11's event filter (filter_event in dlls/winex11.drv/event.c)
 * only dequeues XInput 1 extension events — which carry tablet pressure for
 * wintab — when the app's message wait includes QS_SENDMESSAGE. Apps such as
 * Clip Studio Paint pump messages with input-only masks while drawing, so the
 * tablet events sit in Xlib's queue and the app sees a pen with no pressure
 * (and the eraser end behaves like the tip).
 *
 * Bug 2 (the main one): winex11's tablet_attach_queue() calls
 * XSelectExtensionEvent() once per tablet cursor (stylus, eraser, puck) on the
 * same window. Each call replaces the client's previous XInput 1 selection on
 * that window, so only the last device stays selected — on Xwayland that is
 * usually the "cursor" (puck), and the stylus/eraser events never arrive.
 * Fix: wrap XSelectExtensionEvent and always select the union of all classes
 * requested so far for that window.
 *
 * Xwayland also re-creates the tablet tool devices when the pen is used, which
 * drops every client's selection for them; so the merged selection is
 * re-applied from winex11's event loop about twice a second.
 *
 * Fix for the filter: wrap XCheckIfEvent. When the caller's predicate lives in winex11.so and
 * the wait mask asks for mouse input, also accept XInput 1 events (the range
 * reported by XQueryExtension("XInputExtension")). Everything else is passed
 * through to Wine's own predicate unchanged.
 *
 * Build: gcc -shared -fPIC -O2 -o wintab-xi1-fix.so wintab-xi1-fix.c -ldl
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <time.h>
#define DBG(...) do { if (getenv("WINTAB_XI1_FIX_DEBUG")) fprintf(stderr, "[xi1fix] " __VA_ARGS__); } while (0)
/* Bind to the oldest glibc symbol versions so a build made on a new distro
 * still loads on older ones (glibc >= 2.17). */
#if defined(__x86_64__) && defined(__GLIBC__)
__asm__(".symver dlvsym,dlvsym@GLIBC_2.2.5");
__asm__(".symver dladdr,dladdr@GLIBC_2.2.5");
__asm__(".symver pthread_mutex_lock,pthread_mutex_lock@GLIBC_2.2.5");
__asm__(".symver pthread_mutex_unlock,pthread_mutex_unlock@GLIBC_2.2.5");
__asm__(".symver clock_gettime,clock_gettime@GLIBC_2.17");
__asm__(".symver memcpy,memcpy@GLIBC_2.2.5");
#endif

typedef struct _XDisplay Display;
typedef union { int type; long pad[24]; } XEvent;
typedef int Bool;
typedef char *XPointer;
typedef Bool (*predicate_fn)(Display *, XEvent *, XPointer);

#define QS_MOUSEMOVE   0x0002
#define QS_MOUSEBUTTON 0x0004
#define XI1_EVENT_COUNT 17   /* IEVENTS in XI.h */

struct wrap_ctx { predicate_fn pred; XPointer arg; int xi_first; };

static Bool wrapped_pred(Display *d, XEvent *e, XPointer arg)
{
    struct wrap_ctx *c = (struct wrap_ctx *)arg;
    unsigned long mask = (unsigned long)c->arg;

    if (c->xi_first > 0 && e->type >= c->xi_first && e->type < c->xi_first + XI1_EVENT_COUNT &&
        (mask & (QS_MOUSEMOVE | QS_MOUSEBUTTON)))
        return 1;
    return c->pred(d, e, c->arg);
}

static int is_winex11(void *addr)
{
    Dl_info info;
    return dladdr(addr, &info) && info.dli_fname && strstr(info.dli_fname, "winex11");
}

static int xinput_first_event(Display *d)
{
    static __thread Display *cached_dpy;
    static __thread int cached = -1;
    static Bool (*query)(Display *, const char *, int *, int *, int *);
    int opcode, ev, err;

    if (d == cached_dpy) return cached;
    if (!query) query = dlsym(RTLD_DEFAULT, "XQueryExtension");
    cached = (query && query(d, "XInputExtension", &opcode, &ev, &err)) ? ev : 0;
    cached_dpy = d;
    return cached;
}

/* ---- XSelectExtensionEvent: accumulate classes per window ---- */
typedef unsigned long XEventClass;
#define MAX_WINDOWS 64
#define MAX_CLASSES 64
static struct { Display *dpy; unsigned long win; int n; XEventClass cls[MAX_CLASSES]; } sel[MAX_WINDOWS];
static pthread_mutex_t sel_lock = PTHREAD_MUTEX_INITIALIZER;

static int (*real_select)(Display *, unsigned long, XEventClass *, int);

int XSelectExtensionEvent(Display *d, unsigned long win, XEventClass *list, int count)
{
    int (*real)(Display *, unsigned long, XEventClass *, int);
    XEventClass merged[MAX_CLASSES];
    int i, j, n, slot = -1, free_slot = -1;

    if (!real_select) real_select = dlsym(RTLD_NEXT, "XSelectExtensionEvent");
    real = real_select;
    if (!is_winex11(__builtin_return_address(0))) return real(d, win, list, count);

    pthread_mutex_lock(&sel_lock);
    for (i = 0; i < MAX_WINDOWS; i++)
    {
        if (sel[i].dpy == d && sel[i].win == win) { slot = i; break; }
        if (!sel[i].dpy && free_slot < 0) free_slot = i;
    }
    if (slot < 0) slot = free_slot >= 0 ? free_slot : 0;
    if (sel[slot].dpy != d || sel[slot].win != win) { sel[slot].dpy = d; sel[slot].win = win; sel[slot].n = 0; }
    for (j = 0; j < count; j++)
    {
        for (i = 0; i < sel[slot].n; i++) if (sel[slot].cls[i] == list[j]) break;
        if (i == sel[slot].n && sel[slot].n < MAX_CLASSES) sel[slot].cls[sel[slot].n++] = list[j];
    }
    n = sel[slot].n;
    DBG("select win=%lx count=%d first=%lx -> merged %d\n", win, count, count ? list[0] : 0, n);
    memcpy(merged, sel[slot].cls, n * sizeof(*merged));
    pthread_mutex_unlock(&sel_lock);
    return real(d, win, merged, n);
}

static void reapply_selections(Display *d)
{
    static __thread struct timespec last;
    struct timespec now;
    int i;

    clock_gettime(CLOCK_MONOTONIC, &now);
    if ((now.tv_sec - last.tv_sec) * 1000 + (now.tv_nsec - last.tv_nsec) / 1000000 < 500) return;
    last = now;
    if (!real_select) return;
    pthread_mutex_lock(&sel_lock);
    for (i = 0; i < MAX_WINDOWS; i++)
        if (sel[i].dpy == d && sel[i].n) real_select(d, sel[i].win, sel[i].cls, sel[i].n);
    pthread_mutex_unlock(&sel_lock);
}

Bool XCheckIfEvent(Display *d, XEvent *e, predicate_fn pred, XPointer arg)
{
    static Bool (*real)(Display *, XEvent *, predicate_fn, XPointer);
    struct wrap_ctx ctx;

    if (!real) real = dlsym(RTLD_NEXT, "XCheckIfEvent");
    static __thread predicate_fn last_pred;
    static __thread int last_is_x11;
    if (!pred) return real(d, e, pred, arg);
    if (pred != last_pred) { last_is_x11 = is_winex11((void *)pred); last_pred = pred; }
    if (!last_is_x11) return real(d, e, pred, arg);

    reapply_selections(d);
    ctx.pred = pred;
    ctx.arg = arg;
    ctx.xi_first = xinput_first_event(d);
    return real(d, e, wrapped_pred, (XPointer)&ctx);
}

/* winex11 resolves libXi functions with dlsym(handle, ...), which bypasses
 * LD_PRELOAD interposition, so hand out our wrapper for that one symbol. */
static void *(*resolve_real_dlsym(void))(void *, const char *)
{
    static void *(*fn)(void *, const char *);
    if (!fn) fn = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.34");
    if (!fn) fn = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
    return fn;
}

void *dlsym(void *handle, const char *name)
{
    void *(*real)(void *, const char *) = resolve_real_dlsym();
    if (handle != RTLD_NEXT && handle != RTLD_DEFAULT && name && !strcmp(name, "XSelectExtensionEvent"))
    {
        void *p = real(handle, name);
        if (p && is_winex11(__builtin_return_address(0)))
        {
            if (!real_select) real_select = p;
            return (void *)XSelectExtensionEvent;
        }
        return p;
    }
    return real(handle, name);
}
