/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2023 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.io.type;

import std.system : Endian;
version (Posix)
{
    import core.sys.posix.fcntl;
    import core.stdc.stdio : SEEK_SET, SEEK_CUR, SEEK_END;

    import pham.io.posix : getSystemErrorMessage;
}
else version (Windows)
{
    import core.stdc.stdio : O_RDONLY, O_WRONLY, O_RDWR, O_APPEND, O_CREAT, O_TRUNC, O_BINARY,
        O_TMPFILE=O_TEMPORARY;
    import core.sys.windows.winbase : CREATE_ALWAYS, OPEN_ALWAYS, OPEN_EXISTING, TRUNCATE_EXISTING,
        FILE_FLAG_DELETE_ON_CLOSE;
    import core.sys.windows.winbase : SEEK_SET=FILE_BEGIN, SEEK_CUR=FILE_CURRENT, SEEK_END=FILE_END;
    import core.sys.windows.windef : DWORD;
    import core.sys.windows.winnt : FILE_ATTRIBUTE_NORMAL, FILE_ATTRIBUTE_TEMPORARY,
        FILE_SHARE_READ, FILE_SHARE_WRITE, FILE_GENERIC_WRITE, FILE_WRITE_DATA, GENERIC_READ, GENERIC_WRITE;

    import pham.io.windows : getSystemErrorMessage;
}

@safe:

enum StreamOpenMode : int
{
    read = O_RDONLY, /// open for reading only
    write = O_WRONLY, /// open for writing only
    readWrite = O_RDWR, /// open for reading and writing
    append = O_APPEND, /// open in append mode
    create = O_CREAT, /// create file if missing
    truncate = O_TRUNC, /// truncate existing file
    binary = O_BINARY, /// open in binary mode - b
    temporary = O_TMPFILE, /// file is temporary - t
    
    readOnly = read, /// r
    readPlus = readWrite, /// r+
    writeOnly = write | create | truncate, /// w
    writePlus = readWrite | create | truncate, /// w+
    appendOnly = append | create | write, /// a
    appendPlus = append | create | readWrite, /// a+
}

enum SeekOrigin : int
{
    begin = SEEK_SET, /// Offset is relative to the beginning
    current = SEEK_CUR, /// Offset is relative to the current position
    end = SEEK_END, /// Offset is relative to the end
}

enum StreamResult : int
{
    success = 0,
    failed = -1,
    unsupported = -2,
}

enum ValueKind : ubyte
{
    nil = 0, // null
    boolean = 1,
    int8 = 2,
    uint8 = 3,
    int16 = 4,
    uint16 = 5,
    int32 = 6,
    uint32 = 7,
    int64 = 8,
    uint64 = 9,
    // gap reserved for integer type
    intn = 15, // unlimit integer
    float32 = 16,
    float64 = 17,
    // gap reserved for float type
    floatn = 25, // unlimit float
    decimal16 = 26,
    decimal32 = 27,
    decimal64 = 28,
    decimal128 = 29,
    // gap reserved for decimal type
    decimaln = 35, // unlimit decimal
    date = 36,
    datetime = 37,
    datetimez = 38, // datetime with zone info
    time = 39,
    timez = 40, // time with zone info
    // gap reserved for date/time type
    uuid = 46, // guid
    // gap reserved for guid type
    character = 51, // char
    // gap reserved for character type  
    charactern = 56, // fixed length characters
    characters = 57, // unlimit characters - string
    // gap reserved for characters type    
    binaryn = 66, // fixed length ubytes
    binarys = 67, // unlimit ubytes
    // gap reserved for ubytes type    
    enumeration = 76,
    set = 77,
    json = 80,
    jsonb = 81,
    xml = 82,
    composite = 100, // struct, object
    array = 127,
    unknown = 255 // last value
}

union BytesOfFloat
{
    uint i;
    float f;
    ubyte[uint.sizeof] b;
}

union BytesOfDouble
{
    ulong i;
    double f;
    ubyte[ulong.sizeof] b;
}

// i=1 ~ b=[1,0,0,0]
union BytesOfInt
{
    int i;
    ubyte[int.sizeof] b;
}

struct StreamOpenInfo
{
@safe:

public:
    /**
     * Convert `fopen` string modes to `StreamOpenMode` enum values.
     * The mode `mode` can be one of the following strings.
     *   "r" = open for reading
     *   "r+"`, open for reading)
     *   "w"`, create or truncate and open for writing)
     *   "w+"`, create or truncate and open for reading and writing)
     *   "a"`, create or truncate and open for appending)
     *   "a+"`, create or truncate and open for reading and appending)
     *
     * The mode string can be followed by a `"b"` flag to open files in
     * binary mode. This only has an effect on Posix.
     *
     * The mode string can be followed by a `"t"` flag to open files in
     * temporary mode. This can only be used with "w" mode.
     *
     * Params:
     *   mode = fopen mode to convert to `StreamOpenMode` enum
     *   info = info.mode will contain the converted `StreamOpenMode` enum
     * Returns:
     *   StreamError with success or error with appropriate info
     */
    static StreamError parseOpenMode(scope const(char)[] mode, out StreamOpenInfo info) nothrow
    {
        enum OkMode { notSet, invalid, valid }

        info.reset();
        OkMode ok = OkMode.notSet;
        char lastModeChar = '\0';
        foreach (i; 0..mode.length)
        {
            switch (mode[i])
            {
                case 'r':
                    // Already set?
                    ok = ok == OkMode.valid ? OkMode.invalid : OkMode.valid;

                    info.mode = StreamOpenMode.readOnly;
                    lastModeChar = 'r';
                    break;
                case 'w':
                    // Already set?
                    ok = ok == OkMode.valid ? OkMode.invalid : OkMode.valid;

                    info.mode = StreamOpenMode.writeOnly;
                    lastModeChar = 'w';
                    break;
                case 'a':
                    // Already set?
                    ok = ok == OkMode.valid ? OkMode.invalid : OkMode.valid;

                    info.mode = StreamOpenMode.appendOnly;
                    lastModeChar = 'a';
                    break;
                case '+':
                    // Out of sequence?
                    if (ok == OkMode.notSet)
                        ok = OkMode.invalid;

                    switch (lastModeChar)
                    {
                        case 'r':
                            info.mode = StreamOpenMode.readPlus;
                            break;
                        case 'w':
                            info.mode = StreamOpenMode.writePlus;
                            break;
                        case 'a':
                            info.mode = StreamOpenMode.appendPlus;
                            break;
                        default:
                            break;
                    }
                    break;
                case 'b':
                    // Out of sequence?
                    if (ok == OkMode.notSet)
                        ok = OkMode.invalid;

                    info.mode |= StreamOpenMode.binary;
                    break;
                case 't':
                    // Out of sequence?
                    if (ok == OkMode.notSet)
                        ok = OkMode.invalid;

                    // Conflict (Only for w or w+)?
                    if ((info.mode & StreamOpenMode.writeOnly) != StreamOpenMode.writeOnly
                        && (info.mode & StreamOpenMode.writePlus) != StreamOpenMode.writePlus)
                        ok = OkMode.invalid;

                    info.mode |= StreamOpenMode.temporary;
                    break;
                default:
                    ok = OkMode.invalid;
                    break;
            }

            if (ok == OkMode.invalid)
                break;
        }

        return ok == OkMode.valid ? StreamError(0, null) : StreamError(0, "Invalid file-stream open mode: " ~ mode.idup);
    }

    version (Windows)
    DWORD toCreationDisposition() const nothrow
    {
        switch (mode & (StreamOpenMode.create | StreamOpenMode.truncate))
        {
            case cast(StreamOpenMode)0:
                return OPEN_EXISTING;
            case StreamOpenMode.create:
                return OPEN_ALWAYS;
            case StreamOpenMode.truncate:
                return TRUNCATE_EXISTING;
            case StreamOpenMode.create | StreamOpenMode.truncate:
                return CREATE_ALWAYS;
            default:
                return OPEN_EXISTING;
        }
    }

    version (Windows)
    DWORD toDesiredAccess() const nothrow
    {
        switch (mode & (StreamOpenMode.read | StreamOpenMode.write | StreamOpenMode.readWrite | StreamOpenMode.append))
        {
            case StreamOpenMode.read:
                return GENERIC_READ;
            case StreamOpenMode.write:
                return GENERIC_WRITE;
            case StreamOpenMode.readWrite:
                return GENERIC_READ | GENERIC_WRITE;
            case StreamOpenMode.write | StreamOpenMode.append:
                return FILE_GENERIC_WRITE & ~FILE_WRITE_DATA;
            case StreamOpenMode.readWrite | StreamOpenMode.append:
                return GENERIC_READ | (FILE_GENERIC_WRITE & ~FILE_WRITE_DATA);
            default:
                return GENERIC_READ;
        }
    }

    version (Windows)
    DWORD toFlagsAndAttributes() const nothrow
    {
        return (mode & StreamOpenMode.temporary) == StreamOpenMode.temporary
            ? FILE_ATTRIBUTE_NORMAL | FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE
            : FILE_ATTRIBUTE_NORMAL;
    }

    version (Windows)
    DWORD toShareMode() const nothrow
    {
        return flag;
    }

    void reset() nothrow
    {
        mode = StreamOpenMode.init;
        flag = initFlag();
    }

public:
    StreamOpenMode mode;
    int flag = initFlag();

private:
    static int initFlag() nothrow pure
    {
        version (Posix)
            return S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH;
        else version (Windows)
            return FILE_SHARE_READ;
        else
            return 0;
    }
}

struct StreamError
{
@safe:

public:
    this(int errorNo, string message,
        string file = __FILE__, size_t line = __LINE__) nothrow pure
    {
        this.errorNo = errorNo;
        this.message = message;
        this.file = file;
        this.line = line;
    }

    bool opCast(C: bool)() const @nogc nothrow pure
    {
        return isOK;
    }

    static StreamError failed(int errorNo, string postfixMessage = null,
        string funcName = __FUNCTION__, string file = __FILE__, size_t line = __LINE__) nothrow
    {
        StreamError result;
        result.setFailed(errorNo, postfixMessage, funcName, file, line);
        return result;
    }

    pragma(inline, true)
    StreamResult reset() nothrow
    {
        this.errorNo = 0;
        this.message = null;
        this.file = null;
        this.line = 0;
        return StreamResult.success;
    }

    StreamResult set(int errorNo, string message, StreamResult result = StreamResult.failed,
        string file = __FILE__, size_t line = __LINE__) nothrow
    {
        this.errorNo = errorNo;
        this.message = message;
        this.file = file;
        this.line = line;
        return result;
    }

    StreamResult setFailed(int errorNo, string postfixMessage = null,
        string funcName = __FUNCTION__, string file = __FILE__, size_t line = __LINE__) nothrow
    {
        this.errorNo = errorNo;
        this.message = "Failed " ~ funcName ~ postfixMessage;
        this.file = file;
        this.line = line;
        const sysErrorMessage = errorNo != 0 ? getSystemErrorMessage(errorNo) : null;
        if (sysErrorMessage.length)
            this.message ~= "\n" ~ sysErrorMessage;
        return StreamResult.failed;
    }

    StreamResult setUnsupported(int errorNo, string postfixMessage = null,
        string funcName = __FUNCTION__, string file = __FILE__, size_t line = __LINE__) nothrow
    {
        this.errorNo = errorNo;
        this.message = "Unsupported " ~ funcName ~ postfixMessage;
        this.file = file;
        this.line = line;
        return StreamResult.unsupported;
    }

    pragma(inline, true)
    void throwIf(E : StreamException = StreamException)()
    {
        if (errorNo != 0 || message.length != 0)
            throwIt!E();
    }

    void throwIt(E : StreamException = StreamException)()
    {
        throw new E(errorNo, message, file, line);
    }

    /**
     * Returns true if there is error-code or error-message
     */
    pragma(inline, true)
    @property bool isError() const @nogc nothrow pure
    {
        return errorNo != 0 || message.length != 0;
    }

    /**
     * Returns true if there is no error-code and error-message
     */
    pragma(inline, true)
    @property bool isOK() const @nogc nothrow pure
    {
        return errorNo == 0 && message.length == 0;
    }

public:
    string file;
    string message;
    size_t line;
    int errorNo;
}

class StreamException : Exception
{
@safe:

public:
    this(int errorNo, string message,
        string file = __FILE__, size_t line = __LINE__, Throwable next = null) nothrow pure
    {
        super(message, file, line, next);
        this.errorNo = errorNo;
    }

    override string toString() nothrow @trusted
    {
        import std.format : format;
        scope (failure) assert(0, "Assume nothrow failed");

        auto result = super.toString();
        if (errorNo != 0)
            result ~= "\nError code: " ~ format!"0x%.8d [%d]"(errorNo, errorNo);

        auto e = next;
        while (e !is null)
        {
            result ~= "\n\n" ~ e.toString();
            e = e.next;
        }

        return result;
    }

public:
    const(int) errorNo;
}

class StreamReadException : StreamException
{
@safe:

public:
    this(int errorNo, string message,
        string file = __FILE__, size_t line = __LINE__, Throwable next = null) nothrow pure
    {
        super(errorNo, message, file, line, next);
    }
}

class StreamWriteException : StreamException
{
@safe:

public:
    this(int errorNo, string message,
        string file = __FILE__, size_t line = __LINE__, Throwable next = null) nothrow pure
    {
        super(errorNo, message, file, line, next);
    }
}

pragma(inline, true)
bool isOpenMode(const(StreamOpenMode) modes, const(StreamOpenMode) checkMode) @nogc nothrow pure
{
    return (modes & checkMode) == checkMode;
}

pragma(inline, true)
bool isSameRTEndian(const(Endian) endian) @nogc nothrow pure
{
    version (LittleEndian)
        return endian == Endian.littleEndian;
    else
        return endian == Endian.bigEndian;
}

unittest // StreamOpenInfo.parseOpenMode
{
    StreamOpenInfo info;
    assert(StreamOpenInfo.parseOpenMode("r", info).isOK());
    assert(info.mode == StreamOpenMode.read);
    assert(StreamOpenInfo.parseOpenMode("r+", info).isOK());
    assert(info.mode == StreamOpenMode.readWrite);
    assert(StreamOpenInfo.parseOpenMode("rb", info).isOK());
    assert(info.mode == (StreamOpenMode.read | StreamOpenMode.binary));
    assert(StreamOpenInfo.parseOpenMode("r+b", info).isOK());
    assert(info.mode == (StreamOpenMode.readWrite | StreamOpenMode.binary));

    assert(StreamOpenInfo.parseOpenMode("rw", info).isError());
    assert(StreamOpenInfo.parseOpenMode("ra", info).isError());
    assert(StreamOpenInfo.parseOpenMode("rt", info).isError());
    assert(StreamOpenInfo.parseOpenMode("r+t", info).isError());
    assert(StreamOpenInfo.parseOpenMode("rbt", info).isError());
    assert(StreamOpenInfo.parseOpenMode("r+bt", info).isError());

    assert(StreamOpenInfo.parseOpenMode("w", info).isOK());
    assert(info.mode == (StreamOpenMode.create | StreamOpenMode.truncate | StreamOpenMode.write));
    assert(StreamOpenInfo.parseOpenMode("wt", info).isOK());
    assert(info.mode == (StreamOpenMode.create | StreamOpenMode.truncate | StreamOpenMode.write | StreamOpenMode.temporary));
    assert(StreamOpenInfo.parseOpenMode("w+", info).isOK());
    assert(info.mode == (StreamOpenMode.create | StreamOpenMode.truncate | StreamOpenMode.readWrite));
    assert(StreamOpenInfo.parseOpenMode("w+t", info).isOK());
    assert(info.mode == (StreamOpenMode.create | StreamOpenMode.truncate | StreamOpenMode.readWrite | StreamOpenMode.temporary));
    assert(StreamOpenInfo.parseOpenMode("wb", info).isOK());
    assert(info.mode == (StreamOpenMode.create | StreamOpenMode.truncate | StreamOpenMode.write | StreamOpenMode.binary));
    assert(StreamOpenInfo.parseOpenMode("wbt", info).isOK());
    assert(info.mode == (StreamOpenMode.create | StreamOpenMode.truncate | StreamOpenMode.write | StreamOpenMode.binary | StreamOpenMode.temporary));
    assert(StreamOpenInfo.parseOpenMode("w+b", info).isOK());
    assert(info.mode == (StreamOpenMode.create | StreamOpenMode.truncate | StreamOpenMode.readWrite | StreamOpenMode.binary));
    assert(StreamOpenInfo.parseOpenMode("w+bt", info).isOK());
    assert(info.mode == (StreamOpenMode.create | StreamOpenMode.truncate | StreamOpenMode.readWrite | StreamOpenMode.binary | StreamOpenMode.temporary));

    assert(StreamOpenInfo.parseOpenMode("wr", info).isError());
    assert(StreamOpenInfo.parseOpenMode("wa", info).isError());

    assert(StreamOpenInfo.parseOpenMode("a", info).isOK());
    assert(info.mode == (StreamOpenMode.create | StreamOpenMode.write | StreamOpenMode.append));
    assert(StreamOpenInfo.parseOpenMode("a+", info).isOK());
    assert(info.mode == (StreamOpenMode.create | StreamOpenMode.readWrite | StreamOpenMode.append));
    assert(StreamOpenInfo.parseOpenMode("ab", info).isOK());
    assert(info.mode == (StreamOpenMode.create | StreamOpenMode.write | StreamOpenMode.append | StreamOpenMode.binary));
    assert(StreamOpenInfo.parseOpenMode("a+b", info).isOK());
    assert(info.mode == (StreamOpenMode.create | StreamOpenMode.readWrite | StreamOpenMode.append | StreamOpenMode.binary));

    assert(StreamOpenInfo.parseOpenMode("ar", info).isError());
    assert(StreamOpenInfo.parseOpenMode("aw", info).isError());
    assert(StreamOpenInfo.parseOpenMode("at", info).isError());
    assert(StreamOpenInfo.parseOpenMode("a+t", info).isError());
    assert(StreamOpenInfo.parseOpenMode("abt", info).isError());
    assert(StreamOpenInfo.parseOpenMode("a+bt", info).isError());

    assert(!StreamOpenInfo.parseOpenMode("xyz", info).isOK());
    assert(StreamOpenInfo.parseOpenMode("xyz", info).isError());
}
