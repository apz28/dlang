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

module pham.db.db_skdatabase;

version (pham_io_socket)
    enum usePhamIOSocket = true;
else
    enum usePhamIOSocket = false;
    
import std.conv : to;
static if (!usePhamIOSocket) import std.socket : Address, AddressFamily, InternetAddress, Internet6Address,
    ProtocolType, Socket, socket_t, SocketOption, SocketOptionLevel, SocketType;

version (profile) import pham.utl.utl_test : PerfFunction;
version (unittest) import pham.utl.utl_test;
import pham.cp.cp_openssl;
static if (usePhamIOSocket) import pham.io.io_socket;
static if (!usePhamIOSocket) import pham.io.io_socket_error;
import pham.utl.utl_disposable : DisposingReason, isDisposing;
static if (!usePhamIOSocket) import pham.utl.utl_text : simpleIndexOf;
import pham.db.db_buffer;
import pham.db.db_buffer_filter;
import pham.db.db_buffer_filter_cipher;
import pham.db.db_convert;
import pham.db.db_database;
import pham.db.db_exception;
import pham.db.db_message;
import pham.db.db_object : DbIdentitier;
import pham.db.db_type;
import pham.db.db_util;
import pham.db.db_value;

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
        version (TraceFunction) traceFunction();
        version (profile) debug auto p = PerfFunction.create();

        checkActive();

        if (auto log = canTraceLog())
            log.infof("%s.command.fetch()%s%s", forLogInfo(), newline, commandText);

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

    pragma(inline, true)
    @property final bool socketActive() const nothrow pure @safe
    {
        static if (!usePhamIOSocket)
            return _socket !is null && _socket.handle != socket_t.init;
        else
            return _socket !is null && _socket.active;
    }

    pragma(inline, true)
    @property final bool socketSSLActive() const nothrow pure @safe
    {
        return socketActive && _sslSocket.isConnected;
    }

package(pham.db):
    final DbReadBuffer acquireSocketReadBuffer(size_t capacity = DbDefaultSize.socketReadBufferLength) nothrow @safe
    {
        version (TraceFunctionReader) traceFunction();

        if (_socketReadBuffer is null)
            _socketReadBuffer = createSocketReadBuffer(capacity);
        return _socketReadBuffer;
    }

    final DbWriteBuffer acquireSocketWriteBuffer(size_t capacity = DbDefaultSize.socketWriteBufferLength) nothrow @safe
    {
        version (TraceFunctionWriter) traceFunction();

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

        rs = _sslSocket.connect(cast(int)_socket.handle);
        if (rs.isError)
        {
            _sslSocket.uninitialize();
            return rs;
        }

        return ResultStatus.ok();
    }

    final void releaseSocketWriteBuffer(DbWriteBuffer item) nothrow @safe
    {
        version (TraceFunctionWriter) traceFunction();

        if (!isDisposing(lastDisposingReason))
            _socketWriteBuffers.insertEnd(item.reset());
    }

    final size_t socketReadData(ubyte[] data) @trusted
    {
        version (TraceFunctionReader) traceFunction("_sslSocket.isConnected=", _sslSocket.isConnected);
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
            static if (!usePhamIOSocket)
            {
                result = _socket.receive(data);
                if ((result == Socket.ERROR) || (result == 0 && data.length != 0))
                {
                    auto status = lastSocketError("receive");
                    throwReadDataError(status.errorCode, status.errorMessage);
                }
            }
            else
            {
                const rs = _socket.receive(data);
                if ((rs < 0) || (rs == 0 && data.length != 0))
                    throwReadDataError(_socket.lastError.errorCode, _socket.lastError.errorMessage);
                result = cast(size_t)(rs);
            }
        }

        if (result > 0 && _socketReadBufferFilters !is null)
        {
            ubyte[] filteredData = data[0..result];
            for (auto nextFilter = _socketReadBufferFilters; nextFilter !is null; nextFilter = nextFilter.next)
            {
                version (TraceFunctionReader) traceFunction("filter=", nextFilter.processName, ", length=", filteredData.length, ", data=", filteredData.dgToHex());

                if (!nextFilter.process(filteredData, filteredData))
                    throwReadDataError(nextFilter.errorCode, nextFilter.errorMessage);

                version (TraceFunctionReader) traceFunction("filter=", nextFilter.processName, ", length=", filteredData.length, ", data=", filteredData.dgToHex());
            }
            // TODO check for data.length - expand it?
            result = filteredData.length;
            data[0..result] = filteredData[0..result];

            version (TraceFunctionReader) traceFunction("data=", data[0..result].dgToHex());
        }

        return result;
    }

    final size_t socketWriteData(scope const(ubyte)[] data) @trusted
    {
        version (TraceFunctionWriter) traceFunction("_sslSocket.isConnected=", _sslSocket.isConnected, ", data=", data.dgToHex());

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
                    traceFunction("filter=", nextFilter.processName, ", length=", logData.length, ", data=", logData.dgToHex());
                }

                if (!nextFilter.process(firstFilter ? data : filteredData, filteredData))
                    throwWriteDataError(nextFilter.errorCode, nextFilter.errorMessage);

                version (TraceFunctionWriter) traceFunction("filter=", nextFilter.processName, ", length=", filteredData.length, ", data=", filteredData.dgToHex());

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
            static if (!usePhamIOSocket)
            {
                result = _socket.send(sendingData);
                if (result == Socket.ERROR || result != sendingData.length)
                {
                    auto status = lastSocketError("send");
                    throwWriteDataError(status.errorCode, status.errorMessage);
                }
            }
            else
            {
                const rs = _socket.send(sendingData);
                if (rs < 0 || rs != sendingData.length)
                    throwWriteDataError(_socket.lastError.errorCode, _socket.lastError.errorMessage);
                result = cast(size_t)(rs);
            }
        }

        version (TraceFunctionWriter) traceFunction("_sslSocket.isConnected=", _sslSocket.isConnected, ", result=", result);

        return result;
    }

    final void throwConnectError(int errorRawCode, string errorRawMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        version (TraceFunction) traceFunction("errorRawCode=", errorRawCode, ", errorRawMessage=", errorRawMessage);

        if (auto log = logger)
            log.errorf("%s.%s() - %s", forLogInfo(), funcName, errorRawMessage);

        auto msg = DbMessage.eConnect.fmtMessage(connectionStringBuilder.forErrorInfo(), errorRawMessage);
        throw createConnectError(errorRawCode, msg, next, funcName, file, line);
    }

    final void throwReadDataError(int errorRawCode, string errorRawMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        version (TraceFunctionReader) traceFunction("errorRawCode=", errorRawCode, ", errorRawMessage=", errorRawMessage);

        if (auto log = logger)
            log.errorf("%s.%s() - %s", forLogInfo(), funcName, errorRawMessage);

        auto msg = DbMessage.eReadData.fmtMessage(connectionStringBuilder.forErrorInfo(), errorRawMessage);
        throw createReadDataError(errorRawCode, msg, next, funcName, file, line);
    }

    final void throwWriteDataError(int errorRawCode, string errorRawMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        version (TraceFunctionWriter) traceFunction("errorRawCode=", errorRawCode, ", errorRawMessage=", errorRawMessage);

        if (auto log = logger)
            log.errorf("%s.%s() - %s", forLogInfo(), funcName, errorRawMessage);

        auto msg = DbMessage.eWriteData.fmtMessage(connectionStringBuilder.forErrorInfo(), errorRawMessage);
        throw createWriteDataError(errorRawCode, msg, next, funcName, file, line);
    }

protected:
    final bool canWriteDisconnectMessage() const nothrow pure @safe
    {
        return !isFatalError && socketActive;
    }

    SkException createConnectError(int socketErrorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        return new SkException(DbErrorCode.connect, errorMessage, null, socketErrorCode, 0, next, funcName, file, line);
    }

    SkException createReadDataError(int socketErrorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        return new SkException(DbErrorCode.read, errorMessage, null, socketErrorCode, 0, next, funcName, file, line);
    }

    SkException createWriteDataError(int socketErrorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        return new SkException(DbErrorCode.write, errorMessage, null, socketErrorCode, 0, next, funcName, file, line);
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
        disposeSocketBufferFilters(disposingReason);
        disposeSocketReadBuffer(disposingReason);
        disposeSocketWriteBuffers(disposingReason);
        _sslSocket.dispose(disposingReason);
        static if (!usePhamIOSocket)
        {
            if (_socket !is null && _socket.handle != socket_t.init)
                _socket.close();
        }
        else
        {
            if (_socket !is null)
                _socket.close();
        }
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
        version (TraceFunction) traceFunction();

        disposeSocket(DisposingReason.other);
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        super.doDispose(disposingReason);
        disposeSocket(disposingReason);
    }

    final void doOpenSocket() @trusted
    {
        version (TraceFunction) traceFunction();

        disposeSocket(DisposingReason.other);

        auto useCSB = skConnectionStringBuilder;

        if (useCSB.encrypt != DbEncryptedConnection.disabled)
            setSSLSocketOptions();

        static if (!usePhamIOSocket)
        {
            try
            {
                auto address = useCSB.toConnectAddress();
                _socket = new Socket(address.addressFamily, SocketType.STREAM, ProtocolType.TCP);
                _socket.connect(address);
                setSocketOptions();
            }
            catch (Exception e)
            {
                auto socketErrorMsg = e.msg;
                auto socketErrorCode = lastSocketError();
                throwConnectError(socketErrorCode, socketErrorMsg, e);
            }
        }
        else
        {
            _socket = new Socket(useCSB.toConnectInfo());
            if (_socket.lastError.isError)
            {
                auto errorCode = _socket.lastError.errorCode;
                auto errorMessage = _socket.lastError.errorMessage;
                auto funcName = _socket.lastError.funcName;
                auto file = _socket.lastError.file;
                auto line = _socket.lastError.line;
                _socket = null;
                throwConnectError(errorCode, errorMessage, null, funcName, file, line);
            }
        }
        assert(_socket.isAlive());
    }

    static if (!usePhamIOSocket)
    void setSocketOptions() @safe
    {
        version (TraceFunctionReader) traceFunction();

        auto useCSB = skConnectionStringBuilder;

        socket.blocking = useCSB.blocking;
        socket.setOption(SocketOptionLevel.SOCKET, SocketOption.TCP_NODELAY, useCSB.noDelay ? 1 : 0);
        if (auto n = useCSB.receiveTimeout)
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, n);
        if (auto n = useCSB.sendTimeout)
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, n);
    }

    void setSSLSocketOptions() @safe
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

    static if (!usePhamIOSocket)
    final Address toConnectAddress() const
    {
        const sn = serverName;
        return (sn.simpleIndexOf(':') >= 0 || (sn.length && sn[0] == '['))
            ? new Internet6Address(sn, serverPort)
            : new InternetAddress(sn, serverPort);    
    }
    
    static if (usePhamIOSocket)
    final ConnectInfo toConnectInfo() const nothrow
    {
        auto result = ConnectInfo(serverName, serverPort);
        result.blocking = blocking;
        result.noDelay = noDelay;
        result.connectTimeout = connectionTimeout;
        result.readTimeout = receiveTimeout;
        result.writeTimeout = sendTimeout;
        
        return result;
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
        scope (failure) assert(0, "Assume nothrow failed");
        
        auto result = super.getDefault(name);
        if (result.length == 0)
        {
            auto n = DbIdentitier(name);
            result = skDefaultConnectionParameterValues.get(n, null);
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

        //import pham.utl.utl_test; dgWriteln("nOffset=", nOffset, ", _data.length=", _data.length, ", additionalBytes=", additionalBytes.dgToHex(), ", length=", length);

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
                traceFunction("counter=", readCounter, ", read_length=", n, ", read_data=", readBytes.dgToHex(), ", _offset=", _offset, ", _maxlength=", _maxLength);
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
            traceFunction("counter=", flushCounter, ", length=", flushBytes.length, ", data=", flushBytes.dgToHex());
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
    @disable void opAssign(typeof(this));

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
