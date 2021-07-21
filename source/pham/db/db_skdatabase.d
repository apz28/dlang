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

module pham.db.skdatabase;

import std.exception : assumeWontThrow;
import std.format : format;
import std.socket : socket_t, Address, AddressFamily, InternetAddress, lastSocketError, Socket, SocketOption, SocketOptionLevel, SocketType;
import std.system : Endian;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
version (TraceFunction) import pham.utl.object : bytesToHexs;
import pham.db.object;
import pham.db.message;
import pham.db.exception;
import pham.db.util;
import pham.db.type;
import pham.db.buffer;
import pham.db.buffer_filter;
import pham.db.buffer_filter_cipher;
import pham.db.value;
import pham.db.database;

immutable string[string] skDefaultParameterValues;

class SkCommand : DbCommand
{
public:
    this(SkConnection connection, string name = null) nothrow @safe
    {
        super(connection, name);
    }

    this(SkConnection connection, DbTransaction transaction, string name = null) nothrow @safe
    {
        super(connection, transaction, name);
    }

    final override DbRowValue fetch(bool isScalar) @safe
    {
        version (TraceFunction) dgFunctionTrace();
        version (profile) debug auto p = PerfFunction.create();

        checkActive();

		if (isStoredProcedure)
            return fetchedRows ? fetchedRows.dequeue() : DbRowValue(0);

        if (fetchedRows.empty && !allRowsFetched && isSelectCommandType())
            doFetch(isScalar);

        return fetchedRows ? fetchedRows.dequeue() : DbRowValue(0);
    }

protected:
    override void prepareExecute(DbCommandExecuteType type) @safe
    {
        super.prepareExecute(type);
        fetchedRows.clear();
    }

    abstract void doFetch(bool isScalar) @safe;

protected:
	DbRowValueQueue fetchedRows;
}

abstract class SkConnection : DbConnection
{
public:
    this(DbDatabase database) nothrow @safe
    {
        super(database);
    }

    this(DbDatabase database, string connectionString) nothrow @safe
    {
        super(database, connectionString);
    }

    this(DbDatabase database, SkConnectionStringBuilder connectionStringBuilder) nothrow @safe
    in
    {
        assert(connectionStringBuilder !is null);
        assert(connectionStringBuilder.scheme == scheme);
    }
    do
    {
        super(database, connectionStringBuilder);
    }

    final void chainBufferFilters(DbBufferFilter readFilter, DbBufferFilter writeFilter) @safe
    in
    {
        assert(readFilter !is null);
        assert(readFilter.kind == DbBufferFilterKind.read);
        assert(writeFilter !is null);
        assert(writeFilter.kind == DbBufferFilterKind.write);
        assert(readFilter !is writeFilter);
    }
    do
    {
        DbBufferFilter.chainHead(_socketReadBufferFilters, readFilter);
        DbBufferFilter.chainTail(_socketWriteBufferFilters, writeFilter);
    }

    /* Properties */

    @property final SkConnectionStringBuilder skConnectionStringBuilder() nothrow pure @safe
    {
        return cast(SkConnectionStringBuilder)connectionStringBuilder;
    }

    @property final Socket socket() nothrow pure @safe
    {
        return _socket;
    }

    @property final bool socketActive() const nothrow @safe
    {
        return _socket !is null && _socket.handle != socket_t.init;
    }

package(pham.db):
    final DbReadBuffer acquireSocketReadBuffer(size_t capacity = DbDefaultSize.socketReadBufferLength) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (_socketReadBuffer is null)
            _socketReadBuffer = createSocketReadBuffer(capacity);
        return _socketReadBuffer;
    }

    final IbWriteBuffer acquireSocketWriteBuffer(size_t capacity = DbDefaultSize.socketWriteBufferLength) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (_socketWriteBuffers.empty)
            return createSocketWriteBuffer(capacity).isWriteBuffer();
        else
            return _socketWriteBuffers.remove(_socketWriteBuffers.last).isWriteBuffer();
    }

    final void releaseSocketWriteBuffer(IbWriteBuffer item) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (!disposingState)
            _socketWriteBuffers.insertEnd(item.reset().self());
    }

    void setSocketOptions() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        auto useCSB = skConnectionStringBuilder;
        socket.blocking = useCSB.blocking;
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.TCP_NODELAY, useCSB.noDelay ? 1 : 0);
        if (auto n = useCSB.receiveTimeout)
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, n);
        if (auto n = useCSB.sendTimeout)
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, n);
    }

    final size_t socketReadData(ubyte[] data) @trusted
    {
        version (TraceFunction) dgFunctionTrace();
        version (profile) debug auto p = PerfFunction.create();

        auto result = socket.receive(data);
        if (result == Socket.ERROR || (result == 0 && data.length != 0))
        {
            if (result == Socket.ERROR)
                result = size_t.max;

            auto socketMessage = lastSocketError();
            auto socketCode = lastSocketErrorCode();
            throwReadDataError(socketCode, socketMessage);
        }
        else if (result > 0 && _socketReadBufferFilters !is null)
        {
            ubyte[] filteredData = data[0..result];
            for (auto nextFilter = _socketReadBufferFilters; nextFilter !is null; nextFilter = nextFilter.next)
            {
                version (TraceFunction) dgFunctionTrace("filter=", nextFilter.processName, ", length=", filteredData.length, ", data=", bytesToHexs(filteredData));

                if (!nextFilter.process(filteredData, filteredData))
                    throwReadDataError(nextFilter.errorCode, nextFilter.errorMessage);

                version (TraceFunction) dgFunctionTrace("filter=", nextFilter.processName, ", length=", filteredData.length, ", data=", bytesToHexs(filteredData));
            }
            // TODO check for data.length - expand it?
            result = filteredData.length;
            data[0..result] = filteredData[0..result];
        }

        return result;
    }

    final size_t socketWriteData(scope const(ubyte)[] data) @trusted
    {
        version (TraceFunction) dgFunctionTrace();

        void throwError(uint errorRawCode, string errorRawMessage)
        {
            auto msg = format(DbMessage.eWriteData, connectionStringBuilder.forErrorInfo(), errorRawMessage);
            throw createWriteDataError(msg, errorRawCode, null);
        }

        const(ubyte)[] sendingData;

        if (data.length && _socketWriteBufferFilters !is null)
        {
            bool firstFilter = true;
            ubyte[] filteredData;
            for (auto nextFilter = _socketWriteBufferFilters; nextFilter !is null; nextFilter = nextFilter.next)
            {
                version (TraceFunction)
                {
                    const(ubyte)[] logData = firstFilter ? data : filteredData;
                    dgFunctionTrace("filter=", nextFilter.processName, ", length=", logData.length, ", data=", bytesToHexs(logData));
                }

                if (!nextFilter.process(firstFilter ? data : filteredData, filteredData))
                    throwError(nextFilter.errorCode, nextFilter.errorMessage);

                version (TraceFunction) dgFunctionTrace("filter=", nextFilter.processName, ", length=", filteredData.length, ", data=", bytesToHexs(filteredData));

                firstFilter = false;
            }
            sendingData = filteredData;
        }
        else
            sendingData = data;

        auto result = socket.send(sendingData);
        if (result == Socket.ERROR || result != sendingData.length)
        {
            if (result == Socket.ERROR)
                result = size_t.max;

            auto socketMessage = lastSocketError();
            auto socketCode = lastSocketErrorCode();
            throwError(socketCode, socketMessage);
        }
        return result;
    }

protected:
    SkException createConnectError(string message, int socketCode, Exception e) @safe
    {
        if (auto log = logger)
            log.error(forLogInfo(), newline, message, e);
        return new SkException(e.msg, DbErrorCode.connect, socketCode, 0, e);
    }

    SkException createReadDataError(string message, int socketCode, Exception e) @safe
    {
        if (auto log = logger)
            log.error(forLogInfo(), newline, message, e);
        return new SkException(message, DbErrorCode.read, socketCode, 0, e);
    }

    SkException createWriteDataError(string message, int socketCode, Exception e) @safe
    {
        if (auto log = logger)
            log.error(forLogInfo(), newline, message, e);
        return new SkException(message, DbErrorCode.write, socketCode, 0, e);
    }

    final void disposeSocket(bool disposing) nothrow @safe
    {
        version (TraceFunction)
        if (disposing)
            dgFunctionTrace();

        scope (exit)
        {
            disposeSocketBufferFilters(disposing);
            disposeSocketReadBuffer(disposing);
            disposeSocketWriteBuffers(disposing);
            _socket = null;
        }

        if (socketActive)
            _socket.close();
    }

    final void disposeSocketBufferFilters(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        while (_socketReadBufferFilters !is null)
        {
            auto temp = _socketReadBufferFilters;
            _socketReadBufferFilters = _socketReadBufferFilters.next;
            temp.disposal(disposing);
        }

        while (_socketWriteBufferFilters !is null)
        {
            auto temp = _socketWriteBufferFilters;
            _socketWriteBufferFilters = _socketWriteBufferFilters.next;
            temp.disposal(disposing);
        }
    }

    final void disposeSocketReadBuffer(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (_socketReadBuffer !is null)
        {
            _socketReadBuffer.disposal(disposing);
            _socketReadBuffer = null;
        }
    }

    final void disposeSocketWriteBuffers(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        while (!_socketWriteBuffers.empty)
            _socketWriteBuffers.remove(_socketWriteBuffers.last).disposal(disposing);
    }

    override void doClose() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        disposeSocketBufferFilters(false);
        doCloseSocket();
    }

    final void doCloseSocket() @safe
    {
        version (TraceFunction) dgFunctionTrace();

        if (state != DbConnectionState.opening)
            disposeSocket(true);
        else if (socketActive)
            _socket.close();
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        version (TraceFunction) dgFunctionTrace();

        super.doDispose(disposing);
        disposeSocket(disposing);
        disposeSocketBufferFilters(disposing);
        disposeSocketReadBuffer(disposing);
        disposeSocketReadBuffer(disposing);
    }

    final void doOpenSocket() @trusted
    {
        version (TraceFunction) dgFunctionTrace();

        auto useCSB = skConnectionStringBuilder;

        if (_socket !is null && _socket.addressFamily != useCSB.toAddressFamily())
            doCloseSocket();

        if (_socket is null)
        {
            _socket = new Socket(useCSB.toAddressFamily(), SocketType.STREAM);
            _socket.blocking = useCSB.blocking;
        }

        try
        {
            auto address = useCSB.toAddress();
            _socket.connect(address);
            setSocketOptions();
        }
        catch (Exception e)
        {
            auto socketErrorMsg = e.msg;
            auto socketErrorCode = lastSocketErrorCode();
            throw createConnectError(socketErrorMsg, socketErrorCode, e);
        }
    }

    final int lastSocketErrorCode()
    {
        //version (TraceFunction) dgFunctionTrace();

        version (Windows)
        {
            import core.sys.windows.winsock2;
            return WSAGetLastError();
        }
        else version (Posix)
        {
            import core.stdc.errno;
            return errno;
        }
        else
        {
            pragma(msg, "No socket error code for this platform.");
            return 0;
        }
    }

    final void throwReadDataError(uint errorRawCode, string errorRawMessage) @safe
    {
        auto msg = format(DbMessage.eReadData, connectionStringBuilder.forErrorInfo(), errorRawMessage);
        throw createReadDataError(msg, errorRawCode, null);
    }

    abstract DbReadBuffer createSocketReadBuffer(size_t capacity = DbDefaultSize.socketReadBufferLength) nothrow @safe;
    abstract DbBuffer createSocketWriteBuffer(size_t capacity = DbDefaultSize.socketWriteBufferLength) nothrow @safe;

protected:
    Socket _socket;
    DbBufferFilter _socketReadBufferFilters;
    DbBufferFilter _socketWriteBufferFilters;

private:
    DbReadBuffer _socketReadBuffer;
    DLinkDbBufferTypes.DLinkList _socketWriteBuffers;
}

abstract class SkConnectionStringBuilder : DbConnectionStringBuilder
{
public:
    this(string connectionString) nothrow @safe
    {
        super(connectionString);
    }

    final AddressFamily toAddressFamily() nothrow
    {
        // todo for iv6 AddressFamily.INET6
        return AddressFamily.INET;
    }

    final Address toAddress()
    {
        // todo for iv6
        return new InternetAddress(serverName, port);
    }

    @property final bool blocking() const nothrow @safe
    {
        return isDbTrue(getString(DbParameterName.socketBlocking));
    }

    @property final typeof(this) blocking(bool value) nothrow
    {
        auto setValue = value ? dbBoolTrue : dbBoolFalse;
        put(DbParameterName.socketBlocking, setValue);
        return this;
    }

    @property final bool noDelay() const nothrow @safe
    {
        return isDbTrue(getString(DbParameterName.socketNoDelay));
    }

    @property final typeof(this) noDelay(bool value) nothrow
    {
        auto setValue = value ? dbBoolTrue : dbBoolFalse;
        put(DbParameterName.socketNoDelay, setValue);
        return this;
    }

protected:
    override string getDefault(string name) const nothrow @safe
    {
        auto result = super.getDefault(name);
        if (result.length == 0)
        {
            auto n = DbIdentitier(name);
            result = assumeWontThrow(skDefaultParameterValues.get(n, null));
        }
        return result;
    }

    override void setDefaultIfs()
    {
        super.setDefaultIfs();
        putIf(DbParameterName.socketBlocking, getDefault(DbParameterName.socketBlocking));
        putIf(DbParameterName.socketNoDelay, getDefault(DbParameterName.socketNoDelay));
    }
}

class SkReadBuffer : DbReadBuffer
{
@safe:

public:
    this(SkConnection connection, size_t capacity) nothrow
    {
        super(capacity);
        this._connection = connection;
        version (TraceFunction) readCounter = 0;
    }

    version (TraceFunction) static size_t readCounter = 0;
    final override void fill(const size_t additionalBytes, bool mustSatisfied)
    {
        version (profile) debug auto p = PerfFunction.create();

        if (_offset && (_offset + additionalBytes) > _data.length)
            mergeOffset();

        reserve(additionalBytes);
        const nOffset = _offset + length;

        //dgWriteln("nOffset=", nOffset, ", _data.length=", _data.length, ", additionalBytes=", additionalBytes, ", length=", length);

        // n=size_t.max -> no data returned
        const n = connection.socketReadData(_data[nOffset.._data.length]);
        const hasReadData = n != size_t.max;
        if (hasReadData)
        {
            _maxLength += n;

            version (TraceFunction)
            {
                auto readBytes = _data[nOffset..nOffset + n];
                readCounter++;
                dgFunctionTrace("counter=", readCounter,
                    ", read_length=", n,
                    ", read_data=", bytesToHexs(readBytes),
                    ", _offset=", _offset,
                    ", _maxlength=", _maxLength);
            }
        }

        if (mustSatisfied && (!hasReadData || n < additionalBytes))
        {
            auto msg = format(DbMessage.eNotEnoughData, additionalBytes, hasReadData ? n : 0);
            connection.throwReadDataError(0, msg);
        }
    }

    @property final SkConnection connection() nothrow pure
    {
        return _connection;
    }

protected:
    override void doDispose(bool disposing) nothrow
    {
        _connection = null;
        super.doDispose(disposing);
    }

protected:
    SkConnection _connection;
}

class SkWriteBuffer(Endian EndianKind = Endian.bigEndian) : DbWriteBuffer!EndianKind
{
@safe:

public:
    this(SkConnection connection, size_t capacity) nothrow
    {
        super(capacity);
        this._connection = connection;
        version (TraceFunction) flushCounter = 0;
    }

    version (TraceFunction) static size_t flushCounter = 0;
    override void flush()
    {
        auto flushBytes = peekBytes();

        version (TraceFunction)
        {
            flushCounter++;
            dgFunctionTrace("counter=", flushCounter, ", length=", flushBytes.length, ", data=", bytesToHexs(flushBytes));
        }

        connection.socketWriteData(flushBytes);
        super.flush();
    }

    @property final SkConnection connection() nothrow pure
    {
        return _connection;
    }

protected:
    override void doDispose(bool disposing) nothrow
    {
        _connection = null;
        super.doDispose(disposing);
    }

protected:
    SkConnection _connection;
}

struct SkWriteBufferLocal(C: SkConnection)
{
@safe:

public:
    @disable this(this);

    this(C connection,
        IbWriteBuffer buffer = null) nothrow
    {
        this._connection = connection;
        this._buffer = buffer;
        this._needBuffer = buffer is null;
        if (this._needBuffer)
            this._buffer = connection.acquireSocketWriteBuffer();
        else
            buffer.reset();
    }

    ~this()
    {
        dispose(false);
    }

    void dispose(bool disposing = true)
    {
        if (_needBuffer && _buffer !is null && _connection !is null)
            _connection.releaseSocketWriteBuffer(_buffer);

        _buffer = null;
        _connection = null;
    }

    @property B buffer() nothrow
    {
        return _buffer;
    }

    @property C connection() nothrow
    {
        return _connection;
    }

    alias buffer this;

private:
    B _buffer;
    C _connection;
    bool _needBuffer;
}


// Any below codes are private
private:

shared static this()
{
    skDefaultParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(string[string]))[
            DbParameterName.packageSize : "‭16383‬", // In bytes - do not add underscore, to!... does not work
            DbParameterName.socketBlocking : dbBoolTrue,
            DbParameterName.socketNoDelay : dbBoolTrue
        ];
    }();
}
