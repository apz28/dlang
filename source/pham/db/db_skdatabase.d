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

version = pham_io_socket;

import std.conv : to;

version(pham_io_socket)
{
    import pham.io.io_socket;
    import pham.io.io_socket_error : needResetSocket;
}
else
{
    import std.socket : Address, AddressFamily, InternetAddress, Internet6Address,
        ProtocolType, Socket, SocketException, SocketShutdown, SocketOption, SocketOptionLevel, SocketSet, SocketType,
        socket_t;
    import pham.io.io_socket_error;
    import pham.utl.utl_text : simpleIndexOf;
}

debug(debug_pham_db_db_skdatabase) import pham.db.db_debug;
version(profile) import pham.utl.utl_test : PerfFunction;
import pham.cp.cp_openssl;
import pham.utl.utl_array_dictionary;
import pham.utl.utl_disposable : DisposingReason, isDisposing;
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

static immutable DbDefaultConnectionParameterValues skDefaultConnectionParameterValues;

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
        version(pham_io_socket)
            return _socket !is null && _socket.active;
        else
            return _socket !is null && _socket.handle != socket_t.init;
    }

    pragma(inline, true)
    @property final bool socketSSLActive() const nothrow pure @safe
    {
        return socketActive && _sslSocket.isConnected;
    }

package(pham.db):
    final DbReadBuffer acquireSocketReadBuffer(size_t capacity = DbDefault.socketReadBufferLength) nothrow @safe
    {
        debug(debug_pham_db_db_skdatabase) debug writeln(__FUNCTION__, "(capacity=", capacity, ")");

        if (_socketReadBuffer is null)
            _socketReadBuffer = createSocketReadBuffer(capacity);
        return _socketReadBuffer;
    }

    final DbWriteBuffer acquireSocketWriteBuffer(size_t capacity = DbDefault.socketWriteBufferLength) nothrow @safe
    {
        debug(debug_pham_db_db_skdatabase) debug writeln(__FUNCTION__, "(capacity=", capacity, ")");

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
        debug(debug_pham_db_db_skdatabase) debug writeln(__FUNCTION__, "()");

        if (!isDisposing(lastDisposingReason))
            _socketWriteBuffers.insertEnd(item.reset());
    }

    debug(debug_pham_db_db_skdatabase) static size_t socketReadDataCounter;
    final size_t socketReadData(ubyte[] data) @trusted
    {
        debug(debug_pham_db_db_skdatabase) debug writeln(__FUNCTION__, "()", " - counter=", ++socketReadDataCounter,
            ", _sslSocket.isConnected=", _sslSocket.isConnected);
        version(profile) debug auto p = PerfFunction.create();

        size_t result;
        if (_sslSocket.isConnected)
        {
            const rs = _sslSocket.receive(data, result);
            if (rs.isError)
                throwReadDataError(rs.errorCode, rs.errorMessage);
        }
        else
        {
            version(pham_io_socket)
            {
                const rs = _socket.receive(data);
                if ((rs < 0) || (rs == 0 && data.length != 0))
                {
                    auto msg = _socket.lastError.errorMessage;
                    if (msg.length == 0)
                        msg = DbMessage.eNoReadingData.fmtMessage(cast(int)data.length);
                    throwReadDataError(_socket.lastError.errorCode, msg);
                }
                result = cast(size_t)(rs);
            }
            else
            {
                result = _socket.receive(data);
                if ((result == Socket.ERROR) || (result == 0 && data.length != 0))
                {
                    auto status = lastSocketError("receive", DbMessage.eNoReadingData.fmtMessage(cast(int)data.length));
                    throwReadDataError(status.errorCode, status.errorMessage);
                }
            }
        }

        if (result > 0 && _socketReadBufferFilters !is null)
        {
            ubyte[] filteredData = data[0..result];
            for (auto nextFilter = _socketReadBufferFilters; nextFilter !is null; nextFilter = nextFilter.next)
            {
                debug(debug_pham_db_db_skdatabase) debug writeln("\t", "filter=", nextFilter.processName,
                    ", length=", filteredData.length, ", data=", filteredData.dgToHex());

                if (!nextFilter.process(filteredData, filteredData))
                    throwReadDataError(nextFilter.errorCode, nextFilter.errorMessage);

                debug(debug_pham_db_db_skdatabase) debug writeln("\t", "filter=", nextFilter.processName,
                    ", length=", filteredData.length, ", data=", filteredData.dgToHex());
            }
            // TODO check for data.length - expand it?
            result = filteredData.length;
            data[0..result] = filteredData[0..result];

            debug(debug_pham_db_db_skdatabase) debug writeln("\t", "data=", data[0..result].dgToHex());
        }

        return result;
    }

    debug(debug_pham_db_db_skdatabase) static size_t socketWriteDataCounter;
    final size_t socketWriteData(scope const(ubyte)[] data) @trusted
    {
        debug(debug_pham_db_db_skdatabase) debug writeln(__FUNCTION__, "()", " - counter=", ++socketWriteDataCounter,
            ", _sslSocket.isConnected=", _sslSocket.isConnected, ", data=", data.dgToHex());

        const(ubyte)[] sendingData;

        if (data.length && _socketWriteBufferFilters !is null)
        {
            bool firstFilter = true;
            ubyte[] filteredData;
            for (auto nextFilter = _socketWriteBufferFilters; nextFilter !is null; nextFilter = nextFilter.next)
            {
                debug(debug_pham_db_db_skdatabase)
                {
                    const(ubyte)[] logData = firstFilter ? data : filteredData;
                    debug writeln("\t", "filter=", nextFilter.processName, ", length=", logData.length,
                        ", data=", logData.dgToHex());
                }

                if (!nextFilter.process(firstFilter ? data : filteredData, filteredData))
                    throwWriteDataError(nextFilter.errorCode, nextFilter.errorMessage);

                debug(debug_pham_db_db_skdatabase) debug writeln("\t", "filter=", nextFilter.processName,
                    ", length=", filteredData.length, ", data=", filteredData.dgToHex());

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
            version(pham_io_socket)
            {
                const rs = _socket.send(sendingData);
                if (rs < 0 || rs != sendingData.length)
                {
                    auto msg = _socket.lastError.errorMessage;
                    if (msg.length == 0)
                        msg = DbMessage.eNoSendingData.fmtMessage(cast(int)sendingData.length);
                    throwWriteDataError(_socket.lastError.errorCode, msg);
                }
                result = cast(size_t)(rs);
            }
            else
            {
                result = _socket.send(sendingData);
                if (result == Socket.ERROR || result != sendingData.length)
                {
                    auto status = lastSocketError("send", DbMessage.eNoSendingData.fmtMessage(cast(int)sendingData.length));
                    throwWriteDataError(status.errorCode, status.errorMessage);
                }
            }
        }

        debug(debug_pham_db_db_skdatabase) debug writeln("\t", "_sslSocket.isConnected=", _sslSocket.isConnected, ", result=", result);

        return result;
    }

    final noreturn throwConnectError(const(int) rawErrorCode, string rawErrorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_skdatabase) debug writeln(__FUNCTION__, "(rawErrorCode=", rawErrorCode,
            ", rawErrorMessage=", rawErrorMessage, ", funcName=", funcName, ")");

        if (auto log = canErrorLog())
            log.errorf("%s.%s() - %s", forLogInfo(), funcName, rawErrorMessage);

        auto msg = DbMessage.eConnect.fmtMessage(connectionStringBuilder.forErrorInfo(), rawErrorMessage);
        throw createConnectError(rawErrorCode, msg, next, funcName, file, line);
    }

    final noreturn throwReadDataError(const(int) rawErrorCode, string rawErrorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_skdatabase) debug writeln(__FUNCTION__, "(rawErrorCode=", rawErrorCode,
            ", rawErrorMessage=", rawErrorMessage, ", funcName=", funcName, ")");

        if (auto log = canErrorLog())
            log.errorf("%s.%s() - %s", forLogInfo(), funcName, rawErrorMessage);

        auto msg = DbMessage.eReadData.fmtMessage(connectionStringBuilder.forErrorInfo(), rawErrorMessage);

        if (needResetSocket(rawErrorCode))
            fatalError(FatalErrorReason.readData, state);

        throw createReadDataError(rawErrorCode, msg, next, funcName, file, line);
    }

    final noreturn throwWriteDataError(const(int) rawErrorCode, string rawErrorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @safe
    {
        debug(debug_pham_db_db_skdatabase) debug writeln(__FUNCTION__, "(rawErrorCode=", rawErrorCode,
            ", rawErrorMessage=", rawErrorMessage, ", funcName=", funcName, ")");

        if (auto log = canErrorLog())
            log.errorf("%s.%s() - %s", forLogInfo(), funcName, rawErrorMessage);

        auto msg = DbMessage.eWriteData.fmtMessage(connectionStringBuilder.forErrorInfo(), rawErrorMessage);

        if (needResetSocket(rawErrorCode))
            fatalError(FatalErrorReason.writeData, state);

        throw createWriteDataError(rawErrorCode, msg, next, funcName, file, line);
    }

protected:
    final bool canWriteDisconnectMessage() const nothrow @safe
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

    DbReadBuffer createSocketReadBuffer(size_t capacity = DbDefault.socketReadBufferLength) nothrow @safe
    {
        return new SkReadBuffer(this, capacity);
    }

    DbWriteBuffer createSocketWriteBuffer(size_t capacity = DbDefault.socketWriteBufferLength) nothrow @safe
    {
        return new SkWriteBuffer(this, capacity);
    }

    final void disposeSocket(const(DisposingReason) disposingReason, const(bool) includeShutdown) nothrow @safe
    {
        disposeSocketBufferFilters(disposingReason);
        disposeSocketReadBuffer(disposingReason);
        disposeSocketWriteBuffers(disposingReason);
        _sslSocket.dispose(disposingReason);
        if (_socket !is null)
        {
            version(pham_io_socket)
            {
                if (_socket.active)
                {
                    if (includeShutdown)
                        _socket.shutdown();
                    _socket.close();
                }
            }
            else
            {
                if (_socket.handle != socket_t.init)
                {
                    if (includeShutdown)
                        _socket.shutdown(SocketShutdown.BOTH);
                    _socket.close();
                }
            }
            _socket = null;
        }
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

    override void doCloseImpl(const(DbConnectionState) reasonState) nothrow @safe
    {
        debug(debug_pham_db_db_skdatabase) debug writeln(__FUNCTION__, "(reasonState=", reasonState, ", socketActive=", socketActive, ")");

        const isFailing = isFatalError || reasonState == DbConnectionState.failing;

        disposeSocket(DisposingReason.other, !isFailing);
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        super.doDispose(disposingReason);
        disposeSocket(disposingReason, false);
    }

    final void doOpenSocket() @trusted
    {
        debug(debug_pham_db_db_skdatabase) debug writeln(__FUNCTION__, "()");

        disposeSocket(DisposingReason.other, true);

        auto useCSB = skConnectionStringBuilder;

        if (useCSB.encrypt != DbEncryptedConnection.disabled)
            setSSLSocketOptions();

        version(pham_io_socket)
        {
            _socket = new Socket(useCSB.toConnectInfo());
            if (_socket.lastError.isError)
            {
                auto errorCode = _socket.lastError.errorCode;
                auto errorMessage = _socket.lastError.errorMessage;
                auto funcName = _socket.lastError.funcName;
                auto file = _socket.lastError.file;
                auto line = _socket.lastError.line;
                throwConnectError(errorCode, errorMessage, null, funcName, file, line);
            }
        }
        else
        {
            try
            {
                auto address = useCSB.toConnectAddress();
                _socket = new Socket(address.addressFamily, SocketType.STREAM, ProtocolType.TCP);
                setSocketOptions(_socket);
                doConnectSocket(_socket, address);
            }
            catch (Exception e)
            {
                if (cast(SkException)e)
                    throw e;
                else if (cast(SocketException)e)
                {
                    auto socketErrorMsg = e.msg;
                    auto socketErrorCode = lastSocketError();
                    throwConnectError(socketErrorCode, socketErrorMsg, e);
                }
                else
                    throwConnectError(0, e.msg, e);
            }
        }
        assert(_socket.isAlive());
    }

    version(pham_io_socket)
    {}
    else
    {
        void doConnectSocket(Socket socket, ref Address address) @safe
        {
            debug(debug_pham_db_db_skdatabase) debug writeln(__FUNCTION__, "()");

            auto useCSB = skConnectionStringBuilder;
            if (auto n = useCSB.connectionTimeout)
            {
                auto writeSet = new SocketSet();
                writeSet.add(socket.handle);
                socket.blocking = false;
                socket.connect(address);
                const r = socket.select(null, writeSet, null, n);
                socket.blocking = useCSB.blocking;
                if (r != 1 || !writeSet.isSet(socket.handle))
                    throwConnectError(0, DbMessage.eConnectTimeoutRaw);
            }
            else
                socket.connect(address);
        }

        void setSocketOptions(Socket socket) @safe
        {
            debug(debug_pham_db_db_skdatabase) debug writeln(__FUNCTION__, "()");

            auto useCSB = skConnectionStringBuilder;

            socket.blocking = useCSB.blocking;
            socket.setOption(SocketOptionLevel.SOCKET, SocketOption.TCP_NODELAY, useCSB.noDelay ? 1 : 0);
            if (auto n = useCSB.receiveTimeout)
                socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, n);
            if (auto n = useCSB.sendTimeout)
                socket.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, n);
        }
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

    version(pham_io_socket)
    {
        final ConnectInfo toConnectInfo() nothrow
        {
            auto result = ConnectInfo(serverName, serverPort);
            result.blocking = blocking;
            result.noDelay = noDelay;
            result.connectTimeout = connectionTimeout;
            result.readTimeout = receiveTimeout;
            result.writeTimeout = sendTimeout;

            return result;
        }
    }
    else
    {
        final Address toConnectAddress()
        {
            const sn = serverName;
            return (sn.simpleIndexOf(':') >= 0 || (sn.length && sn[0] == '['))
                ? new Internet6Address(sn, serverPort)
                : new InternetAddress(sn, serverPort);
        }
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
        auto setValue = value >= -1 ? value.to!string() : getDefault(DbConnectionParameterIdentifier.socketSslVerificationMode);
        put(DbConnectionParameterIdentifier.socketSslVerificationMode, setValue);
        return this;
    }

protected:
    override string getDefault(string name) const nothrow
    {
        auto k = name in skDefaultConnectionParameterValues;
        return k !is null && (*k).def.length != 0 ? (*k).def : super.getDefault(name);
    }

    override void setDefaultIfs()
    {
        foreach (ref dpv; skDefaultConnectionParameterValues.byKeyValue)
        {
            auto def = dpv.value.def;
            if (def.length)
                putIf(dpv.key, def);
        }
        super.setDefaultIfs();
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
        debug(debug_pham_db_db_skdatabase) readCounter = 0;
    }

    debug(debug_pham_db_db_skdatabase) static size_t readCounter = 0;
    final override void fill(const(size_t) additionalBytes, bool mustSatisfied)
    {
        version(profile) debug auto p = PerfFunction.create();

        if (_offset && (_offset + additionalBytes) > _data.length)
            mergeOffset();

        reserve(additionalBytes);
        const nOffset = _offset + length;

        debug(debug_pham_db_db_skdatabase) { debug writeln(__FUNCTION__, "(nOffset=", nOffset, ", _data.length=", _data.length,
            ", additionalBytes=", additionalBytes.dgToHex(), ", length=", length, ")"); }

        // n=size_t.max -> no data returned
        const n = connection.socketReadData(_data[nOffset.._data.length]);
        const hasReadData = n != size_t.max;
        if (hasReadData)
        {
            _maxLength += n;

            debug(debug_pham_db_db_skdatabase) { readCounter++; const readBytes = _data[nOffset..nOffset + n];
                debug writeln("\t", "counter=", readCounter, ", read_length=", n, ", read_data=", readBytes.dgToHex(), ", _offset=", _offset, ", _maxlength=", _maxLength); }
        }

        if (mustSatisfied && (!hasReadData || n < additionalBytes))
        {
            auto msg = DbMessage.eNoReadingDataRemaining.fmtMessage(additionalBytes, hasReadData ? n : 0);
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
        debug(debug_pham_db_db_skdatabase) flushCounter = 0;
    }

    debug(debug_pham_db_db_skdatabase) static size_t flushCounter = 0;
    override void flush()
    {
        auto flushBytes = peekBytes();

        debug(debug_pham_db_db_skdatabase) { flushCounter++;
            debug writeln(__FUNCTION__, "() - counter=", flushCounter, ", length=", flushBytes.length, ", data=", flushBytes.dgToHex()); }

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

version(UnitTestSocketFailure)
{
    int unitTestSocketFailure;
}


// Any below codes are private
private:

shared static this() nothrow @safe
{
    skDefaultConnectionParameterValues = () nothrow pure @trusted // @trusted=cast()
    {
        auto result = DbDefaultConnectionParameterValues(10, 5);

        result[DbConnectionParameterIdentifier.packageSize] = DbConnectionParameterInfo(&isConnectionParameterComputingSize, "16_384", 4_096, 4_096*64);
        result[DbConnectionParameterIdentifier.socketBlocking] = DbConnectionParameterInfo(&isConnectionParameterBool, dbBoolTrue, dbConnectionParameterNullMin, dbConnectionParameterNullMax);
        result[DbConnectionParameterIdentifier.socketNoDelay] = DbConnectionParameterInfo(&isConnectionParameterBool, dbBoolTrue, dbConnectionParameterNullMin, dbConnectionParameterNullMax);
        result[DbConnectionParameterIdentifier.socketSslVerificationHost] = DbConnectionParameterInfo(&isConnectionParameterBool, dbBoolFalse, dbConnectionParameterNullMin, dbConnectionParameterNullMax);
        result[DbConnectionParameterIdentifier.socketSslVerificationMode] = DbConnectionParameterInfo(&isConnectionParameterInt32, "-1", -1, 100); // -1=Ignore

        debug(debug_pham_db_db_skdatabase) if (result.maxCollision) debug writeln(__FUNCTION__, "(result.maxCollision=", result.maxCollision,
            ", result.collisionCount=", result.collisionCount, ", result.capacity=", result.capacity, ", result.length=", result.length, ")");

        return cast(immutable(DbDefaultConnectionParameterValues))result;
    }();
}
