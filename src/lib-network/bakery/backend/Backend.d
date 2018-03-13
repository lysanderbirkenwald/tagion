module bakery.backend.Backend;

import vibe.core.core : sleep;
import vibe.core.log;
import vibe.http.fileserver : serveStaticFiles;
import vibe.http.router : URLRouter;
import vibe.http.server;
import vibe.http.websockets : WebSocket, handleWebSockets;

import core.time;
import std.concurrency;
import std.conv : to;
import std.stdio : writeln;

import bakery.hashgraph.Event;
import bakery.Base;
import tango.io.FilePath;

class Backend {

	immutable(FilePath) public_repository;
	private ThreadState _thread_state;
	private HTTPListener _listener;

	this(immutable(FilePath) public_repository) {
		this.public_repository = public_repository;
		writeln("Public path to webserver files: ", public_repository.toString);
	}


	void startWebserver() {	
		auto router = new URLRouter;
		router.get("/", staticRedirect("/index.html"));
		router.get("/ws", handleWebSockets(&handleWebSocketConnection));
		router.get("*", serveStaticFiles(public_repository.toString));

		auto settings = new HTTPServerSettings;
		settings.port = 8080;
		settings.bindAddresses = ["::1", "127.0.0.1"];
		_listener = listenHTTP(settings, router);

	}

	void stopWebserver() {
		_listener.stopListening;
	}



	void handleWebSocketConnection(scope WebSocket socket)
	{
		int counter = 0;
		logInfo("Got new web socket connection.");
		while (true) {
			sleep(1.seconds);
			if (!socket.connected) break;
			counter++;
			logInfo("Sending '%s'.", counter);
			socket.send(counter.to!string);
		}
		logInfo("Client disconnected.");
	}



}

