/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2024 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_timer_engine_windows;

version(Windows):

//version = WindowsSetTimer; // Application must have a message loop for it to work

import core.atomic : atomicExchange, atomicLoad, atomicStore, cas;
import core.time : Duration, dur;
version(WindowsSetTimer)
{
    import core.sys.windows.basetsd : UINT_PTR;
    import core.sys.windows.windef : DWORD, HWND, UINT;
    import core.sys.windows.winbase : GetLastError;
    import core.sys.windows.winuser : KillTimer, SetTimer;
    pragma(lib, "user32");
}
else
{
    import core.sys.windows.basetsd : HANDLE;
    import core.sys.windows.winbase : CreateTimerQueue, CreateTimerQueueTimer, DeleteTimerQueue, DeleteTimerQueueTimer, GetLastError;
    import core.sys.windows.winnt : BOOLEAN, PVOID;
}

version(WindowsSetTimer)
    // 10=https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-settimer
    enum minResolutionInterval = dur!"msecs"(10);
else
    enum minResolutionInterval = dur!"msecs"(1);

alias TimerEngineCallback = void delegate(void* data) nothrow @safe;

struct TimerEngine
{
public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(TimerEngineCallback callback, void* callbackData) nothrow @safe
    {
        this.callback = callback;
        this.callbackData = callbackData;
        this.state = State.initial;
    }

    int start(scope const(Duration) interval) nothrow @trusted
    {
        debug(debug_pham_utl_utl_timer_engine_windows) debug writeln("TimerEngine.start()");

        atomicStore(state, State.start);

        const msecs = cast(uint)interval.total!"msecs";
        
        version(WindowsSetTimer)
        {
            hTimer = SetTimer(null, cast(UINT_PTR)&this, msecs, &timerRun);
            if (hTimer == UINT_PTR.init)
            {
                const failedResult = GetLastError();
                atomicStore(state, State.failed);
                return failedResult;
            }
        }
        else
        {
            hTimer = HANDLE.init;
            hQueue = CreateTimerQueue();
            if (hQueue is null)
            {
                const failedResult = GetLastError();
                atomicStore(state, State.failed);
                return failedResult;
            }

            if (!CreateTimerQueueTimer(&hTimer, hQueue, &timerRun, &this, 0, msecs, 0))
            {
                const failedResult = GetLastError();
                DeleteTimerQueue(hQueue);
                hQueue = HANDLE.init;
                atomicStore(state, State.failed);
                return failedResult;
            }
        }
        return 0;
    }

    void stop(const(bool) destroying) nothrow @trusted
    {
        debug(debug_pham_utl_utl_timer_engine_windows) debug writeln("TimerEngine.stop()");

        atomicStore(state, State.stopping);

        version(WindowsSetTimer)
        {
            if (hTimer != UINT_PTR.init)
            {
                KillTimer(null, hTimer);
                hTimer = UINT_PTR.init;
            }
        }
        else
        {
            if (hTimer !is HANDLE.init)
            {
                DeleteTimerQueueTimer(hQueue, hTimer, null);
                hTimer = HANDLE.init;
            }

            if (hQueue !is HANDLE.init)
            {
                DeleteTimerQueue(hQueue);
                hQueue = HANDLE.init;
            }
        }

        atomicStore(state, State.initial);
    }

    @property bool isRunning() const @nogc nothrow @safe
    {
        return atomicLoad(state) == State.start;
    }

private:
    enum State : size_t
    {
        initial,
        failed,
        start,
        stopping,
    }

    TimerEngineCallback callback;
    void* callbackData;
    State state;

private:
    version(WindowsSetTimer)
    {
        UINT_PTR hTimer;

        extern (Windows) static void timerRun(HWND, UINT, UINT_PTR ptr, DWORD) nothrow @trusted
        {
            debug(debug_pham_utl_utl_timer_engine_windows) debug writeln("TimerEngine.timerRun(begin)");
            assert(ptr != 0);

            auto engine = cast(TimerEngine*)ptr;
            engine.callback(engine.callbackData);

            debug(debug_pham_utl_utl_timer_engine_windows) debug writeln("TimerEngine.timerRun(end)");
        }
    }
    else
    {
        HANDLE hQueue;
        HANDLE hTimer;

        extern (Windows) static void timerRun(PVOID lpParam, BOOLEAN) nothrow @trusted
        {
            debug(debug_pham_utl_utl_timer_engine_windows) debug writeln("TimerEngine.timerRun(begin)");
            assert(lpParam !is null);

            auto engine = cast(TimerEngine*)lpParam;
            engine.callback(engine.callbackData);

            debug(debug_pham_utl_utl_timer_engine_windows) debug writeln("TimerEngine.timerRun(end)");
        }
    }
}
