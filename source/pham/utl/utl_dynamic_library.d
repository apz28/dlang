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

module pham.utl.utl_dynamic_library;

import std.format : format;
import std.typecons : Flag;
public import std.typecons : No, Yes;

import pham.utl.utl_result : getSystemErrorMessage, lastSystemError;
import pham.utl.utl_system : SafeHandle;
import pham.utl.utl_text : concateLineIf;

class DllException : Exception
{
    this(string message, string libName,
        Exception next = null, string file = __FILE__, size_t line = __LINE__) nothrow @safe
    {
        const lastErrorCode = lastSystemError();
        this(message, getSystemErrorMessage(lastErrorCode), lastErrorCode, libName, next, file, line);
    }

    this(string message, string lastErrorMessage, uint lastErrorCode, string libName,
        Exception next = null, string file = __FILE__, size_t line = __LINE__) nothrow @safe
    {
        this.errorCode = lastErrorCode;
        this.libName = libName;
        super(concateLineIf(message, lastErrorMessage), file, line, next);
    }

    string libName;
    uint errorCode;
}

version(Windows)
{
    import core.sys.windows.winbase;
    import core.sys.windows.windef;
    alias DllHandle = HMODULE;
    alias DllProc = FARPROC;
    alias LibHandle = SafeHandle!(HMODULE, FreeLibrary, null);
}
else version(Posix)
{
    import core.sys.posix.dlfcn;
    alias DllHandle = void*;
    alias DllProc = void*;
    alias LibHandle = SafeHandle!(void*, dlclose, null);
}

class DllLibrary
{
    import std.string : toStringz;

public:
    this(string libName) nothrow @safe
    {
        this._libName = libName;
    }

    ~this() @safe
    {
        unload();
    }

    /**
     * Load library if it is not loaded yet
     */
    final bool load(Flag!"throwIfError" throwIfError = Yes.throwIfError)() @safe
    {
        if (!isLoaded)
        {
            _libHandle = loadLib(_libName);

            static if (throwIfError)
            if (!isLoaded)
            {
                string err = format(DllMessage.eLoadLibrary, _libName);
                throw new DllException(err, _libName);
            }

            if (isLoaded)
                loaded();
        }
        return isLoaded;
    }

    /**
     * Load the function address using procName
     * Params:
     *  procName = Name of the function
     * Throws:
     *  DllException if loadProc fails if throwIfError is true
     * Returns:
     *  Pointer to the function
     *
     * Example:
     *  fct = loadProc("AFunctionNameToBeLoaded...")
     */
    final DllProc loadProc(Flag!"throwIfError" throwIfError = Yes.throwIfError)(string procName) @safe
    {
        DllProc res;
        if (isLoaded)
            res = loadProc(_libHandle.handle, procName);

        static if (throwIfError)
        {
            if (res is null)
            {
                if (!isLoaded)
                {
                    auto err = format(DllMessage.notLoadedLibrary, _libName);
                    throw new DllException(err, _libName);
                }
                else
                {
                    auto err = format(DllMessage.eLoadFunction, _libName, procName);
                    throw new DllException(err, _libName);
                }
            }
        }

        return res;
    }

    /**
     * Unload the library if it is loaded
     */
    final void unload() @safe
    {
        if (isLoaded)
        {
            _libHandle.dispose();
            unloaded();
        }
    }

    /**
     * Platform/OS specific load function
     */
    version(Windows)
    {
        static DllHandle loadLib(string libName) nothrow @trusted
        {
            auto libNamez = libName.toStringz();
            return LoadLibraryA(libNamez);
        }

        static DllProc loadProc(DllHandle libHandle, string procName) nothrow @trusted
        {
            auto procNamez = procName.toStringz();
            return GetProcAddress(libHandle, procNamez);
        }
    }
    else version(Posix)
    {
        static DllHandle loadLib(string libName) nothrow @trusted
        {
            auto libNamez = libName.toStringz();
            return dlopen(libNamez, RTLD_NOW);
        }

        static DllProc loadProc(DllHandle libHandle, string procName) nothrow @trusted
        {
            auto procNamez = procName.toStringz();
            return dlsym(libHandle, procNamez);
        }
    }
    else
    {
        static assert(0, "Unsupport system for " ~ __FUNCTION__);
    }

    /**
     * Returns true if library was loaded
     */
    @property final bool isLoaded() const nothrow @safe
    {
        return _libHandle.isValid;
    }

    /**
     * Returns native handle of the loaded library; otherwise null
     */
    @property final DllHandle libHandle() nothrow @safe
    {
        return _libHandle.handle;
    }

    /**
     * Name of the library
     */
    @property final string libName() const nothrow @safe
    {
        return _libName;
    }

protected:
    /**
     * Let the derived class to perform further action when library is loaded
     */
    void loaded() @safe
    {}

    /**
     * Let the derived class to perform further action when library is unloaded
     */
    void unloaded() @safe
    {}

private:
    string _libName;
    LibHandle _libHandle;
}

struct DllMessage
{
    static immutable eLoadFunction = "Unknown procedure name: %s.%s";
    static immutable eLoadLibrary = "Unable to load library: %s";
    static immutable eUnknownError = "Unknown error.";
    static immutable notLoadedLibrary = "Library is not loaded: %s";
}


private:

unittest // DllLibrary
{
    import std.exception : assertThrown;

    version(Windows)
    {
        // Use any library that is always installed
        auto lib = new DllLibrary("Ws2_32.dll");
        assert(lib.libName == "Ws2_32.dll");

        lib.load();
        assert(lib.isLoaded);
        assert(lib.libHandle !is null);

        assert(lib.loadProc("connect") !is null);

        assert(lib.loadProc!(No.throwIfError)("what_is_this_function") is null);
        assertThrown!DllException(lib.loadProc("what_is_this_function"));

        lib.unload();
        assert(!lib.isLoaded);
        assert(lib.libHandle is null);

        assert(lib.loadProc!(No.throwIfError)("connect") is null);
        assertThrown!DllException(lib.loadProc("connect"));

        auto unknownLib = new DllLibrary("what_is_this_function.dll");
        assertThrown!DllException(unknownLib.load());
    }
}
