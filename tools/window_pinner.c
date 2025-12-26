/*
 * window_pinner - Pins Quillex test windows to the current desktop
 *
 * Event-driven X11 daemon that watches for "Quillex (Test)" windows
 * and moves them to whichever desktop was active when this program
 * started. Run this on your "test desktop" to keep spex tests from
 * popping up while you work on other desktops.
 *
 * How it works:
 *   1. On startup, reads _NET_CURRENT_DESKTOP to get target desktop
 *   2. Subscribes to X11 window creation/property events
 *   3. When a window with "Quillex (Test)" in title appears,
 *      sends _NET_WM_DESKTOP client message to move it
 *
 * Build: cd tools && make
 * Usage: ./window_pinner
 *        (run in foreground, Ctrl+C to stop)
 *
 * Dependencies: libX11 only (uses EWMH protocol)
 */

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

#define MATCH_TITLE "Quillex (test)"

// Global X11 connection and atom handles for EWMH properties.
static Display *dpy;
static Atom net_wm_desktop;
static Atom net_current_desktop;
static Atom net_wm_name;
static Atom utf8_string;

// Event loop control flag, flipped by signal handler.
static volatile int running = 1;

// The desktop index captured at startup.
static int target_desktop = 0;

// Signal handler: stop the event loop gracefully.
void cleanup(int sig) {
    (void)sig;
    running = 0;
}

// Read _NET_CURRENT_DESKTOP from the root window.
int get_current_desktop(void) {
    Atom type;
    int format;
    unsigned long nitems, bytes_after;
    unsigned char *data = NULL;
    int desktop = 0;

    // XA_CARDINAL is the standard type for desktop indices.
    if (XGetWindowProperty(dpy, DefaultRootWindow(dpy), net_current_desktop,
                           0, 1, False, XA_CARDINAL, &type, &format,
                           &nitems, &bytes_after, &data) == Success && data) {
        desktop = *(long *)data;
        XFree(data);
    }
    return desktop;
}

// Fetch a window title, trying UTF-8 first, then the legacy WM_NAME.
char *get_window_title(Window win) {
    Atom type;
    int format;
    unsigned long nitems, bytes_after;
    unsigned char *data = NULL;

    // Modern title: _NET_WM_NAME with UTF8_STRING.
    if (XGetWindowProperty(dpy, win, net_wm_name, 0, 256, False,
                           utf8_string, &type, &format, &nitems,
                           &bytes_after, &data) == Success && data) {
        return (char *)data;
    }

    // Fallback: old WM_NAME with XA_STRING.
    if (XGetWindowProperty(dpy, win, XA_WM_NAME, 0, 256, False,
                           XA_STRING, &type, &format, &nitems,
                           &bytes_after, &data) == Success && data) {
        return (char *)data;
    }

    return NULL;
}

// Ask the window manager to move a window to target_desktop.
void move_to_desktop(Window win) {
    XEvent ev = {0};
    ev.xclient.type = ClientMessage;
    ev.xclient.window = win;
    ev.xclient.message_type = net_wm_desktop;
    ev.xclient.format = 32;
    ev.xclient.data.l[0] = target_desktop;
    ev.xclient.data.l[1] = 1;

    // Send to root so the WM handles it; event masks are per EWMH.
    XSendEvent(dpy, DefaultRootWindow(dpy), False,
               SubstructureRedirectMask | SubstructureNotifyMask, &ev);
    XFlush(dpy);
}

// Check a window title and pin it if it matches MATCH_TITLE.
void check_window(Window win) {
    char *title = get_window_title(win);
    if (title) {
        if (strstr(title, MATCH_TITLE)) {
            printf("Pinning '%s' to desktop %d\n", title, target_desktop);
            move_to_desktop(win);
        }
        XFree(title);
    }
}

// Subscribe to events for a window and all its children.
void select_events_recursive(Window win) {
    Window root, parent, *children;
    unsigned int nchildren;

    // Track new windows and title changes beneath this window.
    XSelectInput(dpy, win, SubstructureNotifyMask | PropertyChangeMask);

    if (XQueryTree(dpy, win, &root, &parent, &children, &nchildren)) {
        for (unsigned int i = 0; i < nchildren; i++) {
            select_events_recursive(children[i]);
        }
        if (children) XFree(children);
    }
}

int main(void) {
    // Connect to the X server (uses DISPLAY from environment).
    dpy = XOpenDisplay(NULL);
    if (!dpy) {
        fprintf(stderr, "Cannot open display\n");
        return 1;
    }

    // Cache atom identifiers used by EWMH.
    net_wm_desktop = XInternAtom(dpy, "_NET_WM_DESKTOP", False);
    net_current_desktop = XInternAtom(dpy, "_NET_CURRENT_DESKTOP", False);
    net_wm_name = XInternAtom(dpy, "_NET_WM_NAME", False);
    utf8_string = XInternAtom(dpy, "UTF8_STRING", False);

    // Pin target is the desktop active at startup.
    target_desktop = get_current_desktop();

    // Listen for window events across the existing tree.
    select_events_recursive(DefaultRootWindow(dpy));

    // Exit cleanly on Ctrl+C or termination.
    signal(SIGINT, cleanup);
    signal(SIGTERM, cleanup);

    printf("Pinning '%s' windows to desktop %d (current)\n", MATCH_TITLE, target_desktop);

    XEvent ev;
    while (running) {
        // Block until the next X event arrives.
        XNextEvent(dpy, &ev);

        switch (ev.type) {
            case CreateNotify:
                // New window created: subscribe to its events.
                XSelectInput(dpy, ev.xcreatewindow.window,
                            SubstructureNotifyMask | PropertyChangeMask);
                break;
            case MapNotify:
                // Window became visible; check its title now.
                check_window(ev.xmap.window);
                break;
            case PropertyNotify:
                // Title changed; re-check for a match.
                if (ev.xproperty.atom == net_wm_name ||
                    ev.xproperty.atom == XA_WM_NAME) {
                    check_window(ev.xproperty.window);
                }
                break;
        }
    }

    // Cleanup X connection before exit.
    XCloseDisplay(dpy);
    printf("Exiting\n");
    return 0;
}
