module http.Server;

import hunt.event;
import hunt.io;
import hunt.logging.ConsoleLogger;
import hunt.system.Memory : totalCPUs;
import hunt.util.DateTime;

import std.array;
import std.conv;
import std.json;
import std.socket;
import std.string;

import http.Parser;
import http.Processor;

shared static this() {
	DateTimeHelper.startClock();
}

/**
*/
abstract class AbstractTcpServer {
	protected EventLoopGroup _group = null;
	protected bool _isStarted = false;
	protected Address _address;
	TcpStreamOption _tcpStreamoption;

	this(Address address, int thread = (totalCPUs - 1)) {
		this._address = address;
		_tcpStreamoption = TcpStreamOption.createOption();
		_tcpStreamoption.bufferSize = 1024*2;
		_group = new EventLoopGroup(cast(uint) thread);
	}

	@property Address bindingAddress() {
		return _address;
	}

	void start() {
		if (_isStarted)
			return;
		_isStarted = true;

		Socket server = new TcpSocket();
		server.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		server.bind(new InternetAddress("0.0.0.0", 8080));
		server.listen(8192);

		debug trace("Launching server");

		_group.start();

		while (true) {
			try {
				version (HUNT_DEBUG)
					trace("Waiting for server.accept()");
				Socket socket = server.accept();
				version (HUNT_DEBUG) {
					infof("new client from %s, fd=%d", socket.remoteAddress.toString(), socket.handle());
				}
				EventLoop loop = _group.nextLoop();
				TcpStream stream = new TcpStream(loop, socket, _tcpStreamoption);
				onConnectionAccepted(stream);
			} catch (Exception e) {
				warningf("Failure on accept %s", e);
				break;
			}
		}
		_isStarted = false;
	}

	protected void onConnectionAccepted(TcpStream client);

	void stop() {
		if (!_isStarted)
			return;
		_isStarted = false;
		_group.stop();
	}
}

alias ProcessorCreater = HttpProcessor delegate(TcpStream client);

/**
*/
class HttpServer : AbstractTcpServer {

	ProcessorCreater processorCreater;

	this(string ip, ushort port, int thread = (totalCPUs - 1)) {
		super(new InternetAddress(ip, port), thread);
	}

	this(Address address, int thread = (totalCPUs - 1)) {
		super(address, thread);
	}

	override protected void onConnectionAccepted(TcpStream client) {
		if(processorCreater !is null) {
			HttpProcessor httpProcessor = processorCreater(client);
			httpProcessor.run();
		}
	}

	HttpServer onProcessorCreate(ProcessorCreater handler) {
		this.processorCreater = handler;
		return this;
	}
}
