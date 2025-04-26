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

module pham.io.io_socket_type;

import core.time : Duration, dur;
import std.system : Endian;

import pham.utl.utl_bit : fromBytes, Map32Bit, nativeToBytes, toBytes;
import pham.utl.utl_enum_set : EnumSet, toName;
import pham.utl.utl_numeric_parser : cvtDigit, cvtHexDigit, NumericParsedKind, parseIntegral;
import pham.utl.utl_object : toString;
import pham.utl.utl_result;
import pham.utl.utl_text : simpleIndexOf;

version(Posix)
{
    import core.sys.posix.netinet.in_;
    import core.sys.posix.netinet.tcp;
    import core.sys.posix.sys.select;
    import core.sys.posix.sys.socket;
    public import pham.io.io_socket_posix;
    
    private enum : int
    {
        SD_RECEIVE = SHUT_RD,
        SD_SEND    = SHUT_WR,
        SD_BOTH    = SHUT_RDWR
    }    
}
else version(Windows)
{
    import core.sys.windows.winsock2;
    public import pham.io.io_socket_windows;
}
else
    pragma(msg, "Unsupported system for " ~ __MODULE__);

@safe:

enum AddressFamily : int
{
    unspecified         = AF_UNSPEC,    // AF_UNSPEC - Unspecified
    unix                = AF_UNIX,    // local to host (pipes, portals)
    ipv4                = AF_INET,    // internetwork: UDP, TCP, etc.
    impLink             = 3,    // arpanet imp addresses
    pup                 = 4,    // pup protocols: e.g. BSP
    chaos               = 5,    // mit CHAOS protocols
    ns                  = 6,    // XEROX NS protocols
    ipx                 = ns,   // IPX and SPX
    iso                 = 7,    // ISO protocols
    osi                 = iso,  // OSI is ISO
    ecma                = 8,    // european computer manufacturers
    dataKit             = 9,    // datakit protocols
    ccitt               = 10,   // CCITT protocols, X.25 etc
    sna                 = 11,   // IBM SNA
    decNet              = 12,   // DECnet
    dataLink            = 13,   // Direct data link interface
    lat                 = 14,   // LAT
    hyperChannel        = 15,   // NSC Hyperchannel
    appleTalk           = 16,   // AppleTalk
    netBios             = 17,   // NetBios-style addresses
    voiceView           = 18,   // VoiceView
    fireFox             = 19,   // FireFox
    banyan              = 21,   // Banyan
    atm                 = 22,   // Native ATM Services
    ipv6                = AF_INET6,   // AF_INET6 - Internetwork Version 6
    cluster             = 24,   // Microsoft Wolfpack
    ieee12844           = 25,   // IEEE 1284.4 WG AF
    irda                = 26,   // IrDA
    networkDesigners    = 28,   // Network Designers OSI & gateway enabled protocols
    //max                 = AF_MAX,   // Max
}

enum Protocol : int
{
    ip = IPPROTO_IP,
    icmp = IPPROTO_ICMP,
    igmp = IPPROTO_IGMP,
    ggp = IPPROTO_GGP,
    tcp = IPPROTO_TCP,
    pup = IPPROTO_PUP,
    udp = IPPROTO_UDP,
    idp = IPPROTO_IDP,
    nd = IPPROTO_ND,
}

/**
 * Poll status of a socket
 */
enum SelectMode : int
{
    none = 0, /// Poll no result
    read = 1, /// Poll the read status of a socket
    write = 2, /// Poll the write status of a socket
    error = 4, /// Poll the error status of a socket
    all = read | write | error,
    readWrite = read | write,
    waitforConnect = write | error,
}

enum SocketType : int
{
    unspecified = 0, /// unspecified socket type, mostly as resolve hint
    stream = SOCK_STREAM, /// sequenced, reliable, two-way, connection-based data streams
    dgram = SOCK_DGRAM, /// unordered, unreliable datagrams of fixed length
    seqPacket = SOCK_SEQPACKET, /// sequenced, reliable, two-way datagrams of fixed length
    raw = SOCK_RAW, /// raw network access
}

enum ShutdownReason : int
{
    receive = SD_RECEIVE,      /// socket receives are disallowed
    send = SD_SEND,         /// socket sends are disallowed
    both = SD_BOTH,         /// both RECEIVE and SEND
}

struct AddressInfo
{
nothrow @safe:

public:
    static AddressInfo bindHints(ushort port,
        AddressFamily family = AddressFamily.ipv4,
        SocketType type = SocketType.stream,
        Protocol protocol = Protocol.tcp) pure
    {
        AddressInfo result;
        result.family = family;
        result.type = type;
        result.protocol = protocol;
        result.flags = AI_ADDRCONFIG | AI_V4MAPPED;
        result.port = port;
        return result;
    }

    static AddressInfo connectHints(ushort port,
        AddressFamily family = AddressFamily.ipv4,
        SocketType type = SocketType.stream,
        Protocol protocol = Protocol.tcp) pure
    {
        AddressInfo result;
        result.family = family;
        result.type = type;
        result.protocol = protocol;
        result.flags = AI_ADDRCONFIG | AI_V4MAPPED;
        result.port = port;
        return result;
    }

    string toString() const pure
    {
        return address.isIPv4
            ? IPv4AddressHelper.toString(address._ipvNumbers[0..IPSocketAddress.maxIPv4AddressBytes], port)
            : (address.isIPv6
                ? IPv6AddressHelper.toString(address._ipvNumbers[0..IPSocketAddress.maxIPv6AddressBytes], address.scopeId, port)
                : null);
    }

public:
    string canonName;
    IPSocketAddress address;
    AddressFamily family;
    SocketType type;
    Protocol protocol;
    int flags;
    ushort port;
}

struct BindInfo
{
nothrow @safe:

public:
    this(IPSocketAddress address, ushort port,
        SocketType type = SocketType.stream,
        Protocol protocol = Protocol.tcp) pure
    {
        this.address = address;
        this.port = port;
        this.protocol = protocol;
        this.type = type;
        this.backLog = 1;
        this.flags = EnumSet!Flags([Flags.blocking, Flags.noDelay, Flags.reuseAddress]);
    }

    this(string hostName, ushort port,
        AddressFamily family = AddressFamily.ipv4,
        SocketType type = SocketType.stream,
        Protocol protocol = Protocol.tcp) pure
    {
        this.hostName = hostName;
        this.port = port;
        this.protocol = protocol;
        this.type = type;
        this.address = IPSocketAddress(family);
        this.backLog = 1;
        this.flags = EnumSet!Flags([Flags.blocking, Flags.noDelay, Flags.reuseAddress]);
        this.resolveHostHints = AddressInfo.bindHints(port, family, type, protocol);
    }

    bool isBlocking() const @nogc
    {
        return blocking && canBlockingSocketType(type);
    }

    string resolveHostName() const
    {
        return hostName;
    }

    string resolveServiceName() const
    {
        import std.conv : to;

        return serviceName.length
            ? serviceName
            : (port ? port.to!string() : null);
    }

    void setLinger(scope const(Duration) duration)
    {
        linger = toSocketLinger(duration);
    }

    string toErrorInfo()
    {
        return .toErrorInfo(family, type, protocol);
    }

    @property bool blocking() const @nogc
    {
        return flags.blocking;
    }

    @property ref BindInfo blocking(bool state) @nogc return
    {
        flags.blocking = state;
        return this;
    }

    @property bool debug_() const @nogc
    {
        return flags.debug_;
    }

    @property ref BindInfo debug_(bool state) @nogc return
    {
        flags.debug_ = state;
        return this;
    }

    @property bool dontRoute() const @nogc
    {
        return flags.dontRoute;
    }

    @property ref BindInfo dontRoute(bool state) @nogc return
    {
        flags.dontRoute = state;
        return this;
    }

    pragma(inline, true)
    @property AddressFamily family() const @nogc
    {
        return address.family;
    }

    @property bool ipv6Only() const @nogc
    {
        return flags.ipv6Only;
    }

    @property ref BindInfo ipv6Only(bool state) @nogc return
    {
        flags.ipv6Only = state;
        return this;
    }

    pragma(inline, true)
    @property bool needResolveHostName() const @nogc
    {
        return hostName.length != 0;
    }

    @property bool noDelay() const @nogc
    {
        return flags.noDelay;
    }

    @property ref BindInfo noDelay(bool state) @nogc return
    {
        flags.noDelay = state;
        return this;
    }

    @property bool reuseAddress() const @nogc
    {
        return flags.reuseAddress;
    }

    @property ref BindInfo reuseAddress(bool state) @nogc return
    {
        flags.reuseAddress = state;
        return this;
    }

    @property bool useLinger() const @nogc
    {
        return linger.l_onoff != 0 || linger.l_linger != 0;
    }

    @property bool useLoopback() const @nogc
    {
        return flags.useLoopback;
    }

    @property ref BindInfo useLoopback(bool state) @nogc return
    {
        flags.useLoopback = state;
        return this;
    }

public:
    IPSocketAddress address;
    SocketType type;
    Protocol protocol;
    ushort port;
    Linger linger;
    uint backLog;
    EnumSet!Flags flags;
    string hostName;
    string serviceName;
    AddressInfo resolveHostHints;

private:
    enum Flags
    {
        blocking,
        debug_,
        dontRoute,
        ipv6Only,
        noDelay,
        reuseAddress,
        useLoopback,
    }
}

struct ConnectInfo
{
    import core.time : seconds;

nothrow @safe:

public:
    this(IPSocketAddress address, ushort port,
        SocketType type = SocketType.stream,
        Protocol protocol = Protocol.tcp) pure
    {
        this.address = address;
        this.port = port;
        this.protocol = protocol;
        this.type = type;
        this.connectTimeout = 5.seconds;
        this.flags = EnumSet!Flags([Flags.blocking, Flags.noDelay]);
    }

    this(string hostName, ushort port,
        AddressFamily family = AddressFamily.ipv4,
        SocketType type = SocketType.stream,
        Protocol protocol = Protocol.tcp) pure
    {
        this.hostName = hostName;
        this.port = port;
        this.protocol = protocol;
        this.type = type;
        this.address = IPSocketAddress(family);
        this.connectTimeout = 5.seconds;
        this.flags = EnumSet!Flags([Flags.blocking, Flags.noDelay]);
        this.resolveHostHints = AddressInfo.connectHints(port, family, type, protocol);
    }

    bool isBlocking() const @nogc
    {
        return blocking && canBlockingSocketType(type);
    }

    string resolveHostName() const
    {
        return hostName;
    }

    string resolveServiceName() const
    {
        import std.conv : to;

        return serviceName.length
            ? serviceName
            : (port ? port.to!string() : null);
    }

    void setLinger(scope const(Duration) duration)
    {
        linger = toSocketLinger(duration);
    }

    string toErrorInfo()
    {
        return .toErrorInfo(family, type, protocol);
    }

    // Default is true
    @property bool blocking() const @nogc
    {
        return flags.blocking;
    }

    @property ref ConnectInfo blocking(bool state) @nogc return
    {
        flags.blocking = state;
        return this;
    }

    @property bool debug_() const @nogc
    {
        return flags.debug_;
    }

    @property ref ConnectInfo debug_(bool state) @nogc return
    {
        flags.debug_ = state;
        return this;
    }

    @property bool dontRoute() const @nogc
    {
        return flags.dontRoute;
    }

    @property ref ConnectInfo dontRoute(bool state) @nogc return
    {
        flags.dontRoute = state;
        return this;
    }

    pragma(inline, true)
    @property AddressFamily family() const @nogc
    {
        return address.family;
    }

    @property bool ipv6Only() const @nogc
    {
        return flags.ipv6Only;
    }

    @property ref ConnectInfo ipv6Only(bool state) @nogc return
    {
        flags.ipv6Only = state;
        return this;
    }

    @property bool keepAlive() const @nogc
    {
        return flags.keepAlive;
    }

    @property ref ConnectInfo keepAlive(bool state) @nogc return
    {
        flags.keepAlive = state;
        return this;
    }

    pragma(inline, true)
    @property bool needResolveHostName() const @nogc
    {
        return hostName.length != 0;
    }

    // Default is true
    @property bool noDelay() const @nogc
    {
        return flags.noDelay;
    }

    @property ref ConnectInfo noDelay(bool state) @nogc return
    {
        flags.noDelay = state;
        return this;
    }

    @property bool useLinger() const @nogc
    {
        return linger.l_onoff != 0 || linger.l_linger != 0;
    }

    @property bool useLoopback() const @nogc
    {
        return flags.useLoopback;
    }

    @property ref ConnectInfo useLoopback(bool state) @nogc return
    {
        flags.useLoopback = state;
        return this;
    }

public:
    IPSocketAddress address;
    SocketType type;
    Protocol protocol;
    ushort port;
    Duration connectTimeout;
    Duration readTimeout;
    Duration writeTimeout;
    Linger linger;
    uint receiveBufferSize;
    uint sendBufferSize;
    EnumSet!Flags flags;
    string hostName;
    string serviceName;
    AddressInfo resolveHostHints;

private:
    enum Flags
    {
        blocking,
        debug_,
        dontRoute,
        ipv6Only,
        keepAlive,
        noDelay,
        useLoopback,
    }
}

struct IPSocketAddress
{
@safe:

public:
    /**
     * Initializes a new IPSocketAddress struct with an IPv4 address.
     * The ipv4SocketAddress value is assumed to be in network byte order.
     */
    this(uint ipv4SocketAddress) nothrow pure
    {
        this._family = AddressFamily.ipv4;
        this._ipvNumbers[0..maxIPv4AddressBytes] = .toBytes(ipv4SocketAddress);
        this._scopeId = 0;
    }

    /**
     * Initializes a new IPSocketAddress struct with an IPv4 or IPv6 address depending on the length of socketAddress.
     * For IPv6, the scopeid will be 0 (zero).
     * The socketAddress array-value is assumed to be in network byte order with the most significant byte first in index position 0.
     */
    this(scope const(ubyte)[] socketAddress) nothrow pure
    in
    {
        assert(socketAddress.length == maxIPv4AddressBytes || socketAddress.length == maxIPv6AddressBytes);
    }
    do
    {
        if (socketAddress.length == maxIPv4AddressBytes)
        {
            this._family = AddressFamily.ipv4;
            this._ipvNumbers[0..maxIPv4AddressBytes] = socketAddress[];
            this._scopeId = 0;
        }
        else if (socketAddress.length == maxIPv6AddressBytes)
        {
            this._family = AddressFamily.ipv6;
            this._ipvNumbers[0..maxIPv6AddressBytes] = socketAddress[];
            this._scopeId = 0;
        }
        else
            this._family = AddressFamily.unspecified;
    }

    /**
     * Initializes a new IPSocketAddress struct with an IPv6 address.
     * The scopeid identifies a network interface in the case of a link-local address.
     * The scope is valid only for link-local and site-local addresses.
     * The ipv6SocketAddress array-value is assumed to be in network byte order with the most significant byte first in index position 0.
     */
    this(scope const(ubyte)[] ipv6SocketAddress, uint scopeId) nothrow pure
    in
    {
        assert(ipv6SocketAddress.length == maxIPv6AddressBytes);
    }
    do
    {
        if (ipv6SocketAddress.length == maxIPv6AddressBytes)
        {
            this._family = AddressFamily.ipv6;
            this._ipvNumbers[0..maxIPv6AddressBytes] = ipv6SocketAddress[];
            this._scopeId = scopeId;
        }
        else
            this._family = AddressFamily.unspecified;
    }

    this(AddressFamily family) nothrow pure
    {
        this._family = family;
    }

    int opCmp(scope const(IPSocketAddress) rhs) const @nogc nothrow pure scope
    {
        int result = cmp(this.isIPv6 ? 2 : (this.isIPv4 ? 1 : 0), rhs.isIPv6 ? 2 : (rhs.isIPv4 ? 1 : 0));
        if (result == 0)
          result = cmp(this._ipvNumbers[], rhs._ipvNumbers[]);
        if (result == 0)
          result = cmp(this._scopeId, rhs._scopeId);
        if (result == 0)
           result = cmp(this._family, rhs._family);
        return result;
    }

    bool opEquals(scope const(IPSocketAddress) rhs) const @nogc nothrow pure scope
    {
        return opCmp(rhs) == 0;
    }

    /**
     * Maps the IPSocketAddress struct to an IPv4 address
     */
    IPSocketAddress mapToIPv4() nothrow
    {
        if (isIPv6)
        {
            ubyte[maxIPvBytes] ipv4Numbers = 0;
            ipv4Numbers[0..maxIPv4AddressBytes] = _ipvNumbers[maxIPv6AddressBytes-maxIPv4AddressBytes..maxIPv6AddressBytes];
            return IPSocketAddress(ipv4Numbers, 0, AddressFamily.ipv4);
        }
        else
            return this;
    }

    /**
     * Maps the IPSocketAddress struct to an IPv6 address
     */
    IPSocketAddress mapToIPv6() nothrow
    {
        if (isIPv4)
        {
            ubyte[maxIPvBytes] ipv6Numbers = 0;
            ipv6Numbers[12..maxIPv6AddressBytes] = _ipvNumbers[0..maxIPv4AddressBytes];
            ipv6Numbers[10..12] = 0xff;
            return IPSocketAddress(ipv6Numbers, 0, AddressFamily.ipv6);
        }
        else
            return this;
    }

    static ResultIf!IPSocketAddress parse(scope const(char)[] address) nothrow
    {
        if (address.simpleIndexOf(':') >= 0 || (address.length && address[0] == '['))
            return IPv6AddressHelper.parse(address);
        else
            return IPv4AddressHelper.parse(address);
    }

    static ResultIf!IPSocketAddress parseIPv4(scope const(char)[] address) nothrow pure
    {
        return IPv4AddressHelper.parse(address);
    }

    static ResultIf!IPSocketAddress parseIPv6(scope const(char)[] address) nothrow
    {
        return IPv6AddressHelper.parse(address);
    }

    /**
     *  Returns IP address in bytes in network order
     */
    const(ubyte)[] toBytes() const @nogc nothrow pure return
    {
        return isIPv4
            ? _ipvNumbers[0..maxIPv4AddressBytes]
            : (isIPv6 ? _ipvNumbers[0..maxIPv6AddressBytes] : null);
    }

    SocketAddress toSocketAddress(ushort port) @nogc nothrow pure
    {
        return SocketAddress(this, port);
    }

    size_t toHash() const @nogc nothrow pure scope
    {
        return hashOf(_family, hashOf(_scopeId, hashOf(_ipvNumbers)));
    }

    string toString() const nothrow
    {
        return isIPv4 ? toStringIPv4() : (isIPv6 ? toStringIPv6() : null);
    }

    @property AddressFamily family() const @nogc nothrow pure
    {
        return _family;
    }

    @property bool isAny() const @nogc nothrow pure
    {
        return isIPv4
            ? this.opEquals(ipv4Any)
            : (isIPv6 ? this.opEquals(ipv6Any) : false);
    }

    @property bool isIPv4() const @nogc nothrow pure
    {
        return _family == AddressFamily.ipv4;
    }

    @property bool isIPv6() const @nogc nothrow pure
    {
        return _family == AddressFamily.ipv6;
    }

    @property bool isLoopback() const @nogc nothrow pure
    {
        return isIPv4
            ? this.opEquals(ipv4Loopback)
            : (isIPv6 ? (this.opEquals(ipv6Loopback) || this.opEquals(ipv4LoopbackMappedToIPv6)) : false);
    }

    @property uint scopeId() const @nogc nothrow pure
    {
        return isIPv6 ? _scopeId : 0;
    }

public:
    enum maxIPv4AddressBytes = 4;
    enum maxIPv4StringLength = 15; // 4 numbers separated by 3 periods, with up to 3 digits per number

    enum maxIPv6AddressBytes = 16;
    enum maxIPv6StringLength = 65;

    alias maxIPvBytes = maxIPv6AddressBytes;

    static immutable IPSocketAddress ipv4Any = IPSocketAddress([0, 0, 0, 0]);
    static immutable IPSocketAddress ipv4Loopback = IPSocketAddress([127, 0, 0, 1]);
    static immutable IPSocketAddress ipv4Broadcast = IPSocketAddress([255, 255, 255, 255]);
    alias ipv4None = ipv4Broadcast;

    static immutable IPSocketAddress ipv6Any = IPSocketAddress([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 0);
    static immutable IPSocketAddress ipv6Loopback = IPSocketAddress([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1], 0);
    alias ipv6None = ipv6Any;
    static immutable IPSocketAddress ipv4LoopbackMappedToIPv6 = IPSocketAddress([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 127, 0, 0, 1], 0);

private:
    this(ubyte[maxIPvBytes] ipvNumbers, uint scopeId, AddressFamily family) nothrow pure
    {
        this._ipvNumbers = ipvNumbers;
        this._scopeId = scopeId;
        this._family = family;
    }

    string toStringIPv4() const nothrow
    {
        return IPv4AddressHelper.toString(_ipvNumbers[0..maxIPv4AddressBytes], 0);
    }

    string toStringIPv6() const nothrow
    {
        return IPv6AddressHelper.toString(_ipvNumbers[0..maxIPv6AddressBytes], _scopeId, 0);
    }

private:
    ubyte[maxIPvBytes] _ipvNumbers; // In network endian format
    uint _scopeId;
    AddressFamily _family;
}

struct PollResult
{
nothrow @safe:

public:
    bool isError() const
    {
        return isSelectMode(modes, SelectMode.error);
    }

public:
    SelectMode modes;
    int errorCode;
}

struct PollFDSet
{
nothrow @safe:

public:
    /**
     * Add a socket with checking modes (read & write)
     * Params:
     *  handle = a valid socket handle to be checked
     *  modes = combination of statuses to be checked for
     */
    ref PollFDSet add(SocketHandle handle, SelectMode modes) return
    {
        pollFDs ~= PollFD(handle, pollEventOf(modes), 0);
        return this;
    }

    /**
     * Set all members into initial state
     */
    ref PollFDSet clear() return
    {
        pollFDs = [];
        pollResults = [];
        return this;
    }

    /**
     * Returns number of checking sockets
     */
    int length() const
    {
        return cast(int)pollFDs.length;
    }

    /**
     * Prepare state vars for a 'poll' api call
     */
    ref PollFDSet reset() return
    {
        foreach (ref fd; pollFDs)
            fd.revents = 0;
        pollResults = [];
        return this;
    }

public:
    PollFD[] pollFDs;
    PollResult[] pollResults;
}

struct SelectFDSet
{
nothrow @safe:

    static struct SelectFD
    {
        SocketHandle handle;
        SelectMode modes;
    }

public:
    /**
     * Add a socket with checking modes (read, write & error)
     * Params:
     *  handle = a valid socket handle to be checked
     *  modes = combination of statuses to be checked for
     */
    ref SelectFDSet add(SocketHandle handle, SelectMode modes) return @trusted
    {
        if (set(handle, modes))
        {
            pollFDs ~= SelectFD(handle, modes);
            version(Posix)
            {
                if (nfds < handle)
                    nfds = handle;
            }
        }
        return this;
    }

    /**
     * Set all members into initial state
     */
    ref SelectFDSet clear() return @trusted
    {
        FD_ZERO(&readSet);
        FD_ZERO(&writeSet);
        FD_ZERO(&errorSet);
        readSetCount = writeSetCount = errorSetCount = 0;
        version(Posix) nfds = 0;
        pollFDs = [];
        pollResults = [];
        return this;
    }

    /**
     * Returns number of checking sockets
     */
    int length() const
    {
        return cast(int)pollFDs.length;
    }

    /**
     * Prepare state vars for a 'select' api call
     */
    ref SelectFDSet reset() return @trusted
    {
        FD_ZERO(&readSet);
        FD_ZERO(&writeSet);
        FD_ZERO(&errorSet);
        readSetCount = writeSetCount = errorSetCount = 0;
        pollResults = [];
        foreach (ref fd; pollFDs)
            set(fd.handle, fd.modes);
        return this;
    }

public:
    SelectFD[] pollFDs;
    version(Posix) SocketHandle nfds;
    FDSet readSet, writeSet, errorSet;
    uint readSetCount, writeSetCount, errorSetCount;
    PollResult[] pollResults;

private:
    bool set(SocketHandle handle, const(SelectMode) modes) @trusted
    {
        bool result = false;

        if (isSelectMode(modes, SelectMode.read))
        {
            FD_SET(handle, &readSet);
            readSetCount++;
            result = true;
        }

        if (isSelectMode(modes, SelectMode.write))
        {
            FD_SET(handle, &writeSet);
            writeSetCount++;
            result = true;
        }

        if (isSelectMode(modes, SelectMode.error))
        {
            FD_SET(handle, &errorSet);
            errorSetCount++;
            result = true;
        }

        return result;
    }
}

struct SocketAddress
{
nothrow @safe:

public:
    this(scope const(IPSocketAddress) address, const(ushort) port) @nogc pure
    {
        if (address.isIPv4)
        {
            this._slen = _sin.sizeof;
            this._sin.sin_addr.s_addr = fromBytes!uint(address.toBytes());
            this._sin.sin_port = htons(port);
        }
        else if (address.isIPv6)
        {
            this._slen = _sin6.sizeof;
            this._sin6.sin6_addr.s6_addr[] = address.toBytes();
            this._sin6.sin6_port = htons(port);
            this._sin6.sin6_scope_id = address.scopeId;
        }
        else
            this._slen = 0;
    }

    this(scope const(ubyte)[] sockAddr) @nogc pure @trusted
    {
        if (sockAddr.length == _sin.sizeof)
        {
            this._slen = _sin.sizeof;
            this._sin = *cast(sockaddr_in*)&sockAddr[0];
        }
        else if (sockAddr.length == _sin6.sizeof)
        {
            this._slen = _sin6.sizeof;
            this._sin6 = *cast(sockaddr_in6*)&sockAddr[0];
        }
        else
            this._slen = 0;
    }

    int opCmp(scope const(SocketAddress) rhs) const @nogc nothrow pure scope
    {
        int result;
        if (this.isIPv4 && rhs.isIPv4)
        {
            result = cmp(this._sin.sin_addr.s_addr, rhs._sin.sin_addr.s_addr);
            if (result == 0)
                result = cmp(this._sin.sin_port, rhs._sin.sin_port);
        }
        else if (this.isIPv6 && rhs.isIPv6)
        {
            result = cmp(this._sin6.sin6_addr.s6_addr[], rhs._sin6.sin6_addr.s6_addr[]);
            if (result == 0)
                result = cmp(this._sin6.sin6_scope_id, rhs._sin6.sin6_scope_id);
            if (result == 0)
                result = cmp(this._sin6.sin6_port, rhs._sin6.sin6_port);
        }
        else
            result = cmp(this._slen, rhs._slen);
        return result;
    }

    bool opEquals(scope const(SocketAddress) rhs) const @nogc nothrow pure scope
    {
        return opCmp(rhs) == 0;
    }

    IPSocketAddress toIPAddress() const nothrow pure
    {
        return isIPv4
            ? IPSocketAddress(_sin.sin_addr.s_addr)
            : (isIPv6 ? IPSocketAddress(_sin6.sin6_addr.s6_addr[], scopeId) : IPSocketAddress.init);
    }

    string toString() const nothrow pure
    {
        auto address = toIPAddress();
        return address.isIPv4
            ? IPv4AddressHelper.toString(address._ipvNumbers[0..IPSocketAddress.maxIPv4AddressBytes], port)
            : (address.isIPv6
                ? IPv6AddressHelper.toString(address._ipvNumbers[0..IPSocketAddress.maxIPv6AddressBytes], address.scopeId, port)
                : null);
    }

    @property int slen() @nogc pure
    {
        return cast(int)_slen;
    }

    @property const(sockaddr)* sval() @nogc pure return
    {
        return isIPv4
            ? cast(const(sockaddr)*)&_sin
            : (isIPv6 ? cast(const(sockaddr)*)&_sin6 : null);
    }

    @property AddressFamily family() const @nogc nothrow pure
    {
        return isIPv4
            ? AddressFamily.ipv4
            : (isIPv6 ? AddressFamily.ipv6 : AddressFamily.unspecified);
    }

    @property bool isIPv4() const @nogc nothrow pure
    {
        return _slen == _sin.sizeof;
    }

    @property bool isIPv6() const @nogc nothrow pure
    {
        return _slen == _sin6.sizeof;
    }

    @property ushort port() const @nogc nothrow pure
    {
        return isIPv4
            ? ntohs(_sin.sin_port)
            : (isIPv6 ? ntohs(_sin6.sin6_port) : 0);
    }

    @property uint scopeId() const @nogc nothrow pure
    {
        return isIPv6 ? _sin6.sin6_scope_id : 0;
    }

package(pham.io):
    this(scope const(sockaddr)* ai_addr, const(size_t) ai_addrLen) nothrow pure @trusted
    {
        if (ai_addrLen == _sin.sizeof)
        {
            this._slen = _sin.sizeof;
            this._sin = *cast(sockaddr_in*)ai_addr;
        }
        else if (ai_addrLen == _sin6.sizeof)
        {
            this._slen = _sin6.sizeof;
            this._sin6 = *cast(sockaddr_in6*)ai_addr;
        }
        else
            this._slen = 0;
    }

private:
    sockaddr_in6 _sin6;
    sockaddr_in _sin;
    size_t _slen;
}

struct SocketOptionItem
{
    int level;
    int name;
}

enum SocketOptionItems : SocketOptionItem
{
    acceptConnection = SocketOptionItem(SOL_SOCKET, SO_ACCEPTCONN), /// get whether socket is accepting connections
    broadcast = SocketOptionItem(SOL_SOCKET, SO_BROADCAST), /// broadcast for datagram sockets
    debug_ = SocketOptionItem(SOL_SOCKET, SO_DEBUG), /// enable socket debugging
    dontRoute = SocketOptionItem(SOL_SOCKET, SO_DONTROUTE), /// send only to directly connected hosts
    error = SocketOptionItem(SOL_SOCKET, SO_ERROR), /// get pending socket errors
    ipv6Only = SocketOptionItem(IPPROTO_IPV6, IPV6_V6ONLY),
    keepAlive = SocketOptionItem(SOL_SOCKET, SO_KEEPALIVE), /// enable keep-alive messages on connection-based sockets
    linger = SocketOptionItem(SOL_SOCKET, SO_LINGER), /// linger option
    noDelay = SocketOptionItem(IPPROTO_TCP, TCP_NODELAY),
    oobInline = SocketOptionItem(SOL_SOCKET, SO_OOBINLINE), /// inline receive out-of-band data
    rcvLowat = SocketOptionItem(SOL_SOCKET, SO_RCVLOWAT), /// min number of input bytes to process
    receiveBufferSize = SocketOptionItem(SOL_SOCKET, SO_RCVBUF), /// get or set receive buffer size
    receiveTimeout = SocketOptionItem(SOL_SOCKET, SO_RCVTIMEO), /// receiving timeout
    reuseAddress = SocketOptionItem(SOL_SOCKET, SO_REUSEADDR), /// reuse bind address
    sendBufferSize = SocketOptionItem(SOL_SOCKET, SO_SNDBUF), /// get or set send buffer size
    sendTimeout = SocketOptionItem(SOL_SOCKET, SO_SNDTIMEO), /// sending timeout
    sndLowat = SocketOptionItem(SOL_SOCKET, SO_SNDLOWAT), /// min number of output bytes to process
    type = SocketOptionItem(SOL_SOCKET, SO_TYPE), /// get socket type
    useLoopBack = SocketOptionItem(SOL_SOCKET, SO_USELOOPBACK), /// Use the local loopback address when sending data from this socket. This option should only be used when all data sent will also be received locally
}

//pragma(msg, sockaddr_in.sizeof); // 16
//pragma(msg, sockaddr_in6.sizeof); // 28

pragma(inline, true)
bool canBlockingSocketType(SocketType type) @nogc nothrow pure
{
    return type == SocketType.stream
        || type == SocketType.seqPacket
        || type == SocketType.unspecified;
}

pragma(inline, true)
bool isSelectMode(SelectMode modes, SelectMode mode) @nogc nothrow pure
{
    return (modes & mode) != 0;
}

string toErrorInfo(AddressFamily family, SocketType type, Protocol protocol) nothrow pure
{
    return "family: " ~ toName!AddressFamily(family) ~ ", type: " ~ toName!SocketType(type) ~ ", protocol: " ~ toName!Protocol(protocol);
}

Linger toSocketLinger(scope const(Duration) duration) @nogc nothrow pure
{
    const r = toSocketTimeClamp(duration.total!"seconds"(), 0, ushort.max);
    Linger result;
    result.l_linger = cast(ushort)r; // seconds
    result.l_onoff = r != 0;
    return result;
}

int toSocketTimeClamp(const(long) n, const(int) min = -1, const(int) max = int.max) @nogc nothrow pure
{
    return n < min ? min : (n > max ? max : cast(int)n);
}

Duration toSocketTimeDur(scope const(TimeVal) timeVal) @nogc nothrow pure
{
    return dur!"msecs"(toSocketTimeMSecs(timeVal));
}

int toSocketTimeMSecs(scope const(TimeVal) timeVal) @nogc nothrow pure
{
    return toSocketTimeClamp((cast(long)timeVal.tv_sec * 1_000) /* seconds */ + (timeVal.tv_usec / 1_000) /* microseconds */);
}

TimeVal toSocketTimeVal(scope const(Duration) timeDur) @nogc nothrow pure
{
    return toSocketTimeVal(timeDur.total!"msecs"());
}

TimeVal toSocketTimeVal(long timeMSecs) @nogc nothrow pure
{
    enum msecsPerSecond = 1_000;
    const r = toSocketTimeClamp(timeMSecs);
    TimeVal result;
    result.tv_sec = r / msecsPerSecond; // seconds
    result.tv_usec = (r % msecsPerSecond) * 1_000; // microseconds
    return result;
}


private:

struct IPv4AddressHelper
{
    import std.ascii : isDigit;
    import pham.utl.utl_array_append : Appender;

@safe:

public:
    static void appendSections(ref Appender!string destination, scope const(ubyte)[] ipv4Address) nothrow pure
    {
        .toString(destination, ipv4Address[0]);
        destination.put('.');
        .toString(destination, ipv4Address[1]);
        destination.put('.');
        .toString(destination, ipv4Address[2]);
        destination.put('.');
        .toString(destination, ipv4Address[3]);
    }

    static ResultIf!IPSocketAddress parse(scope const(char)[] address, const(bool) notImplicitFile = true) nothrow pure
    {
        ResultIf!IPSocketAddress error(size_t index) nothrow pure
        {
            import std.conv : to;

            return index != size_t.max
                ? ResultIf!IPSocketAddress.error(0, "Invalid IPv4 address: " ~ address.idup ~ " at position " ~ index.to!string())
                : ResultIf!IPSocketAddress.error(0, "Invalid IPv4 address: " ~ address.idup);
        }

        if (address.length == 0)
            return error(size_t.max);

        enum Base : int { decimal = 10, hex = 16, octal = 8 }
        enum DotParts : ubyte { p0, p1, p2, p3 }
        enum maxIPv4Value = uint.max;

        ulong[4] parts;
        ulong currentValue;
        int dotCount; // Limit 3
        Base numberBase = Base.decimal;
        char ch;
        bool atLeastOneChar;

        // Parse one dotted section at a time
        size_t current = 0;
        for (; current < address.length; current++)
        {
            ch = address[current];
            currentValue = 0;

            // Figure out what base this section is in
            numberBase = Base.decimal;
            if (ch == '0')
            {
                atLeastOneChar = true;
                numberBase = Base.octal;
                current++;
                if (current < address.length)
                {
                    ch = address[current];
                    if (ch == 'x' || ch == 'X')
                    {
                        atLeastOneChar = false;
                        numberBase = Base.hex;
                        current++;
                    }
                }
            }

            // Parse this section
            for (; current < address.length; current++)
            {
                ch = address[current];
                int digitValue;

                if ((numberBase == Base.decimal || numberBase == Base.hex) && isDigit(ch))
                    digitValue = ch - '0';
                else if (numberBase == Base.octal && '0' <= ch && ch <= '7')
                    digitValue = ch - '0';
                else if (numberBase == Base.hex && 'a' <= ch && ch <= 'f')
                    digitValue = ch + 10 - 'a';
                else if (numberBase == Base.hex && 'A' <= ch && ch <= 'F')
                    digitValue = ch + 10 - 'A';
                else
                    break; // Invalid/terminator

                currentValue = (currentValue * numberBase) + digitValue;

                 // Overflow?
                if (currentValue > maxIPv4Value)
                    return error(current);

                atLeastOneChar = true;
            }

            if (current < address.length && address[current] == '.')
            {
                // Max of 3 dots and 4 segments
                if (dotCount >= 3)
                    return error(current);

                // Only the last segment can be more than 255 (if there are less than 3 dots)
                if (currentValue > 0xff)
                    return error(current);

                // No empty segmets: 1...1
                if (!atLeastOneChar)
                    return error(current);

                parts[dotCount++] = currentValue;
                atLeastOneChar = false;
                continue;
            }
            // We don't get here unless We find an invalid character or a terminator
            break;
        }

        // Empty trailing segment: 1.1.1.
        if (!atLeastOneChar)
            return error(current);
        else if (current >= address.length)
        {
            // end of string, allowed
        }
        else if ((ch = address[current]) == '/' || ch == '\\' || (notImplicitFile && (ch == ':' || ch == '?' || ch == '#')))
        {
            // end with special character, allowed
        }
        // not a valid terminating character
        else
            return error(current);

        parts[dotCount] = currentValue;

        ResultIf!IPSocketAddress ok(DotParts dotParts) nothrow pure
        {
            final switch (dotParts)
            {
                case DotParts.p0: // 0xFFFFFFFF
                    return ResultIf!IPSocketAddress.ok(IPSocketAddress(htonl(cast(uint)parts[0])));
                case DotParts.p1: // 0xFF.0xFFFFFF
                    return ResultIf!IPSocketAddress.ok(IPSocketAddress(htonl(cast(uint)((parts[0] << 24) | (parts[1] & 0xffffff)))));
                case DotParts.p2: // 0xFF.0xFF.0xFFFF
                    return ResultIf!IPSocketAddress.ok(IPSocketAddress([cast(ubyte)parts[0], cast(ubyte)parts[1], cast(ubyte)((parts[2] >> 8) & 0xff), cast(ubyte)(parts[2] & 0xff)]));
                case DotParts.p3: // 0xFF.0xFF.0xFF.0xFF
                    return ResultIf!IPSocketAddress.ok(IPSocketAddress([cast(ubyte)parts[0], cast(ubyte)parts[1], cast(ubyte)parts[2], cast(ubyte)parts[3]]));
            }
        }

        // Parsed, reassemble and check for overflows
        switch (dotCount)
        {
            case 0: // 0xFFFFFFFF
                if (parts[0] > maxIPv4Value)
                    return error(size_t.max);
                return ok(DotParts.p0);
            case 1: // 0xFF.0xFFFFFF
                if (parts[1] > 0xffffff)
                    return error(size_t.max);
                return ok(DotParts.p1);
            case 2: // 0xFF.0xFF.0xFFFF
                if (parts[2] > 0xffff)
                    return error(size_t.max);
                return ok(DotParts.p2);
            case 3: // 0xFF.0xFF.0xFF.0xFF
                if (parts[3] > 0xff)
                    return error(size_t.max);
                return ok(DotParts.p3);
            default:
                return error(size_t.max);
        }
    }

    static ResultIf!(ubyte[IPSocketAddress.maxIPv4AddressBytes]) parseHostNumber(scope const(char)[] address) nothrow pure
    {
        ResultIf!(ubyte[IPSocketAddress.maxIPv4AddressBytes]) error(size_t index) nothrow pure
        {
            import std.conv : to;

            return index != size_t.max
                ? ResultIf!(ubyte[IPSocketAddress.maxIPv4AddressBytes]).error(0, "Invalid IPv4 address: " ~ address.idup ~ " at position " ~ index.to!string())
                : ResultIf!(ubyte[IPSocketAddress.maxIPv4AddressBytes]).error(0, "Invalid IPv4 address: " ~ address.idup);
        }

        ubyte[IPSocketAddress.maxIPv4AddressBytes] result;

        size_t c, i;
        while (c < address.length)
        {
            if (i == IPSocketAddress.maxIPv4AddressBytes)
                return error(c);

            const c2 = c;
            int b;
            for (; c < address.length && address[c] != '.' && address[c] != ':'; ++c)
            {
                ubyte cb;
                if (!cvtDigit(address[c], cb))
                    return error(c);
                b = (b * 10) + cb;
            }
            if (b > 0xff)
                return error(c2);
            result[i++] = cast(byte)b;
            c++;
        }

        if (i != IPSocketAddress.maxIPv4AddressBytes)
            return error(size_t.max);

        return ResultIf!(ubyte[IPSocketAddress.maxIPv4AddressBytes]).ok(result);
    }

    static string toString(scope const(ubyte)[] ipv4Address, ushort port) nothrow pure
    {
        auto buffer = Appender!string(IPSocketAddress.maxIPv4StringLength + (port ? 6+1: 0));
        return toString(buffer, ipv4Address, port)[];
    }

    static ref Appender!string toString(return ref Appender!string destination, scope const(ubyte)[] ipv4Address, ushort port) nothrow pure
    {
        appendSections(destination, ipv4Address);
        if (port)
        {
            destination.put(':');
            .toString(destination, port);
        }
        return destination;
    }
}

struct IPv6AddressHelper
{
    import std.ascii : LetterCase;
    import pham.utl.utl_array_append : Appender;

@safe:
    enum maxIPv6AddressShorts = IPSocketAddress.maxIPv6AddressBytes / 2;

public:
    // Appends each of the numbers in address in indexed range [fromInclusive, toExclusive),
    // while also replacing the longest sequence of 0s found in that range with "::", as long
    // as the sequence is more than one 0.
    static void appendSections(ref Appender!string destination, scope const(ushort)[] ipv6Address) nothrow pure
    {
        // Find the longest sequence of zeros to be combined into a "::"
        const r = findCompressionRange(ipv6Address);
        bool needsColon = false;

        // Handle a zero sequence if there is one
        if (r[0] >= 0)
        {
            // Output all of the numbers before the zero sequence
            foreach (i; 0..r[0])
            {
                if (needsColon)
                    destination.put(':');
                .toString!16(destination, ntohs(ipv6Address[i]), 0, '0', LetterCase.lower);
                needsColon = true;
            }

            // Output the zero sequence if there is one
            destination.put("::");
            needsColon = false;
        }

        // Output everything after the zero sequence
        foreach (i; r[1]..ipv6Address.length)
        {
            if (needsColon)
                destination.put(':');
            .toString!16(destination, ntohs(ipv6Address[i]), 0, '0', LetterCase.lower);
            needsColon = true;
        }
    }

    static const(ubyte)[] extractIPv4Address(return scope const(ushort)[] ipv6Address) nothrow pure
    {
        return cast(const(ubyte)[])ipv6Address[6..8];
    }

    // RFC 5952 Section 4.2.3
    // Longest consecutive sequence of zero segments, minimum 2.
    // On equal, first sequence wins. <-1, -1> for no compression.
    static ptrdiff_t[2] findCompressionRange(scope const(ushort)[] ipv6Address) nothrow pure
    {
        int longestSequenceLength, longestSequenceStart = -1, currentSequenceLength;

        foreach (i; 0..ipv6Address.length)
        {
            if (ipv6Address[i] == 0)
            {
                currentSequenceLength++;
                if (currentSequenceLength > longestSequenceLength)
                {
                    longestSequenceLength = currentSequenceLength;
                    longestSequenceStart = cast(int)i - currentSequenceLength + 1;
                }
            }
            else
            {
                currentSequenceLength = 0;
            }
        }

        return longestSequenceLength > 1
            ? [longestSequenceStart, longestSequenceStart + longestSequenceLength]
            : [-1, 0];
    }

    static ResultIf!IPSocketAddress parse(scope const(char)[] address) nothrow
    {
        ResultIf!IPSocketAddress error(size_t index) nothrow pure
        {
            import std.conv : to;

            return index != size_t.max
                ? ResultIf!IPSocketAddress.error(0, "Invalid IPv6 address: " ~ address.idup ~ " at position " ~ index.to!string())
                : ResultIf!IPSocketAddress.error(0, "Invalid IPv6 address: " ~ address.idup);
        }

        if (address.length == 0)
            return error(size_t.max);

        const(char)[] scopeId;
        ushort[maxIPv6AddressShorts] numbers;
        ptrdiff_t index, prefixLength, start, compressorIndex = -1;
        int number;
        bool numberIsValid;

        bool addNumber() nothrow pure
        {
            if (index < numbers.length)
            {
                numbers[index++] = htons(cast(ushort)number);
                number = 0;
                numberIsValid = false;
                return true;
            }
            return false;
        }

        //This used to be a class instance member but have not been used so far
        if (address[start] == '[')
            ++start;

        ptrdiff_t i = start;
        for (; i < address.length && address[i] != ']'; )
        {
            switch (address[i])
            {
                case '%':
                    if (numberIsValid)
                    {
                        if (!addNumber())
                            return error(i);
                    }

                    start = i+1;
                    for (++i; i < address.length && address[i] != ']' && address[i] != '/'; ++i)
                    {}

                    scopeId = address[start..i];
                    // ignore prefix if any
                    for (; i < address.length && address[i] != ']'; ++i)
                    {}
                    break;

                case ':':
                    if (!addNumber())
                        return error(i);
                    ++i;
                    if (address[i] == ':')
                    {
                        compressorIndex = index;
                        ++i;
                    }
                    else if (compressorIndex < 0 && index < 6)
                    {
                        // no point checking for IPv4 address if we don't
                        // have a compressor or we haven't seen 6 16-bit
                        // numbers yet
                        break;
                    }

                    // check to see if the upcoming number is really an IPv4
                    // address. If it is, convert it to 2 ushort numbers
                    ptrdiff_t j = i;
                    for (; j < address.length &&
                                    (address[j] != ']') &&
                                    (address[j] != ':') &&
                                    (address[j] != '%') &&
                                    (address[j] != '/') &&
                                    (j < i + 4); ++j)
                    {

                        if (address[j] == '.')
                        {
                            // we have an IPv4 address. Find the end of it:
                            // we know that since we have a valid IPv6
                            // address, the only things that will terminate
                            // the IPv4 address are the prefix delimiter '/'
                            // or the end-of-string (which we conveniently
                            // delimited with ']')
                            while (j < address.length && address[j] != ']' && address[j] != '/' && address[j] != '%')
                                ++j;

                            const hostNumber = IPv4AddressHelper.parseHostNumber(address[i..j]);
                            if (hostNumber)
                            {
                                number = (cast(ushort)hostNumber[0] << 8) | hostNumber[1];
                                if (!addNumber())
                                    return error(i);
                                number = (cast(ushort)hostNumber[2] << 8) | hostNumber[3];
                                if (!addNumber())
                                    return error(i);
                                i = j;
                            }
                            else
                            {
                                return error(i);
                            }
                            break;
                        }
                    }
                    break;

                case '/':
                    if (numberIsValid && !addNumber())
                        return error(i);

                    // since we have a valid IPv6 address string, the prefix
                    // length is the last token in the string
                    for (++i; i < address.length && address[i] != ']'; ++i)
                    {
                        prefixLength = (prefixLength * 10) + (address[i] - '0');
                    }
                    break;

                default:
                    ubyte hb;
                    if (!cvtHexDigit(address[i++], hb))
                        return error(i-1);
                    number = (number * 16) + hb;
                    numberIsValid = true;
                    break;
            }
        }

        // add number to the array if its not the prefix length or part of
        // an IPv4 address that's already been handled
        if (numberIsValid && !addNumber())
            return error(size_t.max);

        // if we had a compressor sequence ("::") then we need to expand the
        // numbers array
        if (compressorIndex > 0)
        {
            ptrdiff_t toIndex = maxIPv6AddressShorts - 1;
            ptrdiff_t fromIndex = index - 1;

            // if fromIndex and toIndex are the same, it means that "zero bits" are already in the correct place
            // it happens for leading and trailing compression
            if (fromIndex != toIndex)
            {
                for (ptrdiff_t i2 = index - compressorIndex; i2 > 0; --i2)
                {
                    numbers[toIndex--] = numbers[fromIndex];
                    numbers[fromIndex--] = 0;
                }
            }
        }

        if (scopeId.length)
        {
            auto sc = parseScopeId(scopeId);
            if (sc)
                return ResultIf!IPSocketAddress.ok(IPSocketAddress(cast(const(ubyte)[])numbers, sc.value));
            else
                return error(size_t.max);
        }
        else
            return ResultIf!IPSocketAddress.ok(IPSocketAddress(cast(const(ubyte)[])numbers, 0));
    }

    static ResultIf!uint parseScopeId(scope const(char)[] scopeId) nothrow
    {
        if (scopeId.length == 0)
            return ResultIf!uint.ok(0);

        uint result;
        if (parseIntegral(scopeId, result) == NumericParsedKind.ok)
            return ResultIf!uint.ok(result);

        result = interfaceNameToIndex(scopeId);
        return result != 0
            ? ResultIf!uint.ok(result)
            : ResultIf!uint.error(0, "Invalid scope name: " ~ scopeId.idup);
    }

    // Returns true if the IPv6 address should be formatted with an embedded IPv4 address:
    // ::192.168.1.1
    static bool shouldHaveIpv4Embedded(scope const(ushort)[] ipv6Address) nothrow pure
    {
        // 0:0 : 0:0 : x:x : x.x.x.x
        if (ipv6Address[0] == 0 && ipv6Address[1] == 0 && ipv6Address[2] == 0 && ipv6Address[3] == 0 && ipv6Address[6] != 0)
        {
            // RFC 5952 Section 5 - 0:0 : 0:0 : 0:[0 | FFFF] : x.x.x.x
            if (ipv6Address[4] == 0 && (ipv6Address[5] == 0 || ipv6Address[5] == 0xFFFF))
            {
                return true;
            }
            // SIIT - 0:0 : 0:0 : FFFF:0 : x.x.x.x
            else if (ipv6Address[4] == 0xFFFF && ipv6Address[5] == 0)
            {
                return true;
            }
        }

        // ISATAP
        return ipv6Address[4] == 0 && ipv6Address[5] == 0x5EFE;
    }

    static string toString(scope const(ubyte)[] ipv6Address, uint scopeId, ushort port) nothrow pure
    {
        auto buffer = Appender!string(IPSocketAddress.maxIPv6StringLength + (port ? 6+3: 0));
        return toString(buffer, ipv6Address, scopeId, port)[];
    }

    static ref Appender!string toString(return ref Appender!string destination, scope const(ubyte)[] ipv6Address, uint scopeId, ushort port) nothrow pure
    {
        const ipv6Address2 = cast(const(ushort)[])ipv6Address;

        if (port)
            destination.put('[');

        if (shouldHaveIpv4Embedded(ipv6Address2))
        {
            appendSections(destination, ipv6Address2[0..6]);
            destination.put(':');
            IPv4AddressHelper.appendSections(destination, extractIPv4Address(ipv6Address2));
        }
        else
        {
            appendSections(destination, ipv6Address2);
        }

        if (scopeId != 0)
        {
            destination.put('%');
            .toString(destination, scopeId);
        }

        if (port)
        {
            destination.put(']');
            destination.put(':');
            .toString(destination, port);
        }

        return destination;
    }
}

unittest // toSocketTimeClamp
{
    assert(toSocketTimeClamp(-100) == -1);
    assert(toSocketTimeClamp(100) == 100);
    assert(toSocketTimeClamp(long.max) == int.max);
}

unittest // toSocketTimeDur
{
    assert(toSocketTimeDur(TimeVal(0, -1_000)) == dur!"msecs"(-1), toSocketTimeDur(TimeVal(0, -1_000)).toString ~ " / " ~ dur!"msecs"(-1).toString);
    assert(toSocketTimeDur(TimeVal(0, 0)) == dur!"msecs"(0));
    assert(toSocketTimeDur(TimeVal(100, 0)) == dur!"msecs"(100 * 1_000));
}

unittest // toSocketTimeMSecs
{
    assert(toSocketTimeMSecs(TimeVal(-1, 0)) == -1);
    assert(toSocketTimeMSecs(TimeVal(0, -1_000)) == -1);
    assert(toSocketTimeMSecs(TimeVal(0, 0)) == 0);
    assert(toSocketTimeMSecs(TimeVal(100, 0)) == 100 * 1_000);
}

unittest // toSocketTimeVal
{
    assert(toSocketTimeVal(dur!"msecs"(-1)) == TimeVal(0, -1_000));
    assert(toSocketTimeVal(dur!"seconds"(0)) == TimeVal(0, 0));
    assert(toSocketTimeVal(dur!"seconds"(100)) == TimeVal(100, 0));

    assert(toSocketTimeVal(-1_000) == TimeVal(0, -1_000));
    assert(toSocketTimeVal(100 * 1_000) == TimeVal(100, 0));
    assert(toSocketTimeVal(0) == TimeVal(0, 0));
}

unittest // IPSocketAddress
{
    auto ipv41a = IPSocketAddress(0x0100A8C0u);
    assert(ipv41a.toString() == "192.168.0.1", ipv41a.toString());
    auto ipv41b = IPSocketAddress([0xC0,0xA8,0x00,0x01]);
    assert(ipv41b.toString() == "192.168.0.1");
    assert(ipv41a.toBytes() == ipv41b.toBytes());
    assert(ipv41a == ipv41b);
    assert(ipv41a.mapToIPv6().toBytes() == [0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0xFF,0xC0,0xA8,0x00,0x01]);

    auto ipv6 = IPSocketAddress([0x20,0x01,0x0D,0xB8,0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0x00,0x00,0x42,0x83,0x29], 4);
    assert(ipv6.toString() == "2001:db8::ff00:42:8329%4");

    // Embedded IPv4
    ipv6 = IPSocketAddress([0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0xFF,0xC0,0x00,0x02,0x80]);
    assert(ipv6.toString() == "::ffff:192.0.2.128", ipv6.toString());
    assert(ipv6.mapToIPv4().toBytes() == [0xC0,0x00,0x02,0x80]);
}

unittest // IPSocketAddress.parse
{
    auto ipv4 = IPSocketAddress.parseIPv4("192.168.0.1");
    assert(ipv4.isOK);
    assert(ipv4.toBytes() == [0xC0,0xA8,0x00,0x01]);
    auto ipv4b = IPSocketAddress.parse("192.168.0.1");
    assert(ipv4.value == ipv4b.value);

    auto ipv6 = IPSocketAddress.parseIPv6("2001:db8::ff00:42:8329%4");
    assert(ipv6.isOK, ipv6.errorMessage());
    assert(ipv6.toBytes() == [0x20,0x01,0x0D,0xB8,0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0x00,0x00,0x42,0x83,0x29]);
    assert(ipv6.scopeId == 4);
    auto ipv6b = IPSocketAddress.parse("2001:db8::ff00:42:8329%4");
    assert(ipv6.value == ipv6b.value);

    ipv6 = IPSocketAddress.parseIPv6("::ffff:192.0.2.128");
    assert(ipv6.isOK, ipv6.errorMessage());
    assert(ipv6.toBytes() == [0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0xFF,0xC0,0x00,0x02,0x80]);
    assert(ipv6.scopeId == 0);
}

unittest // SocketAddress
{
    auto ipv4 = SocketAddress(IPSocketAddress.parseIPv4("192.168.0.1"), 99);
    assert(ipv4.toString() == "192.168.0.1:99");

    auto ipv6 = SocketAddress(IPSocketAddress.parseIPv6("2001:db8::ff00:42:8329%4"), 99);
    assert(ipv6.toString() == "[2001:db8::ff00:42:8329%4]:99");
}
