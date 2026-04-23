/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2026 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.io.io_socket_service;

import core.atomic : cas, atomicLoad, atomicStore;
import core.thread : Thread;
import core.sync.mutex : Mutex;
import core.time : Duration, dur;
import std.datetime.stopwatch : StopWatch;

debug(debug_pham_io_io_socket_service) import pham.io.io_debug;
import pham.utl.utl_object : RAIIMutex;
import pham.utl.utl_dlink_list;
public import pham.io.io_socket;

@safe:

class SocketServerInfo
{
@safe:

    // Returns non-zero to stop
    alias ErrorHandler = int delegate(ResultStatus error, SocketServerClient client, SocketServer server, Exception e) nothrow;
    alias ServiceHandler = int delegate(SocketServerClient client, SocketServer server);
    alias DoneQueryHandler = bool delegate(SocketServer server) nothrow;
    alias EventHandler = void delegate(SocketServer server) nothrow;

    string address;
    SocketPort port;
    ServiceHandler serviceHandler;
    Duration acceptTimeout; // Optional
    EventHandler beginHandler; // Optional
    DoneQueryHandler doneQueryHandler; // Optional
    EventHandler endHandler; // Optional
    ErrorHandler errorHandler; // Optional
}

class SocketServer
{
@safe:

public:
    this(SocketServerInfo info) nothrow
    {
        this._info = info;
        this._mutex = new Mutex();
    }

    void start() @trusted
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        if (cas(&_stopSignal, stopIndicator, startingIndicator))
        {
            _acceptedCount = 0;
            _thread = new Thread(&run);
            _thread.start();

            // Wait a bit for preparing a listening-connection in thread
            Thread.sleep(dur!"msecs"(10));
        }
    }

    void stop() nothrow
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        if (cas(&_stopSignal, startIndicator, stopIndicator))
        {
            auto lserverSocket = _serverSocket;
            if (lserverSocket !is null && cas(&_serverSocket, lserverSocket, null))
                lserverSocket.close();
        }
    }

    void waitFor() @trusted
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        auto lthread = _thread;
        if (lthread !is null && cas(&_thread, lthread, null))
            lthread.join(false);

        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "(exit)");
    }

    @property final size_t acceptedCount() const nothrow
    {
        return atomicLoad(_acceptedCount);
    }

    @property final bool active() const nothrow
    {
        auto lserverSocket = atomicLoad(_serverSocket);
        if (atomicLoad(_stopSignal) != startIndicator)
            return false;

        return lserverSocket !is null && lserverSocket.active;
    }

    @property final size_t activeClientCount() const nothrow
    {
        return atomicLoad(_activeClientCount);
    }

    @property final SocketServerInfo info() nothrow pure
    {
        return _info;
    }

    @property final StopWatch startTime() const nothrow
    {
        return _startTime;
    }

protected:
    final void attach(SocketServerClient serverClient)
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        auto raiiMutex = RAIIMutex(_mutex);
        _serverClients.insertEnd(serverClient);
        _acceptedCount++;
        _activeClientCount++;
    }

    void cleanup()
    {
        auto lserverSocket = _serverSocket;
        if (lserverSocket !is null && cas(&_serverSocket, lserverSocket, null))
            lserverSocket.close();

        stopServerClients();

        atomicStore(_thread, null); // No reference so it will be cleanup
    }

    final void detach(SocketServerClient serverClient)
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        auto raiiMutex = RAIIMutex(_mutex);
        _serverClients.remove(serverClient);
        _activeClientCount--;
    }

    bool prepare()
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        auto bindInfo = BindInfo(_info.address, _info.port);
        auto lserverSocket = new Socket(bindInfo);
        if (lserverSocket.lastError.isOK)
            lserverSocket.listen(bindInfo.backLog);

        if (lserverSocket.lastError.isError)
        {
            auto lastError = lserverSocket.lastError;
            lserverSocket.close();
            cleanup();
            if (_info.errorHandler !is null)
                _info.errorHandler(lastError, null, this, null);
            return false;
        }

        atomicStore(_serverSocket, lserverSocket);
        return true;
    }

    void run()
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        _startTime.start();

        if (!prepare())
        {
            atomicStore(_stopSignal, stopIndicator);
            return;
        }

        atomicStore(_stopSignal, startIndicator);
        scope (exit)
        {
            cleanup();
            atomicStore(_stopSignal, stopIndicator); // Last operation for marking as completely stopped
        }

        auto acceptTimeout = _info.acceptTimeout;
        if (!acceptTimeout.isTimeout() && _info.doneQueryHandler !is null)
            acceptTimeout = dur!"msecs"(100);

        if (_info.beginHandler !is null)
            _info.beginHandler(this);

        while (auto lserverSocket = atomicLoad(_serverSocket))
        {
            if (!active)
                break;

            if (_info.doneQueryHandler !is null && _info.doneQueryHandler(this))
                break;

            Socket peerSocket;
            if (lserverSocket.accept(peerSocket, acceptTimeout) == ResultCode.ok)
            {
                if (active)
                {
                    auto serverClient = new SocketServerClient(this, peerSocket);
                    serverClient.start();
                }
                else
                    peerSocket.close();
            }
        }

        if (_info.endHandler !is null)
            _info.endHandler(this);

        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "(exit)");
    }

    final void stopServerClients() nothrow
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        // Must get a copy
        auto raiiMutex = RAIIMutex(_mutex);
        auto lserverClients = _serverClients[];
        raiiMutex.unlock();

        foreach (serverClient; lserverClients)
            serverClient.stop();
    }

protected:
    SocketServerInfo _info;
    Mutex _mutex;
    Socket _serverSocket;
    Thread _thread;
    size_t _acceptedCount;
    size_t _activeClientCount;
    StopWatch _startTime;
    shared int _stopSignal;

private:
    SocketServerClientTypes.DLinkList _serverClients;
}

mixin DLinkTypes!SocketServerClient SocketServerClientTypes;

class SocketServerClient
{
@safe:

public:
    this(SocketServer socketServer, Socket peerSocket) nothrow
    {
        this._socketServer = socketServer;
        this._peerSocket = peerSocket;
        this._info = socketServer.info;
    }

    void start() @trusted
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        if (cas(&_stopSignal, stopIndicator, startingIndicator))
        {
            _thread = new Thread(&run);
            _thread.start();
        }
    }

    void stop() nothrow
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        if (cas(&_stopSignal, startIndicator, stopIndicator))
        {
            auto lpeerSocket = _peerSocket;
            if (lpeerSocket !is null && cas(&_peerSocket, lpeerSocket, null))
                lpeerSocket.close();
        }
    }

    void waitFor() @trusted
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        auto lthread = _thread;
        if (lthread !is null && cas(&_thread, lthread, null))
            lthread.join(false);

        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "(exit)");
    }

    @property final bool active() const nothrow
    {
        auto lpeerSocket = atomicLoad(_peerSocket);
        if (atomicLoad(_stopSignal) != startIndicator)
            return false;

        return lpeerSocket !is null && lpeerSocket.active
            && _socketServer !is null && _socketServer.active;
    }

    @property final SocketServerInfo info() nothrow pure
    {
        return _info;
    }

    @property final Socket socket() nothrow
    {
        return _peerSocket;
    }

    @property final StopWatch startTime() const nothrow
    {
        return _startTime;
    }

protected:
    void run()
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        _startTime.start();

        _socketServer.attach(this);
        atomicStore(_stopSignal, startIndicator);
        scope (exit)
        {
            auto lpeerSocket = _peerSocket;
            if (lpeerSocket !is null && cas(&_peerSocket, lpeerSocket, null))
                lpeerSocket.close();

            _socketServer.detach(this);
            atomicStore(_thread, null); // No reference so it will be cleanup
            atomicStore(_stopSignal, stopIndicator); // Last operation for marking as completely stopped
        }

        while (active)
        {
            int r;
            try
            {
                r = _info.serviceHandler(this, _socketServer);
            }
            catch (Exception e)
            {
                auto lastError = ResultStatus.error(-1, e.msg);
                if (_info.errorHandler !is null)
                    r = _info.errorHandler(lastError, this, _socketServer, e);
            }
            if (r != 0)
                break;
        }

        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "(exit)");
    }

protected:
    SocketServerInfo _info;
    Socket _peerSocket;
    SocketServer _socketServer;
    Thread _thread;
    StopWatch _startTime;
    shared int _stopSignal;

private:
    SocketServerClient _next;
    SocketServerClient _prev;
}

class SocketClientInfo
{
@safe:

    // Returns non-zero to stop
    alias ErrorHandler = int delegate(ResultStatus error, SocketClient client, Exception e) nothrow;
    alias ServiceHandler = int delegate(SocketClient client);
    alias EventHandler = void delegate(SocketClient client) nothrow;

    string address;
    SocketPort port;
    Duration connectionTimeout;
    ServiceHandler serviceHandler;
    EventHandler beginHandler; // Optional
    EventHandler endHandler; // Optional
    ErrorHandler errorHandler; // Optional
}

class SocketClient
{
@safe:

public:
    this(SocketClientInfo info) nothrow
    {
        this._info = info;
    }

    void start() @trusted
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        if (cas(&_stopSignal, stopIndicator, startingIndicator))
        {
            _thread = new Thread(&run);
            _thread.start();

            // Wait a bit for making a connection in thread
            Thread.sleep(dur!"msecs"(10));
        }
    }

    void stop() nothrow
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        if (cas(&_stopSignal, startIndicator, stopIndicator))
        {
            auto lclientSocket = _clientSocket;
            if (lclientSocket !is null && cas(&_clientSocket, lclientSocket, null))
                lclientSocket.close();
        }
    }

    void waitFor() @trusted
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        auto lthread = _thread;
        if (lthread !is null && cas(&_thread, lthread, null))
            lthread.join(false);

        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "(exit)");
    }

    @property final bool active() const nothrow
    {
        auto lclientSocket = atomicLoad(_clientSocket);
        if (atomicLoad(_stopSignal) != startIndicator)
            return false;

        return lclientSocket !is null && lclientSocket.active;
    }

    @property final SocketClientInfo info() nothrow pure
    {
        return _info;
    }

    @property final Socket socket() nothrow
    {
        return _clientSocket;
    }

    @property final StopWatch startTime() const nothrow
    {
        return _startTime;
    }

protected:
    void cleanup()
    {
        auto lclientSocket = _clientSocket;
        if (lclientSocket !is null && cas(&_clientSocket, lclientSocket, null))
            lclientSocket.close();

        atomicStore(_thread, null); // No reference so it will be cleanup
    }

    bool prepare()
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        auto connectInfo = ConnectInfo(_info.address, _info.port);
        if (_info.connectionTimeout.isTimeout)
            connectInfo.connectTimeout = _info.connectionTimeout;
        auto lclientSocket = new Socket(connectInfo);
        if (lclientSocket.lastError.isError)
        {
            auto lastError = lclientSocket.lastError;
            lclientSocket.close();
            cleanup();
            if (_info.errorHandler !is null)
                _info.errorHandler(lastError, this, null);
            return false;
        }

        atomicStore(_clientSocket, lclientSocket);
        return true;
    }

    void run()
    {
        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "()");

        _startTime.start();

        if (!prepare())
        {
            atomicStore(_stopSignal, stopIndicator);
            return;
        }

        atomicStore(_stopSignal, startIndicator);
        scope (exit)
        {
            cleanup();
            atomicStore(_stopSignal, stopIndicator); // Last operation for marking as completely stopped
        }

        if (_info.beginHandler !is null)
            _info.beginHandler(this);

        while (active)
        {
            int r;
            try
            {
                r = _info.serviceHandler(this);
            }
            catch (Exception e)
            {
                auto lastError = ResultStatus.error(-1, e.msg);
                if (_info.errorHandler !is null)
                    r = _info.errorHandler(lastError, this, e);
            }
            if (r != 0)
                break;
        }

        if (_info.endHandler !is null)
            _info.endHandler(this);

        debug(debug_pham_io_io_socket_service) debug writeln(__FUNCTION__, "(exit)");
    }

protected:
    SocketClientInfo _info;
    Socket _clientSocket;
    Thread _thread;
    StopWatch _startTime;
    shared int _stopSignal;
}

enum int stopIndicator = 0;
enum int startingIndicator = 1;
enum int startIndicator = 2;

@trusted unittest
{
    import core.atomic : atomicFetchAdd, atomicLoad;
    import std.random : Random, uniform;
    import std.stdio : writeln;

    enum testCount = 2;
    ubyte[][testCount] testDatas;
    //writeln("testDatas[0].length=", testDatas[0].length);
    Random rnd;
    testDatas[0] = new ubyte[](500);
    foreach (i; 0..testDatas[0].length)
        testDatas[0][i] = cast(ubyte)uniform(1, 255, rnd);
    testDatas[1] = new ubyte[](5_000);
    foreach (i; 0..testDatas[1].length)
        testDatas[1][i] = cast(ubyte)uniform(1, 255, rnd);
    size_t serverCount, clientCount;

    SocketPort port = Socket.getUnusedPort();
    if (port == 0)
        port = 30_000;

    bool serverDoneQuery(SocketServer server) nothrow @safe
    {
        return atomicLoad(serverCount) >= testCount;
    }

    int serverError(ResultStatus error, SocketServerClient client, SocketServer server, Exception e) nothrow @safe
    {
        debug writeln(__FUNCTION__, "(error=", error.toString(), ")");

        return 1;
    }

    int serverService(SocketServerClient client, SocketServer server) @safe
    {
        //debug writeln(__FUNCTION__, "()");

        while (atomicLoad(serverCount) < testCount)
        {
            //debug writeln("\t", "serverCount=", serverCount);

            {
                auto readBuffer = new ubyte[](testDatas[serverCount].length);
                auto peerStream = new SocketStream(client.socket);
                auto r = peerStream.read(readBuffer);
                assert(r == testDatas[serverCount].length);
                assert(readBuffer == testDatas[serverCount]);
            }

            atomicFetchAdd(serverCount, 1);
        }
        return 1;
    }

    int clientError(ResultStatus error, SocketClient client, Exception e) nothrow @safe
    {
        debug writeln(__FUNCTION__, "(error=", error.toString(), ")");

        return 1;
    }

    int clientService(SocketClient client) @safe
    {
        //debug writeln(__FUNCTION__, "()");

        while (atomicLoad(clientCount) < testCount)
        {
            //debug writeln("\t", "clientCount=", clientCount);

            {
                auto writeBuffer = testDatas[clientCount];
                auto clientStream = new SocketStream(client.socket);
                const w = clientStream.write(writeBuffer);
                assert(w == writeBuffer.length);
            }

            atomicFetchAdd(clientCount, 1);
        }
        return 1;
    }

    serverCount = clientCount = 0;

    auto serverInfo = new SocketServerInfo();
    serverInfo.address = loopbackHost;
    serverInfo.port = port;
    serverInfo.serviceHandler = &serverService;
    serverInfo.errorHandler = &serverError;
    serverInfo.doneQueryHandler = &serverDoneQuery;
    auto server = new SocketServer(serverInfo);
    server.start();

    auto clientInfo = new SocketClientInfo();
    clientInfo.address = loopbackHost;
    clientInfo.port = port;
    clientInfo.serviceHandler = &clientService;
    clientInfo.errorHandler = &clientError;
    auto client = new SocketClient(clientInfo);
    client.start();

    server.waitFor();
    client.waitFor();
}
