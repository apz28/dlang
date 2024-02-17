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

module pham.io.io_socket;

import core.time : Duration;

import pham.utl.utl_result : resultError, resultOK;
public import pham.utl.utl_result : ResultIf, ResultStatus;
public import pham.io.io_socket_type;
import pham.io.io_stream : Stream;
public import pham.io.io_type;
version(Posix)
{
    import core.sys.posix.sys.socket;
    import pham.io.io_socket_posix;
}
else version(Windows)
{
    import core.sys.windows.winsock2;
    import pham.io.io_socket_windows;
}
else
    pragma(msg, "Unsupported system for " ~ __MODULE__);

@safe:

ResultIf!(AddressInfo[]) getAddressInfo(scope const(char)[] hostNameOrAddress, scope const(char)[] serviceNameOrPort,
    AddressInfo hints) nothrow @trusted
{
    import std.internal.cstring : tempCString;
    import std.conv : to;

    addrinfo* lpres;
    auto lphostNameOrAddress = hostNameOrAddress.tempCString();
    auto lpserviceNameOrPort = serviceNameOrPort.tempCString();
    auto lpcanonName = hints.canonName.tempCString();
    addrinfo lphints;
    const hasHints = hints != AddressInfo.init;
    if (hasHints)
    {
        lphints.ai_flags = hints.flags;
        lphints.ai_family = hints.family;
        lphints.ai_socktype = hints.type;
        lphints.ai_protocol = hints.protocol;
        lphints.ai_canonname = lpcanonName.buffPtr;
    }

    const r = getaddrinfo(lphostNameOrAddress, lpserviceNameOrPort, hasHints ? &lphints : null, &lpres);
    if (r != resultOK)
        return ResultIf!(AddressInfo[]).systemError("getaddrinfo", lastSocketError());
    scope (exit)
        freeaddrinfo(lpres);

    AddressInfo[] addressInfos;
    addressInfos.reserve(10);
    for (const(addrinfo)* res = lpres; res; res = res.ai_next)
    {
        auto sa = SocketAddress(res.ai_addr, res.ai_addrlen);
        AddressInfo addressInfo;
        addressInfo.canonName = res.ai_canonname ? res.ai_canonname.to!string() : null;
        addressInfo.family = cast(AddressFamily)res.ai_family;
        addressInfo.type = cast(SocketType)res.ai_socktype;
        addressInfo.protocol = cast(Protocol)res.ai_protocol;
        addressInfo.flags = res.ai_flags;
        addressInfo.address = sa.toIPAddress();
        addressInfo.port = sa.port;
        addressInfos ~= addressInfo;
    }
    return ResultIf!(AddressInfo[]).ok(addressInfos);
}

class Socket
{
@safe:

public:
    this() nothrow
    {
        this._handle = invalidSocketHandle;
    }

    this(BindInfo bindInfo) nothrow
    {
        this._handle = invalidSocketHandle;
        this.bind(bindInfo);
    }

    this(ConnectInfo connectInfo) nothrow
    {
        this._handle = invalidSocketHandle;
        this.connect(connectInfo);
    }

    this(SocketHandle handle, IPAddress address, ushort port) nothrow pure
    {
        this._handle = handle;
        this._address = address;
        this._port = port;
    }

    ~this() nothrow
    {
        close(true);
    }

    final int accept(out SocketHandle peerHandle, out SocketAddress peerAddress) nothrow @trusted
    {
        if (!active)
        {
            peerHandle = invalidSocketHandle;
            peerAddress = SocketAddress.init;
            return lastError.setError(ENOTCONN, " inactive - need bind() and listen()");
        }

        ubyte[SocketAddress.sizeof] addrBuffer;
        int addrLength = SocketAddress.sizeof;
        peerHandle = acceptSocket(_handle, cast(sockaddr*)&addrBuffer[0], &addrLength);
        if (peerHandle == invalidSocketHandle)
        {
            peerAddress = SocketAddress.init;
            return lastError.setError(lastSocketError());
        }

        setBlockingSocket(peerHandle, blocking);
        peerAddress = SocketAddress(addrBuffer[0..addrLength]);
        return resultOK;
    }

    final int accept(out Socket peerSocket) nothrow
    {
        SocketHandle peerHandle;
        SocketAddress peerAddress;
        const result = accept(peerHandle, peerAddress);
        peerSocket = result == resultOK
            ? new Socket(peerHandle, peerAddress.toIPAddress(), peerAddress.port)
            : null;
        return result;
    }

    final int availableBytes() nothrow
    {
        if (!active)
            return lastError.setError(ENOTCONN, " inactive socket");

        const result = getAvailableBytesSocket(_handle);
        return result >= 0 ? result : lastError.setSystemError(getAvailableBytesSocketAPI(), lastSocketError());
    }

    final int bind(BindInfo bindInfo) nothrow
    {
        if (active && port != 0)
            return lastError.setError(EISCONN, " already active");

        if (bindInfo.needResolveHostName)
        {
            auto addressInfos = getAddressInfo(bindInfo.resolveHostName(),
                bindInfo.resolveServiceName(), bindInfo.resolveHostHints);
            if (addressInfos.isError)
            {
                this._handle = invalidSocketHandle;
                this.lastError = addressInfos.status;
                return resultError;
            }
            int r;
            foreach (ref ai; addressInfos.value)
            {
                BindInfo bi = bindInfo;
                bi.address = ai.address;
                if (bi.type == SocketType.unspecified)
                    bi.type = ai.type;
                if (bi.port == 0)
                    bi.port = ai.port;
                r = bindImpl(bi);
                if (r == resultOK)
                {
                    lastError.reset();
                    break;
                }
            }
            return r;
        }
        else
        {
            return bindImpl(bindInfo);
        }
    }

    final int bind(IPAddress address, ushort port) nothrow
    {
        auto bindInfo = BindInfo(address, port);
        return bind(bindInfo);
    }

    final int bind(string hostName, ushort port) nothrow
    {
        auto bindInfo = BindInfo(hostName, port);
        return bind(bindInfo);
    }

    final int connect(ConnectInfo connectInfo) nothrow
    {
        //import std.stdio : writeln; debug writeln("connect(hostname=", connectInfo.hostName, ", port=", connectInfo.port, ")");

        if (active && port != 0)
            return lastError.setError(EISCONN, " already active");

        if (connectInfo.needResolveHostName)
        {
            auto addressInfos = getAddressInfo(connectInfo.resolveHostName(),
                connectInfo.resolveServiceName(), connectInfo.resolveHostHints);
            if (addressInfos.isError)
            {
                this._handle = invalidSocketHandle;
                this.lastError = addressInfos.status;
                return resultError;
            }
            foreach (ref ai; addressInfos.value)
            {
                ConnectInfo ci = connectInfo;
                ci.address = ai.address;
                if (ci.type == SocketType.unspecified)
                    ci.type = ai.type;
                if (ci.port == 0)
                    ci.port = ai.port;
                if (connectImpl(ci) == resultOK)
                {
                    lastError.reset();
                    return resultOK;
                }
            }
            return resultError;
        }
        else
        {
            return connectImpl(connectInfo);
        }
    }

    final int connect(IPAddress address, ushort port) nothrow
    {
        auto connectInfo = ConnectInfo(address, port);
        return connect(connectInfo);
    }

    final int connect(IPAddress[] addresses, ushort port) nothrow
    {
        if (active && port != 0)
            return lastError.setError(EISCONN, " already active");
            
        foreach (ref a; addresses)
        {
            auto connectInfo = ConnectInfo(a, port);
            if (connect(connectInfo) == resultOK)
                return resultOK;
        }

        if (addresses.length != 0)
            return resultError;

        return lastError.setError(0, " missing IPAddress");
    }

    final int connect(string hostName, ushort port) nothrow
    {
        auto connectInfo = ConnectInfo(hostName, port);
        return connect(connectInfo);
    }

    final int close(const(bool) destroying = false) nothrow scope
    {
        if (_handle == invalidSocketHandle)
            return resultOK;

        if (!destroying)
            shutdown(ShutdownReason.both);

        return internalClose(!destroying);
    }

    final int create(AddressFamily family, SocketType type, Protocol protocol) nothrow
    {
        if (active)
            return lastError.setError(EISCONN, " already active");
    
        this._address = IPAddress.init;
        this._port = 0;
        version(Windows) this._blocking = true; // Default in windows  
        this._handle = createSocket(family, type, protocol);
        if (this._handle == invalidSocketHandle)
            return lastError.setSystemError("socket", lastSocketError());
            
        return resultOK;
    }
    
    final bool isAlive() nothrow
    {
        int type;
        return active && getIntOptionSocket(_handle, SOL_SOCKET, SO_TYPE, type) == resultOK;
    }

    pragma(inline, true)
    static bool isError(int r) nothrow pure
    {
        return r < 0;
    }

    pragma(inline, true)
    static bool isError(SocketHandle r) nothrow pure
    {
        return r == invalidSocketHandle;
    }

    pragma(inline, true)
    static bool isError(SelectMode r) nothrow pure
    {
        return r == SelectMode.none;
    }

    pragma(inline, true)
    static bool isError(long r) nothrow pure
    {
        return r < 0;
    }

    static bool isSupport(AddressFamily family) nothrow
    {
        auto h = createSocket(family, SocketType.dgram, Protocol.ip);
        scope (exit)
        {
            if (h != invalidSocketHandle)
                closeSocket(h);
        }
        if (h != invalidSocketHandle)
            return true;
        const e = lastSocketError();
        return e != EAFNOSUPPORT && e != EPROTONOSUPPORT;
    }

    static bool isSupportIPv4() nothrow
    {
        return isSupport(AddressFamily.ipv4);
    }

    static bool isSupportIPv6() nothrow
    {
        return isSupport(AddressFamily.ipv6);
    }

    final int listen(uint backLog) nothrow
    {
        if (!active)
            return lastError.setError(ENOTCONN, " inactive - need bind()");

        return listenSocket(_handle, backLog) == resultOK
            ? resultOK
            : lastError.setSystemError("listen", lastSocketError());
    }

    final SocketAddress localAddress() nothrow @trusted
    {
        if (!active)
        {
            lastError.setError(ENOTCONN, " inactive - need connect() or bind()");
            return SocketAddress.init;
        }

        ubyte[SocketAddress.sizeof] addrBuffer;
        int addrLength = SocketAddress.sizeof;
        const r = getsockname(_handle, cast(sockaddr*)&addrBuffer[0], &addrLength);
        if (r != resultOK)
        {
            lastError.setSystemError("getsockname", lastSocketError());
            return SocketAddress.init;
        }

        return SocketAddress(addrBuffer[0..addrLength]);
    }

    final SocketAddress remoteAddress() nothrow @trusted
    {
        if (!active)
        {
            lastError.setError(ENOTCONN, " inactive - need connect() or accept()");
            return SocketAddress.init;
        }

        ubyte[SocketAddress.sizeof] addrBuffer;
        int addrLength = SocketAddress.sizeof;
        const r = getpeername(_handle, cast(sockaddr*)&addrBuffer[0], &addrLength);
        if (r != resultOK)
        {
            lastError.setSystemError("getpeername", lastSocketError());
            return SocketAddress.init;
        }

        return SocketAddress(addrBuffer[0..addrLength]);
    }

    final long receive(scope ubyte[] bytes) nothrow
    {
        if (const r = checkActive())
            return r;

        return bytes.length == 0 ? 0L : receiveImpl(bytes);
    }

    final SelectMode select(SelectMode modes, Duration timeout) nothrow
    {
        const r = selectSocket(_handle, modes, toSocketTimeVal(timeout));
        if (r <= 0 || (r & SelectMode.error) == SelectMode.error)
            lastError.setSystemError(selectSocketAPI(), lastSocketError());
        return r <= 0 ? SelectMode.none : cast(SelectMode)r;
    }

    final long send(scope const(ubyte)[] bytes) nothrow
    {
        if (const r = checkActive())
            return r;

        return bytes.length == 0 ? 0L : sendImpl(bytes);
    }

    final int setBlocking(bool state) nothrow
    {
        const r = setBlockingSocket(_handle, state);
        return r == resultOK ? resultOK : lastError.setSystemError(setBlockingSocketAPI(), lastSocketError(), " blocking");
    }

    final int setDebug(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.debug_, v);
        return r == resultOK ? resultOK : lastError.setSystemError(setIntOptionSocketAPI(), lastSocketError(), " debug");
    }

    final int setDontRoute(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.dontRoute, v);
        return r == resultOK ? resultOK : lastError.setSystemError(setIntOptionSocketAPI(), lastSocketError(), " dontRoute");
    }

    final int setIPv6Only(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, IPPROTO_IPV6, IPV6_V6ONLY, v);
        return r == resultOK ? resultOK : lastError.setSystemError(setIntOptionSocketAPI(), lastSocketError(), " ipv6Only");
    }

    final int setKeepAlive(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.keepAlive, v);
        return r == resultOK ? resultOK : lastError.setSystemError(setIntOptionSocketAPI(), lastSocketError(), " keepAlive");
    }

    final int setLinger(Linger linger) nothrow
    {
        const r = setLingerSocket(_handle, linger);
        return r == resultOK ? resultOK : lastError.setSystemError(setLingerSocketAPI(), lastSocketError(), " linger");
    }

    final int setNoDelay(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, IPPROTO_TCP, TCP_NODELAY, v);
        return r == resultOK ? resultOK : lastError.setSystemError(setIntOptionSocketAPI(), lastSocketError(), " noDelay");
    }

    final int setReadTimeout(Duration duration) nothrow
    {
        const r = setReadTimeoutSocket(_handle, toSocketTimeVal(duration));
        return r == resultOK? resultOK : lastError.setSystemError(setTimeoutSocketAPI(), lastSocketError(), " readTimeout");
    }

    final int setReceiveBufferSize(uint bytes) nothrow
    {
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.receiveBufferSize, bytes);
        return r == resultOK ? resultOK : lastError.setSystemError(setIntOptionSocketAPI(), lastSocketError(), " receiveBufferSize");
    }

    final int setReuseAddress(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.reuseAddress, v);
        return r == resultOK ? resultOK : lastError.setSystemError(setIntOptionSocketAPI(), lastSocketError(), " reuseAddress");
    }

    final int setSendBufferSize(uint bytes) nothrow
    {
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.sendBufferSize, bytes);
        return r == resultOK ? resultOK : lastError.setSystemError(setIntOptionSocketAPI(), lastSocketError(), " sendBufferSize");
    }

    final int setUseLoopback(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.useLoopBack, v);
        return r == resultOK ? resultOK : lastError.setSystemError(setIntOptionSocketAPI(), lastSocketError(), " useLoopback");
    }

    final int setWriteTimeout(Duration duration) nothrow
    {
        const r = setWriteTimeoutSocket(_handle, toSocketTimeVal(duration));
        return r == resultOK ? resultOK : lastError.setSystemError(setTimeoutSocketAPI(), lastSocketError(), " writeTimeout");
    }

    final int shutdown(ShutdownReason reason = ShutdownReason.both) nothrow scope
    {
        if (_handle == invalidSocketHandle)
            return resultOK;

        if (shutdownSocket(_handle, reason) == resultOK)
            return resultOK;

        return lastError.setSystemError("shutdown", lastSocketError());
    }

    pragma(inline, true)
    @property final bool active() const @nogc nothrow pure
    {
        return _handle != invalidSocketHandle;
    }

    @property final IPAddress address() const nothrow
    {
        return this._address;
    }

    @property final bool blocking() const @nogc nothrow
    {
        version(Windows)
            return _blocking;
        else
        {
            const r = getBlockingSocket(_handle);
            if (r < 0)
                lastError.setSystemError(getBlockingSocketAPI(), lastSocketError(), " blocking");
            return r == 1;
        }
    }

    pragma(inline, true)
    @property final SocketHandle handle() @nogc nothrow pure
    {
        return _handle;
    }

    @property final ushort port() const @nogc nothrow
    {
        return _port;
    }

public:
    ResultStatus lastError;

protected:
    final int bindImpl(BindInfo bindInfo) nothrow
    {
        version(Windows) this._blocking = bindInfo.isBlocking();
        this._address = bindInfo.address;
        this._port = bindInfo.port;
        
        if (this._handle == invalidSocketHandle)
        {
            this._handle = createSocket(bindInfo.family, bindInfo.type, bindInfo.protocol);
            if (this._handle == invalidSocketHandle)
            {
                const r = lastError.setSystemError("socket", lastSocketError());
                lastError.addMessageIf(bindInfo.toErrorInfo());
                return r;
            }
        }

        int bindFailed(string apiName, string optName) nothrow
        {
            const r = lastSocketError();
            internalClose(false);
            return lastError.setSystemError(apiName, r, optName);
        }

        // No need to check error for unimportant flag
        if (bindInfo.debug_)
            setDebug(true);

        if (setBlocking(bindInfo.isBlocking()) != resultOK)
            return bindFailed(setBlockingSocketAPI(), " blocking");

        if (bindInfo.dontRoute && setDontRoute(true) != resultOK)
            return bindFailed(setIntOptionSocketAPI(), " dontRoute");

        if (bindInfo.family == AddressFamily.ipv6 && bindInfo.ipv6Only && setIPv6Only(true) != resultOK)
            return bindFailed(setIntOptionSocketAPI(), " ipv6Only");

        if (bindInfo.protocol == Protocol.tcp && bindInfo.noDelay && setNoDelay(true) != resultOK)
            return bindFailed(setIntOptionSocketAPI(), " noDelay");

        if (bindInfo.reuseAddress && setReuseAddress(true) != resultOK)
            return bindFailed(setIntOptionSocketAPI(), " reuseAddress");

        // Non-standard so skip checking for error
        if (bindInfo.useLoopback)
            setUseLoopback(true);

        if (bindInfo.useLinger && setLinger(bindInfo.linger) != resultOK)
            return bindFailed(setLingerSocketAPI(), " linger");

        auto sa = bindInfo.address.toSocketAddress(bindInfo.port);
        if (bindSocket(this._handle, sa.sval, sa.slen) != resultOK)
            return bindFailed("bind", null);

        return resultOK;
    }

    pragma(inline, true)
    final int checkActive(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
    {
        return active
            ? lastError.reset()
            : lastError.setError(0, funcName, " with inactive socket", file, line);
    }

    final int connectImpl(ConnectInfo connectInfo) nothrow
    {
        //import std.stdio : writeln; debug writeln("connectImpl(address=", connectInfo.address.toString(), ", port=", connectInfo.port, ")");

        version(Windows) this._blocking = connectInfo.isBlocking();
        this._address = connectInfo.address;
        this._port = connectInfo.port;
                
        if (this._handle == invalidSocketHandle)
        {
            this._handle = createSocket(connectInfo.family, connectInfo.type, connectInfo.protocol);
            if (this._handle == invalidSocketHandle)
            {
                const r = lastError.setSystemError("socket", lastSocketError());
                lastError.addMessageIf(connectInfo.toErrorInfo());
                return r;
            }
        }

        int connectFailed(string apiName, string optName) nothrow
        {
            const r = lastSocketError();
            internalClose(false);
            return lastError.setSystemError(apiName, r, optName);
        }

        // No need to check error for unimportant flag
        if (connectInfo.debug_)
            setDebug(true);

        if (setBlocking(connectInfo.isBlocking()) != resultOK)
            return connectFailed(setBlockingSocketAPI(), " blocking");

        if (connectInfo.dontRoute && setDontRoute(true) != resultOK)
            return connectFailed(setIntOptionSocketAPI(), " dontRoute");

        if (connectInfo.family == AddressFamily.ipv6 && connectInfo.ipv6Only && setIPv6Only(true) != resultOK)
            return connectFailed(setIntOptionSocketAPI(), " ipv6Only");

        if (connectInfo.keepAlive && setKeepAlive(true) != resultOK)
            return connectFailed(setIntOptionSocketAPI(), " keepAlive");

        if (connectInfo.protocol == Protocol.tcp && connectInfo.noDelay && setNoDelay(true) != resultOK)
            return connectFailed(setIntOptionSocketAPI(), " noDelay");

        // Non-standard so skip checking for error
        if (connectInfo.useLoopback)
            setUseLoopback(true);

        if (connectInfo.receiveBufferSize && setReceiveBufferSize(connectInfo.receiveBufferSize) != resultOK)
            return connectFailed(setIntOptionSocketAPI(), " receiveBufferSize");

        if (connectInfo.sendBufferSize && setSendBufferSize(connectInfo.sendBufferSize) != resultOK)
            return connectFailed(setIntOptionSocketAPI(), " sendBufferSize");

        if (connectInfo.useLinger && setLinger(connectInfo.linger) != resultOK)
            return connectFailed(setLingerSocketAPI(), " linger");

        if (cast(bool)connectInfo.readTimeout && setReadTimeout(connectInfo.readTimeout) != resultOK)
            return connectFailed(setTimeoutSocketAPI(), " readTimeout");

        if (cast(bool)connectInfo.writeTimeout && setWriteTimeout(connectInfo.writeTimeout) != resultOK)
            return connectFailed(setTimeoutSocketAPI(), " writeTimeout");

        const r = connectInfo.isBlocking() && cast(bool)connectInfo.connectTimeout
            ? connectWithTimeout(connectInfo)
            : connectWithoutTimeout(connectInfo);
        if (r != resultOK)
            internalClose(false);
        return r;
    }

    final int connectWithoutTimeout(ConnectInfo connectInfo) nothrow
    {
        //import std.stdio : writeln; debug writeln("connectWithoutTimeout: ", connectInfo.port);
        
        auto sa = connectInfo.address.toSocketAddress(connectInfo.port);
        const r = connectSocket(_handle, sa.sval, sa.slen, connectInfo.isBlocking());
        return r == resultOK || r == EINPROGRESS
            ? resultOK
            : lastError.setSystemError("connect", lastSocketError());
    }

    final int connectWithTimeout(ConnectInfo connectInfo) nothrow
    {
        //import std.stdio : writeln; debug writeln("connectWithoutTimeout: ", connectInfo.port);

        // Turn blocking off first
        if (setBlocking(false) != resultOK)
            return resultError;

        // Make connection
        auto sa = connectInfo.address.toSocketAddress(connectInfo.port);
        const r = connectSocket(_handle, sa.sval, sa.slen, false);
        if (r != resultOK && r != EINPROGRESS)
            return lastError.setSystemError("connect", lastSocketError());

        if (waitForConnectSocket(_handle, toSocketTimeVal(connectInfo.connectTimeout)) != resultOK)
            return lastError.setSystemError(selectSocketAPI(), lastSocketError());

        // Turn back blocking on if
        if (connectInfo.isBlocking() && setBlocking(true) != resultOK)
            return resultError;

        return resultOK;
    }

    final int internalClose(bool setFailed) nothrow scope
    {
        scope (exit)
            _handle = invalidSocketHandle;

        if (closeSocket(_handle) == resultOK)
            return resultOK;

        return setFailed ? lastError.setSystemError(closeSocketAPI(), lastSocketError()) : resultError;
    }

    final long receiveImpl(scope ubyte[] bytes) nothrow
    {
        size_t offset = 0;
        while (offset < bytes.length)
        {
            const remaining = bytes.length - offset;
            const rn = remaining >= int.max ? int.max : remaining;
            const rr = receiveSocket(_handle, bytes[offset..offset+rn], 0);
            if (rr < 0)
                return lastError.setSystemError("recv", lastSocketError());
            else if (rr == 0)
                break;
            offset += rr;
        }
        return cast(long)offset;
    }

    final long sendImpl(scope const(ubyte)[] bytes) nothrow
    {
        size_t offset = 0;
        while (offset < bytes.length)
        {
            const remaining = bytes.length - offset;
            const wn = remaining >= int.max ? int.max : remaining;
            const wr = sendSocket(_handle, bytes[offset..offset+wn], 0);
            if (wr < 0)
                return lastError.setSystemError("send", lastSocketError());
            else if (wr == 0)
                break;
            offset += wr;
        }
        return cast(long)offset;
    }

private:
    SocketHandle _handle;
    IPAddress _address;
    ushort _port;
    version(Windows) bool _blocking; // Windows api does not have a function to query blocking state from socket handle
}

class SocketStream : Stream
{
@safe:

public:
    this(Socket socket) nothrow pure
    {
        this._socket = socket;
    }

    this(ConnectInfo connectInfo) nothrow
    {
        this._socket = new Socket();
        if (this._socket.connect(connectInfo) != resultOK)
            this.lastError = this._socket.lastError;
    }

    final override int close(const(bool) destroying = false) nothrow scope
    {
        if (_socket is null)
            return resultOK;

        scope (exit)
            _socket = null;
        return _socket.close(destroying);
    }

    final override int flush() nothrow
    {
        return resultOK;
    }

    final override long setLength(long value) nothrow
    {
        if (const r = checkUnsupported(false))
            return r;
        assert(0, "Unreach");
    }

    pragma(inline, true)
    @property final override bool active() const @nogc nothrow
    {
        return _socket !is null && _socket.active;
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
        return true;
    }

    @property final override bool canWrite() const @nogc nothrow
    {
        return active;
    }

    // Return available number of bytes for reading
    @property final override long length() nothrow
    {
        if (!active)
            return lastError.setError(ENOTCONN, " inactive socket");

        const result = _socket.availableBytes();
        return result >= 0 ? result : lastError.clone(_socket.lastError, result);
    }

    @property final override long position() nothrow
    {
        if (const r = checkUnsupported(false))
            return r;
        assert(0, "Unreach");
    }

    @property final Socket socket() nothrow pure
    {
        return _socket;
    }

protected:
    final override long readImpl(scope ubyte[] bytes) nothrow
    {
        return _socket.receive(bytes);
    }

    final override Duration readTimeoutImpl() nothrow
    {
        return _readTimeout;
    }

    final override Stream readTimeoutImpl(Duration value) nothrow
    {
        _readTimeout = value;
        return active
            ? (_socket.setReadTimeout(value) == resultOK ? this : null)
            : this;
    }

    final override long seekImpl(long offset, SeekOrigin origin) nothrow
    {
        if (const r = checkUnsupported(false))
            return r;
        assert(0, "Unreach");
    }

    final override long writeImpl(scope const(ubyte)[] bytes) nothrow
    {
        return _socket.send(bytes);
    }

    final override Duration writeTimeoutImpl() nothrow
    {
        return _writeTimeout;
    }

    final override Stream writeTimeoutImpl(Duration value) nothrow
    {
        _writeTimeout = value;
        return active
            ? (_socket.setWriteTimeout(value) == resultOK ? this : null)
            : this;
    }

private:
    Socket _socket;
    Duration _readTimeout, _writeTimeout;
}

unittest // getAddressInfo
{
    const r1 = getAddressInfo("localhost", null, AddressInfo.connectHints(0));
    assert(r1.isOK);
    assert(r1.value.length > 0);
    //import std.stdio : writeln; writeln("r1.value.length=", r1.value.length, ", r1.value[0]=", r1.value[0].toString(), ", r1.value[1]=", r1.value.length > 1 ? r1.value[1].toString() : null);

    const r2 = getAddressInfo("127.0.0.1", null, AddressInfo.connectHints(0));
    assert(r2.isOK);
    assert(r2.value.length > 0);
    //import std.stdio : writeln; writeln("r2.value.length=", r2.value.length, ", r2.value[0]=", r2.value[0].toString(), ", r2.value[1]=", r2.value.length > 1 ? r2.value[1].toString() : null);
}

@trusted unittest // getAddressInfo
{
    version(Windows)
        import core.sys.windows.winsock2;
    else version(Posix)
        import core.sys.posix.sys.socket;

    auto r = getAddressInfo("127.0.0.1", null, AddressInfo.connectHints(0, AddressFamily.ipv4));
    assert(r.isOK);
    assert(r.value.length > 0);
    auto s = r.value[0].address.toSocketAddress(0);
    auto sr = cast(sockaddr_in*)s.sval();
    assert(sr.sin_addr.s_addr == inet_addr("127.0.0.1".ptr));
}

version(none)
unittest
{
    import std.stdio : writeln; writeln("Socket.isSupportIPv4=", Socket.isSupportIPv4(), ", Socket.isSupportIPv6=", Socket.isSupportIPv6());
}

unittest
{
    import core.time : seconds;
    import std.conv : to;

    BindInfo bindInfo = BindInfo(IPAddress.parse("127.0.0.1"), 30_000);
    //bindInfo.protocol = Protocol.udp;
    //bindInfo.type = SocketType.dgram;
    auto serverSocket = new Socket(bindInfo);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.errorMessage);
    scope (exit)
        serverSocket.close();
    serverSocket.listen(bindInfo.backLog);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.errorMessage);
    //import std.stdio : writeln; writeln("serverSocket.localAddress()=", serverSocket.localAddress());

    ConnectInfo connectInfo = ConnectInfo(IPAddress.parse("127.0.0.1"), 30_000);
    //connectInfo.protocol = Protocol.udp;
    //connectInfo.type = SocketType.dgram;
    auto clientSocket = new Socket(connectInfo);
    assert(clientSocket.lastError.isOK, clientSocket.lastError.errorMessage);
    scope (exit)
        clientSocket.close();
    assert(clientSocket.select(SelectMode.readWrite, 1.seconds) == SelectMode.write);
    ubyte[4] buf1 = [0, 1, 2, 3];
    auto clientStream = new SocketStream(clientSocket);
    const w = clientStream.write(buf1[]);
    assert(w == 4);

    Socket peerSocket;
    serverSocket.accept(peerSocket);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.errorMessage);
    scope (exit)
        peerSocket.close();
    assert(peerSocket.remoteAddress() == clientSocket.localAddress());
    assert(peerSocket.select(SelectMode.all, 1.seconds) == SelectMode.readWrite);
    //import std.stdio : writeln; writeln("peer.remoteAddress=", peer.remoteAddress(), ", client.localAddress()=", client.localAddress());
    ubyte[4] buf2;
    auto peerStream = new SocketStream(peerSocket);
    assert(peerStream.length == 4);
    auto r = peerStream.read(buf2[]);
    assert(r == 4);
    assert(buf2[] == buf1[]);
}

unittest // Connect using machine name
{
    BindInfo bindInfo = BindInfo(IPAddress.parse("127.0.0.1"), 30_000);
    auto serverSocket = new Socket(bindInfo);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.errorMessage);
    scope (exit)
        serverSocket.close();
    serverSocket.listen(bindInfo.backLog);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.errorMessage);

    ConnectInfo connectInfo = ConnectInfo("localhost", 30_000);
    auto clientSocket = new Socket(connectInfo);
    assert(clientSocket.lastError.isOK, clientSocket.lastError.errorMessage);
    scope (exit)
        clientSocket.close();
    ubyte[4] buf1 = [0, 1, 2, 3];
    auto clientStream = new SocketStream(clientSocket);
    const w = clientStream.write(buf1[]);
    assert(w == 4);

    Socket peerSocket;
    serverSocket.accept(peerSocket);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.errorMessage);
    scope (exit)
        peerSocket.close();
    assert(peerSocket.remoteAddress() == clientSocket.localAddress());
    ubyte[4] buf2;
    auto peerStream = new SocketStream(peerSocket);
    assert(peerStream.length == 4);
    auto r = peerStream.read(buf2[]);
    assert(r == 4);
    assert(buf2[] == buf1[]);
}

unittest // Bind & Connect using machine name
{
    BindInfo bindInfo = BindInfo("localhost", 30_000);
    auto serverSocket = new Socket(bindInfo);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.errorMessage);
    scope (exit)
        serverSocket.close();
    serverSocket.listen(bindInfo.backLog);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.errorMessage);

    ConnectInfo connectInfo = ConnectInfo("localhost", 30_000);
    auto clientSocket = new Socket(connectInfo);
    assert(clientSocket.lastError.isOK, clientSocket.lastError.errorMessage);
    scope (exit)
        clientSocket.close();
    ubyte[4] buf1 = [0, 1, 2, 3];
    auto clientStream = new SocketStream(clientSocket);
    const w = clientStream.write(buf1[]);
    assert(w == 4);

    Socket peerSocket;
    serverSocket.accept(peerSocket);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.errorMessage);
    scope (exit)
        peerSocket.close();
    assert(peerSocket.remoteAddress() == clientSocket.localAddress());
    ubyte[4] buf2;
    auto peerStream = new SocketStream(peerSocket);
    assert(peerStream.length == 4);
    auto r = peerStream.read(buf2[]);
    assert(r == 4);
    assert(buf2[] == buf1[]);
}
