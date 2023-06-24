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

module pham.io.stream;

public import core.time : Duration;
import core.time : msecs;

public import pham.io.type;
version (Posix)
    import pham.io.posix;
else version (Windows)
    import pham.io.windows;
else
    static assert(0, "Unsupport target");

@safe:

class Stream
{
@safe:

public:
    ~this() nothrow
    {
        close();
    }

    /**
     * Closes the current stream and releases any resources (such as sockets and file handles)
     * associated with the current stream
     */
    abstract StreamResult close() nothrow scope;

    /**
     * Reads the bytes from the current stream and writes them to another stream.
     * Both streams positions are advanced by the number of bytes copied.
     * Copying begins at the current position in the current stream, and does not
     * reset the position of the destination stream after the copy operation is complete
     * Params:
     *   destination = The stream to which the contents of the current stream will be copied
     * Returns:
     *   The number of bytes copied if success, a negative value if failed
     */
    final long copyTo(Stream destination) nothrow
    in
    {
        assert(destination !is null);
    }
    do
    {
        if (const r = checkUnsupported(canRead))
            return r;
        if (const r = destination.checkUnsupported(destination.canWrite))
        {
            lastError = destination.lastError;
            return r;
        }
        if (const r = checkActive())
            return r;
        if (const r = destination.checkActive())
        {
            lastError = destination.lastError;
            return r;
        }

        return copyToImpl(destination);
    }

    /**
     * When overridden in a derived class, clears all buffers for this stream and causes
     * any buffered data to be written to the underlying device
     */
    abstract StreamResult flush() nothrow;

    /**
     * Read a ubyte from stream.
     * Return -1 if failed
     */
    int readUByte() nothrow
    {
        ubyte[1] bytes;
        return read(bytes[]) == 1 ? bytes[0] : -1;
    }

    /**
     * When overridden in a derived class, reads a sequence of bytes from the current stream and
     * advances the position within the stream by the number of bytes read.
     * If the read operation is successful, the position within the stream advances by
     * the number of bytes read. If an exception occurs, the position within the stream
     * remains unchanged
     * Params:
     *   bytes = A region of memory. When this method returns, the contents of this region are
     *           replaced by the bytes read from the current source
     * Returns:
     *  The total number of bytes read into the buffer. This can be less than the number of
     *  bytes allocated in the buffer if that many bytes are not currently available,
     *  or zero (0) if the end of the stream has been reached
     */
    final long read(scope ubyte[] bytes) nothrow
    {
        if (const r = checkUnsupported(canRead))
            return r;
        if (const r = checkActive())
            return r;

        return bytes.length == 0 ? 0L : readImpl(bytes);
    }

    /**
     * When overridden in a derived class, sets the position within the current stream
     * Params:
     *   offset = A byte offset relative to the origin parameter
     *   origin = A value of type SeekOrigin indicating the reference point used to obtain the new position
     * Returns:
     *   The new position within the current stream
     */
    final long seek(long offset, SeekOrigin origin) nothrow
    {
        if (const r = checkUnsupported(canSeek))
            return r;
        if (const r = checkActive())
            return r;

        return seekImpl(offset, origin);
    }

    /**
     * When overridden in a derived class, sets the length of the current stream
     * Params:
     *   value = The desired length of the current stream in bytes
     * Returns:
     *   The length in bytes of the current stream
     */
    abstract long setLength(long value) nothrow;

    final long setPosition(long value) nothrow
    {
        return seek(value, SeekOrigin.begin);
    }

    /**
     * When overridden in a derived class, writes a sequence of bytes to the current stream
     * and advances the current position within this stream by the number of bytes written.
     * If the write operation is successful, the position within the stream advances by
     * the number of bytes written. If an exception occurs, the position within the stream
     * remains unchanged
     * Params:
     *   bytes = A region of memory. This method copies the contents of this region to
     *           the current stream
     * Returns:
     *  The total number of bytes written into the stream. This can be less than the number of
     *  bytes allocated in the buffer
     */
    final long write(scope const(ubyte)[] bytes) nothrow
    {
        if (const r = checkUnsupported(canWrite))
            return r;
        if (const r = checkActive())
            return r;

        return bytes.length == 0 ? 0L : writeImpl(bytes);
    }

    int writeUByte(ubyte byte_) nothrow
    {
        ubyte[1] bytes = byte_;
        return cast(int)write(bytes);
    }

    /**
     * When overridden in a derived class, gets a value indicating whether the current stream active/open state
     */
    @property abstract bool active() const @nogc nothrow;

    /**
     * When overridden in a derived class, gets a value indicating whether the current stream supports get/set length
     */
    @property abstract bool canLength() const @nogc nothrow;

    /**
     * When overridden in a derived class, gets a value indicating whether the current stream supports reading
     */
    @property abstract bool canRead() const @nogc nothrow;

    /**
     * When overridden in a derived class, gets a value indicating whether the current stream supports seeking
     */
    @property abstract bool canSeek() const @nogc nothrow;

    /**
     * Gets a value that determines whether the current stream can time out
     */
    @property abstract bool canTimeout() const @nogc nothrow;

    /**
     * When overridden in a derived class, gets a value indicating whether the current stream supports writing
     */
    @property abstract bool canWrite() const @nogc nothrow;

    /**
     * When overridden in a derived class, gets the length in bytes of the current stream
     */
    @property abstract long length() nothrow;

    /**
     * When overridden in a derived class, gets or sets the position within the current stream
     */
    @property long position() nothrow
    {
        if (const r = checkUnsupported(canSeek))
            return r;
        if (const r = checkActive())
            return r;

        return seekImpl(0, SeekOrigin.current);
    }

    /**
     * Gets or sets a duration value that determines how long the stream will attempt to read before timing out
     */
    @property final Duration readTimeout() nothrow
    {
        if (const r = checkUnsupported(canTimeout))
            return msecs(r);

        return readTimeoutImpl();
    }

    @property final Duration readTimeout(Duration value) nothrow
    {
        if (const r = checkUnsupported(canTimeout))
            return msecs(r);

        return readTimeoutImpl(value);
    }

    /**
     * Gets or sets a duration value that determines how long the stream will attempt to write before timing out
     */
    @property final Duration writeTimeout() nothrow
    {
        if (const r = checkUnsupported(canTimeout))
            return msecs(r);

        return writeTimeoutImpl();
    }

    @property final Duration writeTimeout(Duration value) nothrow
    {
        if (const r = checkUnsupported(canTimeout))
            return msecs(r);

        return writeTimeoutImpl(value);
    }

public:
    StreamError lastError;

package(pham.io):
    enum defaultBufferSize = 16_384;

    pragma(inline, true)
    final StreamResult checkActive(string funcName = __FUNCTION__, string file = __FILE__, size_t line = __LINE__) nothrow
    {
        return active
            ? lastError.reset()
            : lastError.setFailed(0, funcName, " with inactive stream", file, line);
    }

    pragma(inline, true)
    final StreamResult checkUnsupported(const(bool) can,
        string funcName = __FUNCTION__, string file = __FILE__, size_t line = __LINE__) nothrow
    {
        return can
            ? lastError.reset()
            : lastError.setUnsupported(0, null, funcName, file, line);
    }

protected:
    long copyToImpl(Stream destination) nothrow
    in
    {
        assert(destination !is null);
    }
    do
    {
        long result = 0;
        ubyte[defaultBufferSize] buffer;
        while (true)
        {
            const nr = readImpl(buffer[]);
            if (nr <= 0)
            {
                if (nr < 0)
                    return nr;
                break;
            }

            const nw = destination.writeImpl(buffer[0..cast(size_t)nr]);
            if (nw <= 0)
            {
                if (nw < 0)
                {
                    lastError = destination.lastError;
                    return nw;
                }
                break;
            }
            result += nw;
        }
        return result;
    }

    abstract long readImpl(scope ubyte[] bytes) nothrow;
    abstract long seekImpl(long offset, SeekOrigin origin) nothrow;
    abstract long writeImpl(scope const(ubyte)[] bytes) nothrow;

    Duration readTimeoutImpl() nothrow
    {
        assert(0, "Must overwrite");
    }

    Duration readTimeoutImpl(Duration value) nothrow
    {
        assert(0, "Must overwrite");
    }

    Duration writeTimeoutImpl() nothrow
    {
        assert(0, "Must overwrite");
    }

    Duration writeTimeoutImpl(Duration value) nothrow
    {
        assert(0, "Must overwrite");
    }

    final long lengthBySeek() nothrow
    {
        const curPosition = seekImpl(0, SeekOrigin.current);
        if (curPosition < 0)
            return curPosition;
        scope (exit)
            seekImpl(curPosition, SeekOrigin.begin);

        return seekImpl(0, SeekOrigin.end);
    }
}

class MemoryStream : Stream
{
@safe:

public:
    this(size_t capacity = 0u) nothrow
    {
        this._position = 0;
        this._data = null;
        if (capacity)
            this._data.reserve(capacity);
    }

    final MemoryStream clear() nothrow
    {
        _data = null;
        _position = 0;
        return this;
    }

    final override StreamResult close() nothrow scope
    {
        _data = null;
        _position = 0;
        return StreamResult.success;
    }

    /**
     * Returns `true` if the stream is at end
     */
    pragma(inline, true)
    bool eos() nothrow
    {
        return this._position >= this._data.length;
    }

    override StreamResult flush() nothrow
    {
        return StreamResult.success;
    }

    pragma(inline, true)
    final override int readUByte() nothrow
    {
        return _position >= _data.length ? -1 : _data[_position++];
    }

    final override long setLength(long value) nothrow
    {
        import std.conv : to;

        if (value > maxLength)
            return lastError.setFailed(0, " with over limit " ~ to!string(value));

        if (value <= 0)
            _data = null;
        else
            _data.length = cast(size_t)value;
        return cast(long)_data.length;
    }

    inout(ubyte)[] toUBytes() nothrow scope inout
    {
        return _data;
    }

    pragma(inline, true)
    final override int writeUByte(ubyte byte_) nothrow
    {
        import std.conv : to;

        const newPos = this._position + 1;
        if (newPos > maxLength)
            return lastError.setFailed(0, " with over limit " ~ to!string(newPos));

        if (this._data.length < newPos)
            this._data.length = newPos;
        this._data[this._position] = byte_;
        this._position = newPos;
        return 1;
    }

    pragma(inline, true)
    @property final override bool active() const @nogc nothrow
    {
        return true;
    }

    @property final override bool canLength() const @nogc nothrow
    {
        return true;
    }

    @property final override bool canRead() const @nogc nothrow
    {
        return true;
    }

    @property final override bool canSeek() const @nogc nothrow
    {
        return true;
    }

    @property final override bool canTimeout() const @nogc nothrow
    {
        return false;
    }

    @property final override bool canWrite() const @nogc nothrow
    {
        return true;
    }

    pragma(inline, true)
    @property final override long length() nothrow
    {
        return cast(long)_data.length;
    }

    pragma(inline, true)
    @property final override long position() nothrow
    {
        return cast(long)_position;
    }

    enum maxLength = (size_t.max / 3) * 2;

protected:
    final override long copyToImpl(Stream destination) nothrow
    in
    {
        assert(destination !is null);
    }
    do
    {
        if (_position >= _data.length)
            return 0;

        const r = destination.writeImpl(_data[_position..$]);
        if (r > 0)
            _position += r;
        else
            this.lastError = destination.lastError;
        return r;
    }

    final override long readImpl(scope ubyte[] bytes) nothrow
    {
        if (bytes.length == 0)
            return 0;

        const len = this._data.length;
        const remaining = cast(long)len - cast(long)this._position;

        if (remaining <= 0 || len == 0)
            return 0;

        if (remaining <= bytes.length)
        {
            bytes[0..cast(size_t)remaining] = this._data[this._position..cast(size_t)(this._position+remaining)];
            this._position = len;
            return remaining;
        }
        else
        {
            const blen = bytes.length;
            bytes[0..blen] = this._data[this._position..cast(size_t)(this._position+blen)];
            this._position += blen;
            return cast(long)blen;
        }
    }

    final override long seekImpl(long offset, SeekOrigin origin) nothrow
    {
        import std.conv : to;

        final switch (origin)
        {
            case SeekOrigin.begin:
                if (offset > maxLength)
                    return lastError.setFailed(0, " with over limit " ~ to!string(offset));
                this._position = offset <= 0 ? 0 : cast(size_t)offset;
                break;
            case SeekOrigin.current:
                // Optimize case
                if (offset == 0)
                    return cast(long)this._position;
                offset += this._position;
                goto case SeekOrigin.begin;
            case SeekOrigin.end:
                offset += this._data.length;
                goto case SeekOrigin.begin;
        }
        return cast(long)this._position;
    }

    final override long writeImpl(scope const(ubyte)[] bytes) nothrow
    {
        if (bytes.length == 0)
            return 0;

        size_t newPos = this._position + bytes.length;
        if (newPos > maxLength)
            newPos = maxLength;
        const wlen = cast(long)newPos - cast(long)this._position;
        if (wlen <= 0)
            return 0;

        if (this._data.length < newPos)
            this._data.length = newPos;
        this._data[this._position..cast(size_t)(this._position+wlen)] = bytes[0..cast(size_t)wlen];
        this._position = newPos;
        return wlen;
    }

private:
    ubyte[] _data;
    size_t _position;
}

class ReadonlyStream : Stream
{
@safe:

public:
    this(ubyte[] data) nothrow pure
    {
        this._position = 0;
        this._data = data;
    }

    final override StreamResult close() nothrow scope
    {
        _data = null;
        _position = 0;
        return StreamResult.success;
    }

    /**
     * Returns `true` if the stream is at end
     */
    pragma(inline, true)
    bool eos() nothrow
    {
        return this._position >= this._data.length;
    }

    override StreamResult flush() nothrow
    {
        return StreamResult.success;
    }

    final ReadonlyStream open(ubyte[] data) nothrow pure
    {
        this._position = 0;
        this._data = data;
        return this;
    }

    pragma(inline, true)
    final override int readUByte() nothrow
    {
        return _position >= _data.length ? -1 : _data[_position++];
    }

    final override long setLength(long value) nothrow
    {
        if (const r = checkUnsupported(false))
            return r;
        assert(0, "Unreach");
    }

    inout(ubyte)[] toUBytes() nothrow scope inout
    {
        return _data;
    }

    pragma(inline, true)
    @property final override bool active() const @nogc nothrow
    {
        return true;
    }

    @property final override bool canLength() const @nogc nothrow
    {
        return false;
    }

    @property final override bool canRead() const @nogc nothrow
    {
        return true;
    }

    @property final override bool canSeek() const @nogc nothrow
    {
        return true;
    }

    @property final override bool canTimeout() const @nogc nothrow
    {
        return false;
    }

    @property final override bool canWrite() const @nogc nothrow
    {
        return false;
    }

    pragma(inline, true)
    @property final override long length() nothrow
    {
        return cast(long)_data.length;
    }

    pragma(inline, true)
    @property final override long position() nothrow
    {
        return cast(long)_position;
    }

protected:
    final override long copyToImpl(Stream destination) nothrow
    in
    {
        assert(destination !is null);
    }
    do
    {
        if (_position >= _data.length)
            return 0;

        const r = destination.writeImpl(_data[_position..$]);
        if (r > 0)
            _position += r;
        else
            this.lastError = destination.lastError;
        return r;
    }

    final override long readImpl(scope ubyte[] bytes) nothrow
    {
        if (bytes.length == 0)
            return 0;

        const pos = this._position;
        const len = this._data.length;
        const remaining = cast(long)len - cast(long)pos;

        if (remaining <= 0 || len == 0)
            return 0;

        if (remaining <= bytes.length)
        {
            bytes[0..cast(size_t)remaining] = this._data[pos..cast(size_t)(pos+remaining)];
            this._position = len;
            return remaining;
        }
        else
        {
            const blen = bytes.length;
            bytes[0..blen] = this._data[pos..pos+blen];
            this._position += blen;
            return cast(long)blen;
        }
    }

    final override long seekImpl(long offset, SeekOrigin origin) nothrow
    {
        import std.conv : to;

        const len = this._data.length;
        final switch (origin)
        {
            case SeekOrigin.begin:
                this._position = offset <= 0 ? 0 : cast(size_t)(offset > len ? len : offset);
                break;
            case SeekOrigin.current:
                // Optimize case
                if (offset == 0)
                    return cast(long)this._position;
                offset += this._position;
                goto case SeekOrigin.begin;
            case SeekOrigin.end:
                offset += len;
                goto case SeekOrigin.begin;
        }
        return cast(long)this._position;
    }

    final override long writeImpl(scope const(ubyte)[] bytes) nothrow
    {
        if (const r = checkUnsupported(false))
            return r;
        assert(0, "Unreach");
    }

private:
    ubyte[] _data;
    size_t _position;
}

class HandleStream : Stream
{
@safe:

public:
    this(Handle handle, string name) nothrow pure
    {
        this._handle = handle;
        this._name = name;
    }

    pragma(inline, true)
    @property final override bool active() const @nogc nothrow
    {
        return _handle != invalidHandleValue;
    }

    pragma(inline, true)
    @property final Handle handle() @nogc nothrow pure
    {
        return _handle;
    }

    @property final string name() const nothrow pure
    {
        return this._name;
    }

private:
    string _name;
    Handle _handle = invalidHandleValue;
}

class FileHandleStream : HandleStream
{
@safe:

public:
    this(Handle handle, string name, StreamOpenMode openMode) nothrow pure
    {
        super(handle, name);
        this._openMode = openMode;
        this._position = 0;
    }

    final override StreamResult close() nothrow scope
    {
        if (_handle == invalidHandleValue)
            return StreamResult.success;

        scope (exit)
        {
            _handle = invalidHandleValue;
            _position = 0;
        }

        if (closeFile(_handle) == 0)
            return StreamResult.success;

        return lastError.setFailed(lastErrorNo());
    }

    pragma(inline, true)
    @property final override long position() nothrow
    {
        return _position;
    }

    pragma(inline, true)
    @property final StreamOpenMode openMode() const @nogc nothrow pure
    {
        return _openMode;
    }

protected:
    final override long readImpl(scope ubyte[] bytes) nothrow
    {
        size_t offset = 0;
        while (offset < bytes.length)
        {
            const remaining = bytes.length - offset;
            const rn = remaining >= int.max ? int.max : remaining;
            const rr = readFile(_handle, bytes[offset..offset+rn]);
            if (rr < 0)
                return lastError.setFailed(lastErrorNo());
            else if (rr == 0)
                break;
            offset += rr;
            this._position += rr;
        }
        return cast(long)offset;
    }

    final override long seekImpl(long offset, SeekOrigin origin) nothrow
    {
        if (offset == 0 && origin == SeekOrigin.current)
            return this._position;

        const result = seekFile(_handle, offset, origin);
        if (result < 0)
            return lastError.setFailed(lastErrorNo());

        this._position = result;
        return result;
    }

    final override long writeImpl(scope const(ubyte)[] bytes) nothrow
    {
        size_t offset = 0;
        while (offset < bytes.length)
        {
            const remaining = bytes.length - offset;
            const wn = remaining >= int.max ? int.max : remaining;
            const wr = writeFile(_handle, bytes[offset..offset+wn]);
            if (wr < 0)
                return lastError.setFailed(lastErrorNo());
            else if (wr == 0)
                break;
            offset += wr;
            this._position += wr;
        }
        return cast(long)offset;
    }

private:
    long _position;
    StreamOpenMode _openMode;
}

class FileStream : FileHandleStream
{
@safe:

public:
    this(Handle handle, string fileName, StreamOpenMode openMode) nothrow pure
    {
        super(handle, fileName, openMode);
    }

    this(string fileName, scope const(char)[] mode = "r") nothrow
    {
        StreamOpenInfo openInfo;
        auto parseResult = StreamOpenInfo.parseOpenMode(mode, openInfo);
        if (parseResult.isOK)
            this(fileName, openInfo);
        else
        {
            super(invalidHandleValue, fileName, openInfo.mode);
            this.lastError.set(0, "Failed open file-name: " ~ fileName ~ "\n" ~ parseResult.message);
        }
    }

    this(string fileName, scope const(StreamOpenInfo) openInfo) nothrow
    {
        auto h = openFile(fileName, openInfo);
        super(h, fileName, openInfo.mode);
        if (h == invalidHandleValue)
            this.lastError.set(lastErrorNo(), "Failed open file-name: " ~ fileName);
    }

    /**
     * Returns `true` if the file is at end
     */
    pragma(inline, true)
    bool eos() nothrow
    {
        return this.position >= this.length;
    }

    final override StreamResult flush() nothrow
    {
        if (const r = checkActive())
            return r;

        return flushFile(_handle) == 0
            ? StreamResult.success
            : lastError.setFailed(lastErrorNo());
    }

    final override long setLength(long value) nothrow
    {
        if (const r = checkActive())
            return r;

        const curPosition = seekFile(_handle, 0, SeekOrigin.current);
        if (curPosition < 0)
            return lastError.setFailed(lastErrorNo());

        if (seekFile(_handle, value, SeekOrigin.begin) < 0)
            return lastError.setFailed(lastErrorNo());
        scope (success)
            seekFile(handle, curPosition > value ? value : curPosition, SeekOrigin.begin);

        if (setLengthFile(_handle, value) < 0)
            return lastError.setFailed(lastErrorNo());

        return value;
    }

    @property final override bool canLength() const @nogc nothrow
    {
        return canWrite;
    }

    @property final override bool canRead() const @nogc nothrow
    {
        return active && (isOpenMode(openMode, StreamOpenMode.read) || isOpenMode(openMode, StreamOpenMode.readWrite));
    }

    @property final override bool canSeek() const @nogc nothrow
    {
        return active;
    }

    @property final override bool canTimeout() const @nogc nothrow
    {
        return false;
    }

    @property final override bool canWrite() const @nogc nothrow
    {
        return active && (isOpenMode(openMode, StreamOpenMode.write) || isOpenMode(openMode, StreamOpenMode.readWrite));
    }

    alias fileName = name;

    @property final override long length() nothrow
    {
        if (const r = checkActive())
            return r;

        const result = getLengthFile(_handle);
        return result >= 0 ? result : lastError.setFailed(lastErrorNo());
    }
}

class InputPipeStream : FileHandleStream
{
@safe:

public:
    this(Handle handle, string name) nothrow pure
    {
        super(handle, name, StreamOpenMode.readOnly);
    }

    final override StreamResult flush() nothrow
    {
        if (const r = checkUnsupported(false))
            return r;
        assert(0, "Unreach");
    }

    final override long setLength(long value) nothrow
    {
        if (const r = checkUnsupported(false))
            return r;
        assert(0, "Unreach");
    }

    @property final override bool canLength() const @nogc nothrow
    {
        return false;
    }

    @property final override bool canRead() const @nogc nothrow
    {
        return active;
    }

    @property final override bool canSeek() const @nogc nothrow
    {
        return false;
    }

    @property final override bool canTimeout() const @nogc nothrow
    {
        return false;
    }

    @property final override bool canWrite() const @nogc nothrow
    {
        return false;
    }

    @property final override long length() nothrow
    {
        return -1L;
    }
}

class OutputPipeStream : FileHandleStream
{
@safe:

public:
    this(Handle handle, string name) nothrow pure
    {
        super(handle, name, StreamOpenMode.writeOnly);
    }

    final override StreamResult flush() nothrow
    {
        if (const r = checkActive())
            return r;

        return flushFile(_handle) == 0
            ? StreamResult.success
            : lastError.setFailed(lastErrorNo());
    }

    final override long setLength(long value) nothrow
    {
        if (const r = checkUnsupported(false))
            return r;
        assert(0, "Unreach");
    }

    @property final override bool canLength() const @nogc nothrow
    {
        return false;
    }

    @property final override bool canRead() const @nogc nothrow
    {
        return false;
    }

    @property final override bool canSeek() const @nogc nothrow
    {
        return false;
    }

    @property final override bool canTimeout() const @nogc nothrow
    {
        return false;
    }

    @property final override bool canWrite() const @nogc nothrow
    {
        return active;
    }

    @property final override long length() nothrow
    {
        return -1L;
    }
}

StreamError createPipeStreams(const(bool) asInput, out InputPipeStream inputStream, out OutputPipeStream outputStream,
    uint bufferSize = 0) nothrow
{
    Handle inputHandle, outputHandle;
    const r = createFilePipes(asInput, inputHandle, outputHandle, bufferSize);
    if (r < 0)
    {
        inputStream = null;
        outputStream = null;
        return StreamError.failed(lastErrorNo());
    }
    else
    {
        inputStream = new InputPipeStream(inputHandle, "stdin" ~ (asInput ? "-in" : "-out"));
        outputStream = new OutputPipeStream(outputHandle, "stdout" ~ (asInput ? "-in" : "-out"));
        return StreamError.init;
    }
}

enum ChildInputOutputCloseAfter
{
    none = 0,
    failed = 1,
    zero = 2,
    positive = 4,
    any = failed | zero | positive,
}

struct ChildInputOutputStreams
{
@safe:

public:
    ~this() nothrow
    {
        closeAll();
    }

    void closeAll() nothrow scope
    {
        if (childInputRead !is null)
            childInputRead.close();

        if (childInputWrite !is null)
            childInputWrite.close();

        if (childOutputRead !is null)
            childOutputRead.close();

        if (childOutputWrite !is null)
            childOutputWrite.close();
    }

    void closeInput() nothrow
    {
        if (childInputRead !is null)
            childInputRead.close();

        if (childInputWrite !is null)
            childInputWrite.close();
    }

    void closeOutput() nothrow
    {
        if (childOutputRead !is null)
            childOutputRead.close();

        if (childOutputWrite !is null)
            childOutputWrite.close();
    }

    StreamError openAll() nothrow
    {
        auto r1 = createPipeStreams(true, childInputRead, childInputWrite);
        if (r1.isError)
            return r1;

        const r2 = createPipeStreams(false, childOutputRead, childOutputWrite);
        if (r2.isError)
        {
            childInputRead.close();
            childInputWrite.close();
            return r2;
        }
        return StreamError.init;
    }

    static bool canClose(long rwResult, ChildInputOutputCloseAfter closeAfter) @nogc nothrow pure
    {
        if (closeAfter == ChildInputOutputCloseAfter.any)
            return true;

        if (rwResult < 0 && (closeAfter & ChildInputOutputCloseAfter.failed) != 0)
            return true;

        if (rwResult == 0 && (closeAfter & ChildInputOutputCloseAfter.zero) != 0)
            return true;

        if (rwResult > 0 && (closeAfter & ChildInputOutputCloseAfter.positive) != 0)
            return true;

        return false;
    }

    long read(scope ubyte[] bytes, ChildInputOutputCloseAfter closeAfter) nothrow
    {
        assert(childOutputRead !is null);
        assert(childOutputRead.active);

        const result = childOutputRead.read(bytes);
        if (canClose(result, closeAfter))
            childOutputRead.close();
        return result;
    }

    long write(scope const(ubyte)[] bytes, ChildInputOutputCloseAfter closeAfter) nothrow
    {
        assert(childInputWrite !is null);
        assert(childInputWrite.active);

        const result = childInputWrite.write(bytes);
        if (canClose(result, closeAfter))
            childInputWrite.close();
        return result;
    }

public:
   InputPipeStream childInputRead, childOutputRead;
   OutputPipeStream childInputWrite, childOutputWrite;
}

unittest // MemoryStream
{
    ubyte[200] bufWrite = 75;
    ubyte[200] bufRead;

    // Write only
    {
        auto f = new MemoryStream();
        assert(f.active);
        assert(f.canLength);
        assert(f.canSeek);
        assert(!f.canTimeout);
        assert(f.canRead);
        assert(f.canWrite);
        assert(f.position == 0);
        assert(f.write(bufWrite[]) == bufWrite.length);
        assert(f.length == bufWrite.length);
        assert(f.position == bufWrite.length);
    }

    // Write & Read
    {
        auto f = new MemoryStream();
        assert(f.active);
        assert(f.canLength);
        assert(f.canSeek);
        assert(!f.canTimeout);
        assert(f.canRead);
        assert(f.canWrite);
        assert(f.position == 0);
        assert(f.write(bufWrite[]) == bufWrite.length);
        assert(f.length == bufWrite.length);
        assert(f.position == bufWrite.length);
        f.setPosition(0);
        bufRead[] = 0; // Make sure it not contain previous info
        assert(f.read(bufRead[]) == bufWrite.length);
        assert(bufRead == bufWrite);
        assert(f.position == bufWrite.length);
    }

    // Write & Read half
    {
        auto f = new MemoryStream(bufWrite.length);
        assert(f.active);
        assert(f.canLength);
        assert(f.canSeek);
        assert(!f.canTimeout);
        assert(f.canRead);
        assert(f.canWrite);
        assert(f.position == 0);
        assert(f.write(bufWrite[]) == bufWrite.length);
        assert(f.length == bufWrite.length);
        assert(f.position == bufWrite.length);
        bufRead[] = 0; // Make sure it not contain previous info
        const halfLen = bufWrite.length / 2;
        f.setPosition(halfLen);
        assert(f.read(bufRead[]) == halfLen);
        assert(bufRead[0..halfLen] == bufWrite[halfLen..bufWrite.length]);
        assert(f.position == bufWrite.length);
    }
}

unittest // ReadonlyStream
{
    ubyte[] bufWrite = new ubyte[200];
    bufWrite[] = 75;
    ubyte[200] bufRead;

    // Read all
    {
        auto f = new ReadonlyStream(bufWrite[]);
        assert(f.active);
        assert(!f.canLength);
        assert(f.canSeek);
        assert(!f.canTimeout);
        assert(f.canRead);
        assert(!f.canWrite);
        assert(f.position == 0);
        assert(f.length == bufWrite.length);
        bufRead[] = 0; // Make sure it not contain previous info
        assert(f.read(bufRead[]) == bufWrite.length);
        assert(bufRead == bufWrite);
        assert(f.position == bufWrite.length);
    }

    // Read half
    {
        auto f = new ReadonlyStream(bufWrite[]);
        assert(f.active);
        assert(!f.canLength);
        assert(f.canSeek);
        assert(!f.canTimeout);
        assert(f.canRead);
        assert(!f.canWrite);
        assert(f.position == 0);
        assert(f.length == bufWrite.length);
        bufRead[] = 0; // Make sure it not contain previous info
        const halfLen = bufWrite.length / 2;
        f.setPosition(halfLen);
        assert(f.read(bufRead[]) == halfLen);
        assert(bufRead[0..halfLen] == bufWrite[halfLen..bufWrite.length]);
        assert(f.position == bufWrite.length);
    }
}

unittest // FileStream
{
    ubyte[200] bufWrite = 42;
    ubyte[200] bufRead;

    // Write only
    {
        auto f = new FileStream("TestFileStream.txt", "wt");
        scope (exit)
        {
            f.close();
            removeFile("TestFileStream.txt");
        }
        assert(f.active);
        assert(f.canLength);
        assert(f.canSeek);
        assert(!f.canTimeout);
        assert(f.canRead);
        assert(f.canWrite);
        assert(f.position == 0);
        assert(f.write(bufWrite[]) == bufWrite.length);
        assert(f.position == bufWrite.length);
    }

    // Write & Read
    {
        auto f = new FileStream("TestFileStream.txt", "w+t");
        scope (exit)
        {
            f.close();
            removeFile("TestFileStream.txt");
        }
        assert(f.active);
        assert(f.canLength);
        assert(f.canSeek);
        assert(!f.canTimeout);
        assert(f.canRead);
        assert(f.canWrite);
        assert(f.position == 0);
        assert(f.write(bufWrite[]) == bufWrite.length);
        assert(f.position == bufWrite.length);
        assert(f.length == bufWrite.length);
        f.setPosition(0);
        bufRead[] = 0; // Make sure it not contain previous info
        assert(f.read(bufRead[]) == bufWrite.length);
        assert(bufRead == bufWrite);
        assert(f.position == bufWrite.length);
    }

    // Write & Read half
    {
        auto f = new FileStream("TestFileStream.txt", "w+t");
        scope (exit)
        {
            f.close();
            removeFile("TestFileStream.txt");
        }
        assert(f.active);
        assert(f.canLength);
        assert(f.canSeek);
        assert(!f.canTimeout);
        assert(f.canRead);
        assert(f.canWrite);
        assert(f.position == 0);
        assert(f.write(bufWrite[]) == bufWrite.length);
        assert(f.position == bufWrite.length);
        assert(f.length == bufWrite.length);
        bufRead[] = 0; // Make sure it not contain previous info
        const halfLen = bufWrite.length / 2;
        f.setPosition(halfLen);
        assert(f.read(bufRead[]) == halfLen);
        assert(bufRead[0..halfLen] == bufWrite[halfLen..bufWrite.length]);
        assert(f.position == bufWrite.length);
    }
}

unittest // ChildInputOutputStreams
{
    ChildInputOutputStreams childStreams;
    const r = childStreams.openAll();
    scope (exit)
        childStreams.closeAll();
    assert(r.isOK);
}
