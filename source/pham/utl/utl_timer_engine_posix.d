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

module pham.utl.utl_timer_engine_posix;

version(Posix):

import core.atomic : atomicExchange, atomicLoad, atomicStore, cas;
import core.stdc.errno : errno;
import core.time : Duration, dur;
import core.stdc.string : memset;
import core.sys.linux.time;
import core.sys.posix.time;

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
        debug(debug_pham_utl_utl_timer_engine_posix) debug writeln("TimerEngine.start()");

        atomicStore(state, State.start);

        enum nanosecs = 1_000_000_000U;
        const nanosecsInterval = cast(ulong)interval.total!"hnsecs" * 100;
        const tv_sec = nanosecsInterval / nanosecs;
        const tv_nsec = nanosecsInterval % nanosecs;

        hTimer = timer_t.init;

        memset(&se, 0, sigevent.sizeof);
        se.sigev_notify = SIGEV_THREAD;
        se.sigev_value.sival_ptr = &this;
        se.sigev_notify_function = &timerRun;

        memset(&ts, 0, itimerspec.sizeof);
        ts.it_value.tv_sec = ts.it_interval.tv_sec = tv_sec;
        ts.it_value.tv_nsec = ts.it_interval.tv_nsec = tv_nsec;

        if (timer_create(CLOCK_BOOTTIME, &se, &hTimer) != 0)
        {
            const failedResult = errno;
            atomicStore(state, State.failed);
            return failedResult;
        }

        if (timer_settime(hTimer, 0, &ts, null) != 0)
        {
            const failedResult = errno;
            timer_delete(hTimer);
            hTimer = timer_t.init;
            atomicStore(state, State.failed);
            return failedResult;
        }

        return 0;
    }

    void stop(const(bool) destroying) nothrow @trusted
    {
        debug(debug_pham_utl_utl_timer_engine_posix) debug writeln("TimerEngine.stop()");

        atomicStore(state, State.stopping);

        if (hTimer != timer_t.init)
        {
            timer_delete(hTimer);
            hTimer = timer_t.init;
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
    timer_t hTimer;
    sigevent se;
    itimerspec ts;

    extern (C) static void timerRun(sigval arg) nothrow @trusted
    {
        debug(debug_pham_utl_utl_timer_engine_posix) debug writeln("TimerEngine.timerRun(begin)");
        assert(arg.sival_ptr !is null);

        auto engine = cast(TimerEngine*)arg.sival_ptr;
        engine.callback(engine.callbackData);

        debug(debug_pham_utl_utl_timer_engine_posix) debug writeln("TimerEngine.timerRun(end)");
    }
}
