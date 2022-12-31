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

import std.conv : to;
import std.exception : assumeWontThrow;
import std.socket : Address, AddressFamily, InternetAddress, ProtocolType, Socket, socket_t, SocketOption, SocketOptionLevel, SocketType;

version (profile) import pham.utl.test : PerfFunction;
version (unittest) import pham.utl.test;
import pham.cp.openssl;
import pham.utl.disposable : DisposingReason, isDisposing;
import pham.utl.system : lastSocketError, lastSocketErrorCode;
import pham.db.buffer;
import pham.db.buffer_filter;
import pham.db.buffer_filter_cipher;
import pham.db.convert;
import pham.db.database;
import pham.db.exception;
import pham.db.message;
import pham.db.object : DbIdentitier;
import pham.db.type;
import pham.db.util;
import pham.db.value;

static immutable string[string] skDefaultConnectionParameterValues;

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

    final override DbRowValue fetch(const(bool) isScalar) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();
        version (profile) debug auto p = PerfFunction.create();

        checkActive();

		if (isStoredProcedure)
            return fetchedRows ? fetchedRows.dequeue() : DbRowValue(0);

        if (fetchedRows.empty && !allRowsFetched && isSelectCommandType())
            doFetch(isScalar);

        return fetchedRows ? fetchedRows.dequeue() : DbRowValue(0);
    }

protected:
    override void prepareExecuting(const(DbCommandExecuteType) type) @safe
    {
        fetchedRows.clear();
        super.prepareExecuting(type);
    }

    abstract void doFetch(const(bool) isScalar) @safe;

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

    this(DbDatabase database, string connectionString) @safe
    {
        super(database, connectionString);
    }

    this(DbDatabase database, SkConnectionStringBuilder connectionString) nothrow @safe
    {
        super(database, connectionString);
    }

    this(DbDatabase database, DbURL!string connectionString) @safe
    {
        super(database, connectionString);
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

    @property final SkConnectionStringBuilder skConnectionStringBuilder() nothrow pure @safe
    {
        return cast(SkConnectionStringBuilder)connectionStringBuilder;
    }

    @property final Socket socket() nothrow pure @safe
    {
        return _socket;
    }

    @property final bool socketActive() const nothrow pure @safe
    {
        return _socket !is null && _socket.handle != socket_t.init;
    }

    @property final bool socketSSLActive() const nothrow pure @safe
    {
        return _sslSocket.isConnected && socketActive;
    }

package(pham.db):
    final DbReadBuffer acquireSocketReadBuffer(size_t capacity = DbDefaultSize.socketReadBufferLength) nothrow @safe
    {
        version (TraceFunctionReader) traceFunction!("pham.db.database")();

        if (_socketReadBuffer is null)
            _socketReadBuffer = createSocketReadBuffer(capacity);
        return _socketReadBuffer;
    }

    final DbWriteBuffer acquireSocketWriteBuffer(size_t capacity = DbDefaultSize.socketWriteBufferLength) nothrow @safe
    {
        version (TraceFunctionWriter) traceFunction!("pham.db.database")();

        if (_socketWriteBuffers.empty)
            return createSocketWriteBuffer(capacity);
        else
            return cast(DbWriteBuffer)(_socketWriteBuffers.remove(_socketWriteBuffers.last));
    }

    final ResultStatus doOpenSSL() @safe
    {
        auto rs = _sslSocket.initialize();
        if (rs.isError)
            return rs;

        rs = _sslSocket.connect(_socket.handle);
        if (rs.isError)
        {
            _sslSocket.uninitialize();
            return rs;
        }

        return ResultStatus.ok();
    }

    final void releaseSocketWriteBuffer(DbWriteBuffer item) nothrow @safe
    {
        version (TraceFunctionWriter) traceFunction!("pham.db.database")();

        if (!isDisposing(lastDisposingReason))
            _socketWriteBuffers.insertEnd(item.reset());
    }

    void setSocketOptions() @safe
    {
        version (TraceFunctionReader) traceFunction!("pham.db.database")();

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
        version (TraceFunctionReader) traceFunction!("pham.db.database")("_sslSocket.isConnected=", _sslSocket.isConnected);
        version (profile) debug auto p = PerfFunction.create();

        size_t result;
        if (_sslSocket.isConnected)
        {
            const rs = _sslSocket.receive(data, result);
            if (rs.isError)
                throwReadDataError(rs.errorCode, rs.errorMessage);
        }
        else
        {
            result = socket.receive(data);
            if (result == Socket.ERROR || (result == 0 && data.length != 0))
            {
                if (result == Socket.ERROR)
                    result = size_t.max;

                auto status = lastSocketError("receive");
                throwReadDataError(status.errorCode, status.errorMessage);
            }
        }

        if (result > 0 && _socketReadBufferFilters !is null)
        {
            ubyte[] filteredData = data[0..result];
            for (auto nextFilter = _socketReadBufferFilters; nextFilter !is null; nextFilter = nextFilter.next)
            {
                version (TraceFunctionReader) traceFunction!("pham.db.database")("filter=", nextFilter.processName, ", length=", filteredData.length, ", data=", filteredData.dgToHex());

                if (!nextFilter.process(filteredData, filteredData))
                    throwReadDataError(nextFilter.errorCode, nextFilter.errorMessage);

                version (TraceFunctionReader) traceFunction!("pham.db.database")("filter=", nextFilter.processName, ", length=", filteredData.length, ", data=", filteredData.dgToHex());
            }
            // TODO check for data.length - expand it?
            result = filteredData.length;
            data[0..result] = filteredData[0..result];

            version (TraceFunctionReader) traceFunction!("pham.db.database")("data=", data[0..result].dgToHex());
        }

        return result;
    }

    final size_t socketWriteData(scope const(ubyte)[] data) @trusted
    {
        version (TraceFunctionWriter) traceFunction!("pham.db.database")("_sslSocket.isConnected=", _sslSocket.isConnected, ", data=", data.dgToHex());

        const(ubyte)[] sendingData;

        if (data.length && _socketWriteBufferFilters !is null)
        {
            bool firstFilter = true;
            ubyte[] filteredData;
            for (auto nextFilter = _socketWriteBufferFilters; nextFilter !is null; nextFilter = nextFilter.next)
            {
                version (TraceFunctionWriter)
                {
                    const(ubyte)[] logData = firstFilter ? data : filteredData;
                    traceFunction!("pham.db.database")("filter=", nextFilter.processName, ", length=", logData.length, ", data=", logData.dgToHex());
                }

                if (!nextFilter.process(firstFilter ? data : filteredData, filteredData))
                    throwWriteDataError(nextFilter.errorCode, nextFilter.errorMessage);

                version (TraceFunctionWriter) traceFunction!("pham.db.database")("filter=", nextFilter.processName, ", length=", filteredData.length, ", data=", filteredData.dgToHex());

                firstFilter = false;
            }
            sendingData = filteredData;
        }
        else
            sendingData = data;

        size_t result;
        if (_sslSocket.isConnected)
        {
            const rs = _sslSocket.send(sendingData, result);
            if (rs.isError)
                throwWriteDataError(rs.errorCode, rs.errorMessage);
        }
        else
        {
            result = _socket.send(sendingData);
            if (result == Socket.ERROR || result != sendingData.length)
            {
                if (result == Socket.ERROR)
                    result = size_t.max;

                auto status = lastSocketError("send");
                throwWriteDataError(status.errorCode, status.errorMessage);
            }
        }

        version (TraceFunctionWriter) traceFunction!("pham.db.database")("_sslSocket.isConnected=", _sslSocket.isConnected, ", result=", result);

        return result;
    }

    final void throwConnectError(int errorRawCode, string errorRawMessage) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")("errorRawCode=", errorRawCode, ", errorRawMessage=", errorRawMessage);

        auto msg = DbMessage.eConnect.fmtMessage(connectionStringBuilder.forErrorInfo(), errorRawMessage);
        throw createConnectError(errorRawCode, msg, null);
    }

    final void throwReadDataError(int errorRawCode, string errorRawMessage) @safe
    {
        version (TraceFunctionReader) traceFunction!("pham.db.database")("errorRawCode=", errorRawCode, ", errorRawMessage=", errorRawMessage);

        auto msg = DbMessage.eReadData.fmtMessage(connectionStringBuilder.forErrorInfo(), errorRawMessage);
        throw createReadDataError(errorRawCode, msg, null);
    }

    final void throwWriteDataError(int errorRawCode, string errorRawMessage) @safe
    {
        version (TraceFunctionWriter) traceFunction!("pham.db.database")("errorRawCode=", errorRawCode, ", errorRawMessage=", errorRawMessage);

        auto msg = DbMessage.eWriteData.fmtMessage(connectionStringBuilder.forErrorInfo(), errorRawMessage);
        throw createWriteDataError(errorRawCode, msg, null);
    }

protected:
    final bool canWriteDisconnectMessage() const nothrow pure @safe
    {
        return !isFatalError && socketActive;
    }

    SkException createConnectError(int errorCode, string errorMessage, Exception e) @safe
    {
        if (auto log = logger)
            log.error(forLogInfo(), newline, errorMessage, e);
        return new SkException(errorMessage, DbErrorCode.connect, null, errorCode, 0, e);
    }

    SkException createReadDataError(int errorCode, string errorMessage, Exception e) @safe
    {
        if (auto log = logger)
            log.error(forLogInfo(), newline, errorMessage, e);
        return new SkException(errorMessage, DbErrorCode.read, null, errorCode, 0, e);
    }

    SkException createWriteDataError(int errorCode, string errorMessage, Exception e) @safe
    {
        if (auto log = logger)
            log.error(forLogInfo(), newline, errorMessage, e);
        return new SkException(errorMessage, DbErrorCode.write, null, errorCode, 0, e);
    }

    DbReadBuffer createSocketReadBuffer(size_t capacity = DbDefaultSize.socketReadBufferLength) nothrow @safe
    {
        return new SkReadBuffer(this, capacity);
    }

    DbWriteBuffer createSocketWriteBuffer(size_t capacity = DbDefaultSize.socketWriteBufferLength) nothrow @safe
    {
        return new SkWriteBuffer(this, capacity);
    }

    final void disposeSocket(const(DisposingReason) disposingReason) nothrow @safe
    {
        _sslSocket.dispose(disposingReason);
        disposeSocketBufferFilters(disposingReason);
        disposeSocketReadBuffer(disposingReason);
        disposeSocketWriteBuffers(disposingReason);
        if (socketActive)
            _socket.close();
        _socket = null;
    }

    final void disposeSocketBufferFilters(const(DisposingReason) disposingReason) nothrow @safe
    {
        while (_socketReadBufferFilters !is null)
        {
            auto temp = _socketReadBufferFilters;
            _socketReadBufferFilters = _socketReadBufferFilters.next;
            temp.dispose(disposingReason);
        }

        while (_socketWriteBufferFilters !is null)
        {
            auto temp = _socketWriteBufferFilters;
            _socketWriteBufferFilters = _socketWriteBufferFilters.next;
            temp.dispose(disposingReason);
        }
    }

    final void disposeSocketReadBuffer(const(DisposingReason) disposingReason) nothrow @safe
    {
        if (_socketReadBuffer !is null)
        {
            _socketReadBuffer.dispose(disposingReason);
            _socketReadBuffer = null;
        }
    }

    final void disposeSocketWriteBuffers(const(DisposingReason) disposingReason) nothrow @safe
    {
        while (!_socketWriteBuffers.empty)
            _socketWriteBuffers.remove(_socketWriteBuffers.last).dispose(disposingReason);
    }

    override void doClose(bool failedOpen) @safe
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        disposeSocket(DisposingReason.other);
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        super.doDispose(disposingReason);
        disposeSocket(disposingReason);
    }

    final void doOpenSocket() @trusted
    {
        version (TraceFunction) traceFunction!("pham.db.database")();

        auto useCSB = skConnectionStringBuilder;

        if (_socket !is null && _socket.addressFamily != useCSB.toAddressFamily())
            disposeSocket(DisposingReason.other);

        if (useCSB.encrypt != DbEncryptedConnection.disabled)
            setSSLSocketOptions();

        if (_socket is null)
            _socket = new Socket(useCSB.toAddressFamily(), SocketType.STREAM, ProtocolType.TCP);

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
            throw createConnectError(socketErrorCode, socketErrorMsg, e);
        }
    }

    void setSSLSocketOptions()
    {
        auto useCSB = skConnectionStringBuilder;

        _sslSocket.sslCa = useCSB.sslCa;
        _sslSocket.sslCaDir = useCSB.sslCaDir;
        _sslSocket.sslCert = useCSB.sslCert;
        _sslSocket.sslKey = useCSB.sslKey;
        _sslSocket.sslKeyPassword = useCSB.sslKeyPassword;
        _sslSocket.verificationMode = useCSB.sslVerificationMode;
        _sslSocket.verificationHost = useCSB.sslVerificationHost ? useCSB.serverName : null;
    }

protected:
    Socket _socket;
    DbBufferFilter _socketReadBufferFilters;
    DbBufferFilter _socketWriteBufferFilters;
    OpenSSLClientSocket _sslSocket;

private:
    DbReadBuffer _socketReadBuffer;
    DLinkDbBufferTypes.DLinkList _socketWriteBuffers;
}

abstract class SkConnectionStringBuilder : DbConnectionStringBuilder
{
@safe:

public:
    this(DbDatabase database) nothrow
    {
        super(database);
    }

    this(DbDatabase database, string connectionString)
    {
        super(database, connectionString);
    }

    final bool hasSSL() const nothrow
    {
        return (sslCert.length || sslKey.length) && (sslCa.length || sslCaDir.length);
    }

    final Address toAddress()
    {
        // todo for iv6
        return new InternetAddress(serverName, serverPort);
    }

    final AddressFamily toAddressFamily() nothrow
    {
        // todo for iv6 AddressFamily.INET6
        return AddressFamily.INET;
    }

    @property final bool blocking() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.socketBlocking));
    }

    @property final typeof(this) blocking(bool value) nothrow
    {
        auto setValue = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.socketBlocking, setValue);
        return this;
    }

    @property final bool noDelay() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.socketNoDelay));
    }

    @property final typeof(this) noDelay(bool value) nothrow
    {
        auto setValue = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.socketNoDelay, setValue);
        return this;
    }

    @property final string sslCa() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.socketSslCa);
    }

    @property final typeof(this) sslCa(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.socketSslCa, value);
        return this;
    }

    @property final string sslCaDir() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.socketSslCaDir);
    }

    @property final typeof(this) sslCaDir(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.socketSslCaDir, value);
        return this;
    }

    @property final string sslCert() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.socketSslCert);
    }

    @property final typeof(this) sslCert(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.socketSslCert, value);
        return this;
    }

    @property final string sslKey() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.socketSslKey);
    }

    @property final typeof(this) sslKey(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.socketSslKey, value);
        return this;
    }

    @property final string sslKeyPassword() const nothrow
    {
        return getString(DbConnectionParameterIdentifier.socketSslKeyPassword);
    }

    @property final typeof(this) sslKeyPassword(string value) nothrow
    {
        put(DbConnectionParameterIdentifier.socketSslKeyPassword, value);
        return this;
    }

    @property final bool sslVerificationHost() const nothrow
    {
        return isDbTrue(getString(DbConnectionParameterIdentifier.socketSslVerificationHost));
    }

    @property final typeof(this) sslVerificationHost(bool value) nothrow
    {
        auto setValue = value ? dbBoolTrue : dbBoolFalse;
        put(DbConnectionParameterIdentifier.socketSslVerificationHost, setValue);
        return this;
    }

    @property final int sslVerificationMode() const nothrow
    {
        return toIntegerSafe!int(getString(DbConnectionParameterIdentifier.socketSslVerificationMode), -1);
    }

    @property final typeof(this) sslVerificationMode(int value) nothrow
    {
        auto setValue = value >= -1 ? to!string(value) : getDefault(DbConnectionParameterIdentifier.socketSslVerificationMode);
        put(DbConnectionParameterIdentifier.socketSslVerificationMode, setValue);
        return this;
    }

protected:
    override string getDefault(string name) const nothrow
    {
        auto result = super.getDefault(name);
        if (result.length == 0)
        {
            auto n = DbIdentitier(name);
            result = assumeWontThrow(skDefaultConnectionParameterValues.get(n, null));
        }
        return result;
    }

    override void setDefaultIfs()
    {
        super.setDefaultIfs();
        putIf(DbConnectionParameterIdentifier.socketBlocking, getDefault(DbConnectionParameterIdentifier.socketBlocking));
        putIf(DbConnectionParameterIdentifier.socketNoDelay, getDefault(DbConnectionParameterIdentifier.socketNoDelay));
        putIf(DbConnectionParameterIdentifier.socketSslVerificationMode, getDefault(DbConnectionParameterIdentifier.socketSslVerificationMode));
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
        version (TraceFunctionReader) readCounter = 0;
    }

    version (TraceFunctionReader) static size_t readCounter = 0;
    final override void fill(const(size_t) additionalBytes, bool mustSatisfied)
    {
        version (profile) debug auto p = PerfFunction.create();

        if (_offset && (_offset + additionalBytes) > _data.length)
            mergeOffset();

        reserve(additionalBytes);
        const nOffset = _offset + length;

        //import pham.utl.test; dgWriteln("nOffset=", nOffset, ", _data.length=", _data.length, ", additionalBytes=", additionalBytes.dgToHex(), ", length=", length);

        // n=size_t.max -> no data returned
        const n = connection.socketReadData(_data[nOffset.._data.length]);
        const hasReadData = n != size_t.max;
        if (hasReadData)
        {
            _maxLength += n;

            version (TraceFunctionReader)
            {
                readCounter++;
                auto readBytes = _data[nOffset..nOffset + n];
                traceFunction!("pham.db.database")("counter=", readCounter, ", read_length=", n, ", read_data=", readBytes.dgToHex(), ", _offset=", _offset, ", _maxlength=", _maxLength);
            }
        }

        if (mustSatisfied && (!hasReadData || n < additionalBytes))
        {
            auto msg = DbMessage.eNotEnoughData.fmtMessage(additionalBytes, hasReadData ? n : 0);
            connection.throwReadDataError(0, msg);
        }
    }

    @property final SkConnection connection() nothrow pure
    {
        return _connection;
    }

protected:
    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        if (isDisposing(disposingReason))
            _connection = null;
        super.doDispose(disposingReason);
    }

protected:
    SkConnection _connection;
}

class SkWriteBuffer : DbWriteBuffer
{
@safe:

public:
    this(SkConnection connection, size_t capacity) nothrow
    {
        super(capacity);
        this._connection = connection;
        version (TraceFunctionWriter) flushCounter = 0;
    }

    version (TraceFunctionWriter) static size_t flushCounter = 0;
    override void flush()
    {
        auto flushBytes = peekBytes();

        version (TraceFunctionWriter)
        {
            flushCounter++;
            traceFunction!("pham.db.database")("counter=", flushCounter, ", length=", flushBytes.length, ", data=", flushBytes.dgToHex());
        }

        connection.socketWriteData(flushBytes);
        super.flush();
    }

    @property final SkConnection connection() nothrow pure
    {
        return _connection;
    }

protected:
    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        if (isDisposing(disposingReason))
            _connection = null;
        super.doDispose(disposingReason);
    }

protected:
    SkConnection _connection;
}

struct SkWriteBufferLocal
{
@safe:

public:
    @disable this(this);

    this(SkConnection connection) nothrow
    {
        this._needBuffer = true;
        this._connection = connection;
        this._buffer = connection.acquireSocketWriteBuffer();
    }

    this(SkConnection connection, SkWriteBuffer buffer) nothrow
    {
        this._needBuffer = false;
        this._connection = connection;
        this._buffer = buffer;
        buffer.reset();
    }

    ~this()
    {
        dispose(DisposingReason.destructor);
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow @safe
    {
        if (_needBuffer && _buffer !is null && _connection !is null)
            _connection.releaseSocketWriteBuffer(_buffer);
        _buffer = null;
        if (isDisposing(disposingReason))
            _connection = null;
    }

    @property DbWriteBuffer buffer() nothrow pure
    {
        return _buffer;
    }

    @property SkConnection connection() nothrow pure
    {
        return _connection;
    }

    alias buffer this;

private:
    DbWriteBuffer _buffer;
    SkConnection _connection;
    bool _needBuffer;
}


// Any below codes are private
private:

shared static this()
{
    skDefaultConnectionParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        return cast(immutable(string[string]))[
            DbConnectionParameterIdentifier.packageSize : "16384", // In bytes - do not add underscore, to!int does not work
            DbConnectionParameterIdentifier.socketBlocking : dbBoolTrue,
            DbConnectionParameterIdentifier.socketNoDelay : dbBoolTrue,
            DbConnectionParameterIdentifier.socketSslVerificationHost : dbBoolFalse,
            DbConnectionParameterIdentifier.socketSslVerificationMode : "-1", // Ignore
        ];
    }();
}
