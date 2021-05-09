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

module pham.utl.utltest;

import core.time;

nothrow @safe:

struct PerfTestResult
{
nothrow @safe:

    size_t count;
    Duration elapsedTime;
    MonoTime startedTime;

    static typeof(this) init()
    {
        typeof(this) result;
        result.reset();
        return result;
    }

    void mark()
    {
        elapsedTime = MonoTime.currTime - startedTime;
    }

    void reset()
    {
        count = 0;
        elapsedTime = Duration.zero;
        startedTime = MonoTime.currTime;
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
        import pham.utl.utlobject : bytesToHexs;

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
        import pham.utl.utlobject : bytesToHexs;

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

version (TraceInvalidMemoryOp)
shared static this()
{
    import pham.utl.utltest;
    dgWriteln("utl.utltest.shared static this()");

    import core.exception;
    assertHandler(null);
}
