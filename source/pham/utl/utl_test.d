/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.test;

import core.time : Duration, MonoTime, dur;
import core.sync.mutex : Mutex;

nothrow @safe:

struct PerfCpuUsage
{
@nogc nothrow @safe:

public:
    static PerfCpuUsage get() @trusted
    {
        static PerfCpuUsage errorResult() pure
        {
            return PerfCpuUsage(Duration.max, Duration.max);
        }

	    version (Windows)
        {
            import core.sys.windows.windows : FILETIME, GetCurrentProcess, GetProcessTimes;
	        //import core.sys.windows.psapi : PROCESS_MEMORY_COUNTERS, GetProcessMemoryInfo;

		    FILETIME creationTime; // time that process was created
		    FILETIME exitTime; // undefined if process has not exited
		    FILETIME kernelTime; // ru_stime
		    FILETIME userTime; // ru_utime
		    auto currentProcess = GetCurrentProcess();
		    if (GetProcessTimes(currentProcess, &creationTime, &exitTime, &kernelTime, &userTime) == 0)
			    return errorResult();

		    static Duration toMicroSeconds(in FILETIME ft) pure
            {
			    return dur!"usecs"((cast(long)ft.dwHighDateTime << 32 | ft.dwLowDateTime) / 10);
		    }

            PerfCpuUsage result;
		    result.kernelTime = toMicroSeconds(kernelTime);
		    result.userTime = toMicroSeconds(userTime);
            return result;
	    }
        else version (Posix)
        {
            import core.sys.posix.sys.resource: rusage, getrusage, RUSAGE_SELF, timeval;

		    rusage rusageStruct;
		    if (getrusage(RUSAGE_SELF, &rusageStruct) == -1)
                return errorResult();

		    static Duration toMicroSeconds(in timeval t) pure
            {
			    return dur!"usecs"(cast(long)t.tv_sec * 1_000_000L + t.tv_usec);
		    }

            PerfCpuUsage result;
		    result.kernelTime = toMicroSeconds(rusageStruct.ru_stime);
		    result.userTime = toMicroSeconds(rusageStruct.ru_utime);
            return result;
	    }
        else
            static assert(false, "Platform not implemented");
    }

public:
	/// Time that the process has executed in kernel mode in microseconds
	Duration kernelTime;

	/// Time that the process has executed in user mode in microseconds
	Duration userTime;
}

struct PerfFunction
{
nothrow @safe:

public:
    static typeof(this) create(in string name = __FUNCTION__) pure
    {
        typeof(this) result;
        result.name = name;
        debug result.startedTime = MonoTime.currTime;
        return result;
    }

    version (profile)
    ~this() pure
    {
        if (name.length)
            debug PerfFunctionCounter.profile(name, elapsedTime());
    }

    Duration elapsedTime() const @nogc
    {
        return MonoTime.currTime - startedTime;
    }

public:
    string name;
    MonoTime startedTime;
}

struct PerfFunctionCounter
{
nothrow @safe:

public:
    this(in string name, in Duration elapsedTime) pure
    {
        this._name = name;
        this._count = 1;
        this._elapsedTime = elapsedTime;
    }

    long elapsedTimeMsecs() const pure
    {
        return elapsedTime.total!"msecs"();
    }

    long elapsedTimeUsecs() const pure
    {
        return elapsedTime.total!"usecs"();
    }

    version (profile)
    static void profile(in string name, in Duration elapsedTime) @trusted
    in
    {
        assert(name.length != 0);
    }
    do
    {
        import pham.utl.object : RAIIMutex;

        auto raiiMutex = RAIIMutex(countersMutex);
        auto existedCounter = name in counters;
        if (existedCounter !is null)
        {
            (*existedCounter)._count++;
            (*existedCounter)._elapsedTime += elapsedTime;
        }
        else
        {
            counters[name] = PerfFunctionCounter(name, elapsedTime);
        }
    }

    @property size_t count() const @nogc pure
    {
        return _count;
    }

    @property Duration elapsedTime() const @nogc pure
    {
        return _elapsedTime;
    }

    @property string name() const @nogc pure
    {
        return _name;
    }

private:
    version (profile)
    static void saveProfile(string fileName) @trusted
    {
        import std.algorithm : sort;
        import std.format : format;
        import std.stdio : File;

        scope (failure) assert(0);

        auto counterValues = counters.values;
        counterValues.sort!("a.elapsedTime > b.elapsedTime"); // Sort in descending order

        File file;
        file.open(fileName, "w");
        scope (exit)
            file.close();
        file.writeln("function,msecs,usecs,count,%");
        foreach (ref value; counterValues)
        {
            const msecs = value.elapsedTimeMsecs();
            const usecs = value.elapsedTimeUsecs();
            file.writeln(value.name,
                ",", format!"%,3?d"('_', msecs),
                ",", format!"%,3?d"('_', usecs),
                ",", format!"%,3?d"('_', value.count),
                ",", format!"%.2f"((usecs / cast(double)value.count) * 100.0));
        }
    }

private:
    string _name;
    size_t _count;
    Duration _elapsedTime;
    version (profile)
    {
        __gshared static PerfFunctionCounter[string] counters;
        __gshared static Mutex countersMutex;
    }
}

struct PerfTestResult
{
@nogc nothrow @safe:

    size_t count;
    Duration elapsedTime;
    MonoTime startedTime;

    static typeof(this) create() pure
    {
        typeof(this) result;
        result.reset();
        return result;
    }

    long elapsedTimeMsecs() const pure
    {
        return elapsedTime.total!"msecs"();
    }

    long elapsedTimeUsecs() const pure
    {
        return elapsedTime.total!"usecs"();
    }

    void end() pure
    {
        debug elapsedTime = MonoTime.currTime - startedTime;
    }

    void reset() pure
    {
        count = 0;
        elapsedTime = Duration.zero;
        debug startedTime = MonoTime.currTime;
    }
}

version (unittest)
{
    import std.conv : to;
    import std.format : format;
    import std.traits : isSomeChar;

    void dgFunctionTrace(A...)(A args,
        int line = __LINE__,
        string functionName = __FUNCTION__)
    {
        try
        {
            debug dgWrite(functionName, "(", line, ")");
            if (args.length)
            {
                debug dgWrite(": ");
                debug dgWriteln(args);
            }
            else
                debug dgWriteln("");
        }
        catch (Exception)
        {}
    }

	static ubyte[] dgReadAllBinary(string fileName) nothrow @trusted
    {
		import std.stdio;
		import std.file;

		try
        {
			auto f = File(fileName);
			f.seek(0, SEEK_END);
			auto size = cast(size_t)f.tell();
			f.seek(0, SEEK_SET);
			auto result = new ubyte[size];
			f.rawRead(result);
			return result;
		}
		catch (Exception e)
        {
			debug dgWriteln("fileName=", fileName, ", e.msg=", e.msg);
			return null;
        }
    }

    string dgToHex(ubyte n) @nogc nothrow pure @safe
    {
        debug return format!"%.2X"(n);
    }

    string dgToHex(ushort n) @nogc nothrow pure @safe
    {
        debug return format!"%.4X"(n);
    }

    string dgToHex(uint n) @nogc nothrow pure @safe
    {
        debug return format!"%.8X"(n);
    }

    string dgToHex(ulong n) @nogc nothrow pure @safe
    {
        debug return format!"%.16X"(n);
    }

    string dgToHex(scope const(ubyte)[] b) @nogc nothrow pure @safe
    {
        import pham.utl.object : bytesToHexs;

        debug return bytesToHexs(b);
    }

    string dgToStr(int n) @nogc nothrow pure @safe
    {
        debug return format!"%d"(n);
    }

    string dgToStr(long n) @nogc nothrow pure @safe
    {
        debug return format!"%d"(n);
    }

    void dgWrite(A...)(A args) nothrow
    {
        import std.stdio : write;

        try
        {
            debug write(args);
        }
        catch (Exception)
        {}
    }

    void dgWritef(Char, A...)(in Char[] fmt, A args) nothrow
    if (isSomeChar!Char)
    {
        import std.stdio : writef;

        try
        {
            debug writef(fmt, args);
        }
        catch (Exception)
        {}
    }

    void dgWriteln(A...)(A args) nothrow
    {
        import std.stdio : writeln;

        try
        {
            debug writeln(args);
        }
        catch (Exception)
        {}
    }

    void dgWriteln(const(char)[] prefix, scope const(ubyte)[] bytes) nothrow
    {
        import pham.utl.object : bytesToHexs;

        try
        {
            debug dgWriteln(prefix, bytesToHexs(bytes));
        }
        catch (Exception)
        {}
    }

    void dgWritefln(Char, A...)(in Char[] fmt, A args) nothrow
    if (isSomeChar!Char)
    {
        import std.stdio : writefln;

        try
        {
            debug writefln(fmt, args);
        }
        catch (Exception)
        {}
    }

    void traceUnitTest(A...)(A args) nothrow
    {
        version (TraceUnitTest)
        {
            import std.stdio : writeln;

            try
            {
                debug writeln(args);
            }
            catch (Exception)
            {}
        }
    }
}


private:

shared static this() @trusted
{
    version (profile) PerfFunctionCounter.countersMutex = new Mutex();

    version (TraceInvalidMemoryOp)
    {
        import core.exception;
        import pham.utl.test;
        dgWriteln("utl.utltest.shared static this()");

        assertHandler(null);
    }
}

shared static ~this() @trusted
{
    version (profile)
    {
        if (PerfFunctionCounter.countersMutex !is null)
        {
            PerfFunctionCounter.countersMutex.destroy();
            PerfFunctionCounter.countersMutex = null;
        }

        if (PerfFunctionCounter.counters.length != 0)
        {
            PerfFunctionCounter.saveProfile("profile.csv");
            PerfFunctionCounter.counters = null;
        }
    }
}

unittest // PerfCpuUsage
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.utltest.PerfCpuUsage");

    const cpuTime = PerfCpuUsage.get();
    assert(cpuTime.kernelTime != Duration.max && cpuTime.kernelTime.total!"usecs"() > 0);
    assert(cpuTime.userTime != Duration.max && cpuTime.userTime.total!"usecs"() > 0);
}
