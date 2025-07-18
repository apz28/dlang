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

module pham.utl.utl_test;

version(TraceFunction)
    version = TraceLog;
else version(TraceUnitTest)
    version = TraceLog;

import core.time : Duration, MonoTime, dur;
import core.sync.mutex : Mutex;
version(TraceLog)
{
    import pham.external.std.log.log_logger : defaultOutputPattern, FileLogger, FileLoggerOption, LoggerOption,
        LogLevel, LogLocation, OutputPattern;
}

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

	    version(Windows)
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

		    static Duration toMicroSeconds(scope const(FILETIME) ft) pure
            {
			    return dur!"usecs"((cast(long)ft.dwHighDateTime << 32 | ft.dwLowDateTime) / 10);
		    }

            PerfCpuUsage result;
		    result.kernelTime = toMicroSeconds(kernelTime);
		    result.userTime = toMicroSeconds(userTime);
            return result;
	    }
        else version(Posix)
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

    version(profile)
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

    version(profile)
    static void profile(in string name, in Duration elapsedTime) @trusted
    in
    {
        assert(name.length != 0);
    }
    do
    {
        import pham.utl.utl_object : RAIIMutex;

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

    @property long elapsedTimeMsecs() const @nogc pure
    {
        return _elapsedTime.total!"msecs"();
    }

    @property double elapsedTimePercent() const @nogc pure
    {
        return _count != 0 ? cast(double)elapsedTimeUsecs / cast(double)_count * 100.0 : 0.0;
    }

    @property long elapsedTimeUsecs() const @nogc pure
    {
        return _elapsedTime.total!"usecs"();
    }

    @property string name() const @nogc pure
    {
        return _name;
    }

private:
    version(profile)
    static void saveProfile(string fileName) @trusted
    {
        import std.algorithm : sort;
        import std.format : format;
        import std.stdio : File;
        scope (failure) assert(0, "Assume nothrow failed");

        auto counterValues = counters.values;
        counterValues.sort!("a.elapsedTime > b.elapsedTime"); // Sort in descending order

        File file;
        file.open(fileName, "w");
        scope (exit)
            file.close();
        file.writeln("function,msecs,usecs,count,%");
        foreach (ref value; counterValues)
        {
            file.writeln(value.name,
                ",", format!"%,3?d"('_', value.elapsedTimeMsecs()),
                ",", format!"%,3?d"('_', value.elapsedTimeUsecs()),
                ",", format!"%,3?d"('_', value.count),
                ",", format!"%,3?.2f"('_', value.elapsedTimePercent()));
        }
    }

private:
    string _name;
    size_t _count;
    Duration _elapsedTime;
    version(profile)
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

    ref typeof(this) end() pure return
    {
        debug elapsedTime = MonoTime.currTime - startedTime;
        return this;
    }

    ref typeof(this) reset() pure return
    {
        count = 0;
        elapsedTime = Duration.zero;
        debug startedTime = MonoTime.currTime;
        return this;
    }

    @property long elapsedTimeMsecs() const pure
    {
        return elapsedTime.total!"msecs"();
    }

    @property long elapsedTimeUsecs() const pure
    {
        return elapsedTime.total!"usecs"();
    }
}

debug
{
    import std.ascii : LetterCase;
    import std.conv : to;
    import std.format : format;
    import std.traits : isSomeChar;

	ubyte[] dgReadAllBinary(string fileName) nothrow @trusted
    {
		import std.stdio;
		import std.file;

		try {
			auto f = File(fileName);
			f.seek(0, SEEK_END);
			auto size = cast(size_t)f.tell();
			f.seek(0, SEEK_SET);
			auto result = new ubyte[](size);
			f.rawRead(result);
			return result;
		}
		catch (Exception e) { debug dgWriteln("fileName=", fileName, ", e.msg=", e.msg); return null; }
    }

    ubyte[] dgFromHex(scope const(char)[] hexs) nothrow pure @safe
    {
        import pham.utl.utl_array_static : ShortStringBuffer;
        import pham.utl.utl_numeric_parser : NumericParsedKind, parseBase16;
        import pham.utl.utl_utf8 : NoDecodeInputRange;

        NoDecodeInputRange!(hexs, char) inputRange;
        ShortStringBuffer!ubyte result;
        if (parseBase16(result, inputRange) != NumericParsedKind.ok)
            return null;
        return result[].dup;
    }

    string dgToHex(ubyte n) nothrow pure @safe
    {
        try {
            return format!"%.2X"(n);
        } catch (Exception) { return null; }
    }

    string dgToHex(ushort n) nothrow pure @safe
    {
        try {
            return format!"%.4X"(n);
        } catch (Exception) { return null; }
    }

    string dgToHex(uint n) nothrow pure @safe
    {
        try {
            return format!"%.8X"(n);
        } catch (Exception) { return null; }
    }

    string dgToHex(ulong n) nothrow pure @safe
    {
        try {
            return format!"%.16X"(n);
        } catch (Exception) { return null; }
    }

    string dgToHex(scope const(ubyte)[] bytes) nothrow pure @safe
    {
        import pham.utl.utl_numeric_parser : cvtBytesBase16;

        return cvtBytesBase16(bytes, LetterCase.upper);
    }

    string dgToStr(bool b) @nogc nothrow pure @safe
    {
        return b ? "true" : "false";
    }

    string dgToStr(int n) nothrow pure @safe
    {
        try {
            return format!"%,3?d"('_', n);
        } catch (Exception) { return null; }
    }

    string dgToStr(uint n) nothrow pure @safe
    {
        try {
            return format!"%,3?d"('_', n);
        } catch (Exception) { return null; }
    }

    string dgToStr(long n) nothrow pure @safe
    {
        try {
            return format!"%,3?d"('_', n);
        } catch (Exception) { return null; }
    }

    string dgToStr(ulong n) nothrow pure @safe
    {
        try {
            return format!"%,3?d"('_', n);
        } catch (Exception) { return null; }
    }

    void dgWrite(A...)(A args) nothrow
    {
        import std.stdio : write;

        try {
            debug write(args);
        } catch (Exception) {}
    }

    void dgWritef(Char, A...)(in Char[] fmt, A args) nothrow
    if (isSomeChar!Char)
    {
        import std.stdio : writef;

        try {
            debug writef(fmt, args);
        } catch (Exception) {}
    }

    void dgWriteln(const(char)[] prefix, scope const(ubyte)[] bytes) nothrow
    {
        import pham.utl.utl_convert : bytesToHexs;

        try {
            debug dgWriteln(prefix, bytesToHexs(bytes));
        } catch (Exception) {}
    }

    void dgWriteln(A...)(A args) nothrow
    {
        import std.stdio : writeln;

        try {
            debug writeln(args);
        } catch (Exception) {}
    }

    void dgWritefln(Char, A...)(in Char[] fmt, A args) nothrow
    if (isSomeChar!Char)
    {
        import std.stdio : writefln;

        try {
            debug writefln(fmt, args);
        } catch (Exception) {}
    }
}

void traceFunction(Args...)(Args args,
    in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) @nogc nothrow pure @trusted
{
    version(TraceFunction)
    {
        debug traceLogger.trace!(Args)(args, line, fileName, funcName, moduleName);
    }
}

void traceFunction(
    in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) @nogc nothrow pure @trusted
{
    version(TraceFunction)
    {
        debug traceLogger.trace(LogLocation(line, fileName, funcName, moduleName));
    }
}

void traceUnitTest(Args...)(Args args,
    in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) @nogc nothrow pure @trusted
{
    version(TraceUnitTest)
    {
        debug traceLogger.trace!(Args)(args, line, fileName, funcName, moduleName);
    }
}

void traceUnitTest(
    in uint line = __LINE__, in string fileName = __FILE__, in string funcName = __FUNCTION__, in string moduleName = __MODULE__) @nogc nothrow pure @trusted
{
    version(TraceUnitTest)
    {
        debug traceLogger.trace(LogLocation(line, fileName, funcName, moduleName));
    }
}


private:

version(TraceLog) static __gshared FileLogger traceLogger;

shared static this() nothrow @trusted
{
    version(profile) PerfFunctionCounter.countersMutex = new Mutex();
    version(TraceLog)
    {
        traceLogger = new FileLogger("trace.log", FileLoggerOption(FileLoggerOption.overwriteMode),
            LoggerOption(LogLevel.trace, "unittestTrace", defaultOutputPattern, 10));
    }
}

shared static ~this() nothrow @trusted
{
    version(profile)
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

    version(TraceLog)
    {
        if (traceLogger !is null)
        {
            traceLogger.destroy();
            traceLogger = null;
        }
    }
}

unittest // PerfCpuUsage
{
    import core.time : dur;
    import core.thread.osthread : Thread;
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.utl.utltest.PerfCpuUsage");

    void delay() nothrow @trusted
    {
        Thread.sleep(dur!("msecs")(20));
    }

    delay();
    delay();
    const cpuTime = PerfCpuUsage.get();
    assert(cpuTime.kernelTime != Duration.max && cpuTime.kernelTime.total!"usecs"() >= 0);
    assert(cpuTime.userTime != Duration.max && cpuTime.userTime.total!"usecs"() > 0);
}
