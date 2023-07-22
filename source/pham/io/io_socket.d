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

module pham.io.socket;

import core.time : Duration;

public import pham.io.error : IOError;
public import pham.io.socket_type;
import pham.io.stream : Stream;
public import pham.io.type;
version (Posix)
{
    import core.sys.posix.sys.socket;
    import pham.io.socket_posix;
}
else version (Windows)
{
    import core.sys.windows.winsock2;
    import pham.io.socket_windows;
}
else
    static assert(0, "Unsupport target");

@safe:

IOError getAddressInfo(out AddressInfo[] addressInfos,
    scope const(char)[] hostNameOrAddress, scope const(char)[] serviceNameOrPort,
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

    addressInfos = null;
    const r = getaddrinfo(lphostNameOrAddress, lpserviceNameOrPort, hasHints ? &lphints : null, &lpres);
    if (r != IOResult.success)
        return IOError.failed(lastSocketError());
    scope (exit)
        freeaddrinfo(lpres);

    addressInfos.reserve(10);
    for (const(addrinfo)* res = lpres; res; res = res.ai_next)
    {
        auto sa = SocketAddress(res.ai_addr, res.ai_addrlen);
        AddressInfo addressInfo;
        addressInfo.canonName = res.ai_canonname ? to!string(res.ai_canonname) : null;
        addressInfo.family = cast(AddressFamily)res.ai_family;
        addressInfo.type = cast(SocketType)res.ai_socktype;
        addressInfo.protocol = cast(Protocol)res.ai_protocol;
        addressInfo.flags = res.ai_flags;
        addressInfo.address = sa.toIPAddress();
        addressInfo.port = sa.port;
        addressInfos ~= addressInfo;
    }
    return IOError.ok();
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

    final IOResult accept(out SocketHandle peerHandle, out SocketAddress peerAddress) nothrow @trusted
    {
        if (!active)
        {
            peerHandle = invalidSocketHandle;
            peerAddress = SocketAddress.init;
            return lastError.setFailed(ENOTCONN, " inactive - need bind() and listen()");
        }

        ubyte[SocketAddress.sizeof] addrBuffer;
        int addrLength = SocketAddress.sizeof;
        peerHandle = acceptSocket(_handle, cast(sockaddr*)&addrBuffer[0], &addrLength);
        if (peerHandle == invalidSocketHandle)
        {
            peerAddress = SocketAddress.init;
            return lastError.setFailed(lastSocketError());
        }

        setBlockingSocket(peerHandle, blocking);
        peerAddress = SocketAddress(addrBuffer[0..addrLength]);
        return IOResult.success;
    }

    final IOResult accept(out Socket peerSocket) nothrow
    {
        SocketHandle peerHandle;
        SocketAddress peerAddress;
        const result = accept(peerHandle, peerAddress);
        peerSocket = result == IOResult.success
            ? new Socket(peerHandle, peerAddress.toIPAddress(), peerAddress.port)
            : null;
        return result;
    }

    final int availableBytes() nothrow
    {
        if (!active)
            return lastError.setFailed(ENOTCONN, " inactive socket");

        const result = getAvailableBytesSocket(_handle);
        return result >= 0 ? result : lastError.setFailed(lastSocketError());
    }

    final IOResult bind(BindInfo bindInfo) nothrow
    in
    {
        assert(!active);
    }
    do
    {
        if (active)
            return lastError.setFailed(EISCONN, " already active");

        version (Windows) this._blocking = bindInfo.isBlocking();
        if (bindInfo.needResolveHostName)
        {
            AddressInfo[] addressInfos;
            this.lastError = getAddressInfo(addressInfos, bindInfo.resolveHostName(),
                bindInfo.resolveServiceName(), bindInfo.resolveHostHints);
            if (this.lastError.isError)
            {
                this._handle = invalidSocketHandle;
                return IOResult.failed;
            }
            IOResult r;
            foreach (ref ai; addressInfos)
            {
                BindInfo bi = bindInfo;
                bi.address = ai.address;
                if (bi.type == SocketType.unspecified)
                    bi.type = ai.type;
                if (bi.port == 0)
                    bi.port = ai.port;
                r = bindImpl(bi);
                if (r == IOResult.success)
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

    final IOResult bind(IPAddress address, ushort port) nothrow
    {
        auto bindInfo = BindInfo(address, port);
        return bind(bindInfo);
    }

    final IOResult bind(string hostName, ushort port) nothrow
    {
        auto bindInfo = BindInfo(hostName, port);
        return bind(bindInfo);
    }

    final IOResult connect(ConnectInfo connectInfo) nothrow
    in
    {
        assert(!active);
    }
    do
    {
        if (active)
            return lastError.setFailed(EISCONN, " already active");

        version (Windows) this._blocking = connectInfo.isBlocking();
        if (connectInfo.needResolveHostName)
        {
            AddressInfo[] addressInfos;
            this.lastError = getAddressInfo(addressInfos, connectInfo.resolveHostName(),
                connectInfo.resolveServiceName(), connectInfo.resolveHostHints);
            if (this.lastError.isError)
            {
                this._handle = invalidSocketHandle;
                return IOResult.failed;
            }
            foreach (ref ai; addressInfos)
            {
                ConnectInfo ci = connectInfo;
                ci.address = ai.address;
                if (ci.type == SocketType.unspecified)
                    ci.type = ai.type;
                if (ci.port == 0)
                    ci.port = ai.port;
                if (connectImpl(ci) == IOResult.success)
                {
                    lastError.reset();
                    return IOResult.success;
                }
            }
            return IOResult.failed;
        }
        else
        {
            return connectImpl(connectInfo);
        }
    }

    final IOResult connect(IPAddress address, ushort port) nothrow
    {
        auto connectInfo = ConnectInfo(address, port);
        return connect(connectInfo);
    }

    final IOResult connect(IPAddress[] addresses, ushort port) nothrow
    {            
        foreach (ref a; addresses)
        {
            auto connectInfo = ConnectInfo(a, port);
            if (connect(connectInfo) == IOResult.success)
                return IOResult.success;
        }
        
        if (addresses.length != 0)
            return IOResult.failed;
     
        if (active)
            return lastError.setFailed(EISCONN, " already active");
     
        return lastError.setFailed(0, " missing IPAddress");
    }

    final IOResult connect(string hostName, ushort port) nothrow
    {
        auto connectInfo = ConnectInfo(hostName, port);
        return connect(connectInfo);
    }

    final IOResult close(const(bool) destroying = false) nothrow scope
    {
        if (_handle == invalidSocketHandle)
            return IOResult.success;

        if (!destroying)
            shutdown(ShutdownReason.both);

        return internalClose(!destroying);
    }

    final bool isAlive() nothrow
    {
        int type;
        return active && getIntOptionSocket(_handle, SOL_SOCKET, SO_TYPE, type) == IOResult.success;
    }

    pragma(inline, true)
    static bool isError(IOResult r) nothrow pure
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

    final IOResult listen(uint backLog) nothrow
    {
        if (!active)
            return lastError.setFailed(ENOTCONN, " inactive - need bind()");

        return listenSocket(_handle, backLog) == IOResult.success
            ? IOResult.success
            : lastError.setFailed(lastSocketError());
    }

    final SocketAddress localAddress() nothrow @trusted
    {
        if (!active)
        {
            lastError.setFailed(ENOTCONN, " inactive - need connect() or bind()");
            return SocketAddress.init;
        }

        ubyte[SocketAddress.sizeof] addrBuffer;
        int addrLength = SocketAddress.sizeof;
        const r = getsockname(_handle, cast(sockaddr*)&addrBuffer[0], &addrLength);
        if (r != IOResult.success)
        {
            lastError.setFailed(lastSocketError());
            return SocketAddress.init;
        }

        return SocketAddress(addrBuffer[0..addrLength]);
    }

    final SocketAddress remoteAddress() nothrow @trusted
    {
        if (!active)
        {
            lastError.setFailed(ENOTCONN, " inactive - need connect() or accept()");
            return SocketAddress.init;
        }

        ubyte[SocketAddress.sizeof] addrBuffer;
        int addrLength = SocketAddress.sizeof;
        const r = getpeername(_handle, cast(sockaddr*)&addrBuffer[0], &addrLength);
        if (r != IOResult.success)
        {
            lastError.setFailed(lastSocketError());
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
            lastError.setFailed(lastSocketError());
        return r <= 0 ? SelectMode.none : cast(SelectMode)r;
    }

    final long send(scope const(ubyte)[] bytes) nothrow
    {
        if (const r = checkActive())
            return r;

        return bytes.length == 0 ? 0L : sendImpl(bytes);
    }

    final IOResult setBlocking(bool state) nothrow
    {
        const r = setBlockingSocket(_handle, state);
        return r == IOResult.success ? IOResult.success : lastError.setFailed(lastSocketError(), " blocking");
    }

    final IOResult setDebug(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.debug_, v);
        return r == IOResult.success ? IOResult.success : lastError.setFailed(lastSocketError(), " debug");
    }

    final IOResult setDontRoute(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.dontRoute, v);
        return r == IOResult.success ? IOResult.success : lastError.setFailed(lastSocketError(), " dontRoute");
    }

    final IOResult setIPv6Only(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, IPPROTO_IPV6, IPV6_V6ONLY, v);
        return r == IOResult.success ? IOResult.success : lastError.setFailed(lastSocketError(), " ipv6Only");
    }

    final IOResult setKeepAlive(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.keepAlive, v);
        return r == IOResult.success ? IOResult.success : lastError.setFailed(lastSocketError(), " keepAlive");
    }

    final IOResult setLinger(Linger linger) nothrow
    {
        const r = setLingerSocket(_handle, linger);
        return r == IOResult.success ? IOResult.success : lastError.setFailed(lastSocketError(), " linger");
    }

    final IOResult setNoDelay(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, IPPROTO_TCP, TCP_NODELAY, v);
        return r == IOResult.success ? IOResult.success : lastError.setFailed(lastSocketError(), " noDelay");
    }

    final IOResult setReadTimeout(Duration duration) nothrow
    {
        const r = setReadTimeoutSocket(_handle, toSocketTimeVal(duration));
        return r == IOResult.success ? IOResult.success : lastError.setFailed(lastSocketError(), " readTimeout");
    }

    final IOResult setReceiveBufferSize(uint bytes) nothrow
    {
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.receiveBufferSize, bytes);
        return r == IOResult.success ? IOResult.success : lastError.setFailed(lastSocketError(), " receiveBufferSize");
    }

    final IOResult setReuseAddress(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.reuseAddress, v);
        return r == IOResult.success ? IOResult.success : lastError.setFailed(lastSocketError(), " reuseAddress");
    }

    final IOResult setSendBufferSize(uint bytes) nothrow
    {
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.sendBufferSize, bytes);
        return r == IOResult.success ? IOResult.success : lastError.setFailed(lastSocketError(), " sendBufferSize");
    }

    final IOResult setUseLoopback(bool state) nothrow
    {
        int v = state ? 1 : 0;
        const r = setIntOptionSocket(_handle, SOL_SOCKET, SocketOption.useLoopBack, v);
        return r == IOResult.success ? IOResult.success : lastError.setFailed(lastSocketError(), " useLoopback");
    }

    final IOResult setWriteTimeout(Duration duration) nothrow
    {
        const r = setWriteTimeoutSocket(_handle, toSocketTimeVal(duration));
        return r == IOResult.success ? IOResult.success : lastError.setFailed(lastSocketError(), " writeTimeout");
    }

    final IOResult shutdown(ShutdownReason reason) nothrow scope
    {
        if (_handle == invalidSocketHandle)
            return IOResult.success;

        if (shutdownSocket(_handle, reason) == IOResult.success)
            return IOResult.success;

        return lastError.setFailed(lastSocketError());
    }

    pragma(inline, true)
    @property final bool active() const @nogc nothrow
    {
        return _handle != invalidSocketHandle;
    }

    @property final IPAddress address() const nothrow
    {
        return this._address;
    }

    @property final bool blocking() const @nogc nothrow
    {
        version (Windows)
            return _blocking;
        else
        {
            const r = getBlockingSocket(_handle);
            if (r < 0)
                lastError.setFailed(lastSocketError());
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
    IOError lastError;

protected:
    final IOResult bindImpl(BindInfo bindInfo) nothrow
    {
        version (Windows) this._blocking = bindInfo.isBlocking();
        this._address = bindInfo.address;
        this._port = bindInfo.port;
        this._handle = createSocket(bindInfo.family, bindInfo.type, bindInfo.protocol);
        if (this._handle == invalidSocketHandle)
        {
            const r = lastError.setFailed(lastSocketError());
            lastError.addMessageIf(bindInfo.toErrorInfo());
            return r;
        }

        IOResult bindFailed(string optName) nothrow
        {
            const r = lastSocketError();
            internalClose(false);
            return lastError.setFailed(r, optName);
        }

        // No need to check error for unimportant flag
        if (bindInfo.debug_)
            setDebug(true);

        if (setBlocking(bindInfo.isBlocking()) != IOResult.success)
            return bindFailed(" blocking");

        if (bindInfo.dontRoute && setDontRoute(true) != IOResult.success)
            return bindFailed(" dontRoute");

        if (bindInfo.family == AddressFamily.ipv6 && bindInfo.ipv6Only && setIPv6Only(true) != IOResult.success)
            return bindFailed(" ipv6Only");

        if (bindInfo.protocol == Protocol.tcp && bindInfo.noDelay && setNoDelay(true) != IOResult.success)
            return bindFailed(" noDelay");

        if (bindInfo.reuseAddress && setReuseAddress(true) != IOResult.success)
            return bindFailed(" reuseAddress");

        // Non-standard so skip checking for error
        if (bindInfo.useLoopback)
            setUseLoopback(true);

        if (bindInfo.useLinger && setLinger(bindInfo.linger) != IOResult.success)
            return bindFailed(" linger");

        auto sa = bindInfo.address.toSocketAddress(bindInfo.port);
        if (bindSocket(this._handle, sa.sval, sa.slen) != IOResult.success)
            return bindFailed(null);

        return IOResult.success;
    }

    pragma(inline, true)
    final IOResult checkActive(string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
    {
        return active
            ? lastError.reset()
            : lastError.setFailed(0, funcName, " with inactive socket", file, line);
    }

    final IOResult connectImpl(ConnectInfo connectInfo) nothrow
    {
        version (Windows) this._blocking = connectInfo.isBlocking();
        this._address = connectInfo.address;
        this._port = connectInfo.port;
        this._handle = createSocket(connectInfo.family, connectInfo.type, connectInfo.protocol);
        if (this._handle == invalidSocketHandle)
        {
            const r = lastError.setFailed(lastSocketError());
            lastError.addMessageIf(connectInfo.toErrorInfo());
            return r;
        }

        IOResult connectFailed(string optName) nothrow
        {
            const r = lastSocketError();
            internalClose(false);
            return lastError.setFailed(r, optName);
        }

        // No need to check error for unimportant flag
        if (connectInfo.debug_)
            setDebug(true);

        if (setBlocking(connectInfo.isBlocking()) != IOResult.success)
            return connectFailed(" blocking");

        if (connectInfo.dontRoute && setDontRoute(true) != IOResult.success)
            return connectFailed(" dontRoute");

        if (connectInfo.family == AddressFamily.ipv6 && connectInfo.ipv6Only && setIPv6Only(true) != IOResult.success)
            return connectFailed(" ipv6Only");

        if (connectInfo.keepAlive && setKeepAlive(true) != IOResult.success)
            return connectFailed(" keepAlive");

        if (connectInfo.protocol == Protocol.tcp && connectInfo.noDelay && setNoDelay(true) != IOResult.success)
            return connectFailed(" noDelay");

        // Non-standard so skip checking for error
        if (connectInfo.useLoopback)
            setUseLoopback(true);

        if (connectInfo.receiveBufferSize && setReceiveBufferSize(connectInfo.receiveBufferSize) != IOResult.success)
            return connectFailed(" receiveBufferSize");

        if (connectInfo.sendBufferSize && setSendBufferSize(connectInfo.sendBufferSize) != IOResult.success)
            return connectFailed(" sendBufferSize");

        if (connectInfo.useLinger && setLinger(connectInfo.linger) != IOResult.success)
            return connectFailed(" linger");

        if (cast(bool)connectInfo.readTimeout && setReadTimeout(connectInfo.readTimeout) != IOResult.success)
            return connectFailed(" readTimeout");

        if (cast(bool)connectInfo.writeTimeout && setWriteTimeout(connectInfo.writeTimeout) != IOResult.success)
            return connectFailed(" writeTimeout");

        const r = connectInfo.isBlocking() && cast(bool)connectInfo.connectTimeout
            ? connectWithTimeout(connectInfo)
            : connectWithoutTimeout(connectInfo);
        if (r != IOResult.success)
            internalClose(false);
        return r;
    }

    final IOResult connectWithoutTimeout(ConnectInfo connectInfo) nothrow
    {
        auto sa = connectInfo.address.toSocketAddress(connectInfo.port);
        const r = connectSocket(_handle, sa.sval, sa.slen, connectInfo.isBlocking());
        return r == IOResult.success || r == EINPROGRESS
            ? IOResult.success
            : lastError.setFailed(lastSocketError());
    }

    final IOResult connectWithTimeout(ConnectInfo connectInfo) nothrow
    {
        // Turn blocking off first
        if (setBlocking(false) != IOResult.success)
            return IOResult.failed;

        // Make connection
        auto sa = connectInfo.address.toSocketAddress(connectInfo.port);
        const r = connectSocket(_handle, sa.sval, sa.slen, false);
        if (r != IOResult.success && r != EINPROGRESS)
            return lastError.setFailed(lastSocketError());

        if (waitForConnectSocket(_handle, toSocketTimeVal(connectInfo.connectTimeout)) != IOResult.success)
            return lastError.setFailed(lastSocketError());

        // Turn back blocking on if
        if (connectInfo.isBlocking() && setBlocking(true) != IOResult.success)
            return IOResult.failed;

        return IOResult.success;
    }

    final IOResult internalClose(bool setFailed) nothrow scope
    {
        scope (exit)
            _handle = invalidSocketHandle;

        if (closeSocket(_handle) == IOResult.success)
            return IOResult.success;

        return setFailed ? lastError.setFailed(lastSocketError()) : IOResult.failed;
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
                return lastError.setFailed(lastSocketError());
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
                return lastError.setFailed(lastSocketError());
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
    version (Windows) bool _blocking; // Windows api does not have a function to query blocking state from socket handle
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
        if (this._socket.connect(connectInfo) != IOResult.success)
            this.lastError = this._socket.lastError;
    }

    final override IOResult close(const(bool) destroying = false) nothrow scope
    {
        if (_socket is null)
            return IOResult.success;

        scope (exit)
            _socket = null;
        return _socket.close(destroying);
    }

    final override IOResult flush() nothrow
    {
        return IOResult.success;
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
            return lastError.setFailed(ENOTCONN, " inactive socket");

        const result = _socket.availableBytes();
        return result >= 0 ? result : lastError.clone(_socket.lastError, cast(IOResult)result);
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
            ? (_socket.setReadTimeout(value) == IOResult.success ? this : null)
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
            ? (_socket.setWriteTimeout(value) == IOResult.success ? this : null)
            : this;
    }

private:
    Socket _socket;
    Duration _readTimeout, _writeTimeout;
}

unittest
{
    AddressInfo[] addressInfos;
    const r1 = getAddressInfo(addressInfos, "localhost", null, AddressInfo.connectHints());
    assert(r1.isOK);
    assert(addressInfos.length > 0);
    //import std.stdio : writeln; writeln("addressInfos.length=", addressInfos.length, ", addressInfos[0]=", addressInfos[0].toString(), ", addressInfos[1]=", addressInfos.length > 1 ? addressInfos[1].toString() : null);

    const r2 = getAddressInfo(addressInfos, "127.0.0.1", null, AddressInfo.connectHints());
    assert(r2.isOK);
    assert(addressInfos.length > 0);
    //import std.stdio : writeln; writeln("addressInfos.length=", addressInfos.length, ", addressInfos[0]=", addressInfos[0].toString(), ", addressInfos[1]=", addressInfos.length > 1 ? addressInfos[1].toString() : null);
}

version (none)
unittest
{
    import std.stdio : writeln; writeln("Socket.isSupportIPv4=", Socket.isSupportIPv4(), ", Socket.isSupportIPv6=", Socket.isSupportIPv6());
}

unittest
{
    import core.time : seconds;
    import std.conv : to;
    
    BindInfo bindInfo;
    bindInfo.address = IPAddress.parse("127.0.0.1");
    bindInfo.port = 30_000;
    //bindInfo.protocol = Protocol.udp;
    //bindInfo.type = SocketType.dgram;
    auto serverSocket = new Socket();
    serverSocket.bind(bindInfo);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.message);
    scope (exit)
        serverSocket.close();
    serverSocket.listen(bindInfo.backLog);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.message);
    //import std.stdio : writeln; writeln("serverSocket.localAddress()=", serverSocket.localAddress());

    ConnectInfo connectInfo;
    connectInfo.address = IPAddress.parse("127.0.0.1");
    connectInfo.port = 30_000;
    //connectInfo.protocol = Protocol.udp;
    //connectInfo.type = SocketType.dgram;
    auto clientSocket = new Socket(connectInfo);
    assert(clientSocket.lastError.isOK, clientSocket.lastError.message);
    scope (exit)
        clientSocket.close();
    assert(clientSocket.select(SelectMode.readWrite, 1.seconds) == SelectMode.write);
    ubyte[4] buf1 = [0, 1, 2, 3];
    auto clientStream = new SocketStream(clientSocket);
    const w = clientStream.write(buf1[]);
    assert(w == 4);

    Socket peerSocket;
    serverSocket.accept(peerSocket);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.message);
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
    BindInfo bindInfo;
    bindInfo.address = IPAddress.parse("127.0.0.1");
    bindInfo.port = 30_000;
    auto serverSocket = new Socket();
    serverSocket.bind(bindInfo);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.message);
    scope (exit)
        serverSocket.close();
    serverSocket.listen(bindInfo.backLog);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.message);

    ConnectInfo connectInfo;
    connectInfo.hostName = "localhost";
    connectInfo.port = 30_000;
    auto clientSocket = new Socket(connectInfo);
    assert(clientSocket.lastError.isOK, clientSocket.lastError.message);
    scope (exit)
        clientSocket.close();
    ubyte[4] buf1 = [0, 1, 2, 3];
    auto clientStream = new SocketStream(clientSocket);
    const w = clientStream.write(buf1[]);
    assert(w == 4);

    Socket peerSocket;
    serverSocket.accept(peerSocket);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.message);
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
    BindInfo bindInfo;
    bindInfo.hostName = "localhost";
    bindInfo.port = 30_000;
    auto serverSocket = new Socket();
    serverSocket.bind(bindInfo);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.message);
    scope (exit)
        serverSocket.close();
    serverSocket.listen(bindInfo.backLog);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.message);

    ConnectInfo connectInfo;
    connectInfo.hostName = "localhost";
    connectInfo.port = 30_000;
    auto clientSocket = new Socket(connectInfo);
    assert(clientSocket.lastError.isOK, clientSocket.lastError.message);
    scope (exit)
        clientSocket.close();
    ubyte[4] buf1 = [0, 1, 2, 3];
    auto clientStream = new SocketStream(clientSocket);
    const w = clientStream.write(buf1[]);
    assert(w == 4);

    Socket peerSocket;
    serverSocket.accept(peerSocket);
    assert(serverSocket.lastError.isOK, serverSocket.lastError.message);
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
