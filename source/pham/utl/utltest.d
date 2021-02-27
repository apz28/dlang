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

nothrow @safe:

version (unittest)
{
    import std.traits : isSomeChar;

    void dgFunctionTrace(A...)(A args,
        int line = __LINE__,
        string functionName = __FUNCTION__)
    {
        scope (failure) assert(0);

        dgWrite(functionName, "(", line, ")");
        if (args.length)
        {
            dgWrite(": ");
            dgWriteln(args);
        }
        else
            dgWriteln("");
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
			dgWriteln("fileName=", fileName, ", e.msg=", e.msg);
			return null;
        }
    }

    string dgToString(size_t n) nothrow pure
    {
        import std.conv : to;

        return to!string(n);
    }

    string dgToString(long n) nothrow pure
    {
        import std.conv : to;

        return to!string(n);
    }

    string dgToString(scope const(ubyte)[] b) nothrow pure
    {
        import pham.utl.utlobject : bytesToHexs;

        return bytesToHexs(b);
    }

    void dgWrite(A...)(A args)
    {
        import std.stdio : write;

        scope (failure) assert(0);

        debug write(args);
    }

    void dgWritef(Char, A...)(in Char[] fmt, A args)
    if (isSomeChar!Char)
    {
        import std.stdio : writef;

        scope (failure) assert(0);

        debug writef(fmt, args);
    }

    void dgWriteln(A...)(A args)
    {
        import std.stdio : writeln;

        scope (failure) assert(0);

        debug writeln(args);
    }

    void dgWriteln(const(char)[] prefix, scope const(ubyte)[] bytes)
    {
        import pham.utl.utlobject : bytesToHexs;

        debug dgWriteln(prefix, bytesToHexs(bytes));
    }

    void dgWritefln(Char, A...)(in Char[] fmt, A args)
    if (isSomeChar!Char)
    {
        import std.stdio : writefln;

        scope (failure) assert(0);

        debug writefln(fmt, args);
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
