import vibe.d;

final class WebChat {
	private Room[string] m_rooms;


	// GET /
	void get()
	{
		render!("index.dt");
	}

	// GET /room?id=...&name=...
	void getRoom(string id, string name)
	{
		auto messages = getOrCreateRoom(id).messages;
		render!("room.dt", id, name, messages);
	}

	// GET /ws?room=...&name=...
	void getWS(string room, string name, scope WebSocket socket)
	{
		auto r = getOrCreateRoom(room);
		
		auto writer = runTask({
			auto next_message = r.messages.length;
			
			while (socket.connected) {
				while (next_message < r.messages.length)
					socket.send(r.messages[next_message++]);
				r.waitForMessage(next_message);
			}
		});
		
		while (socket.waitForData) {
			auto message = socket.receiveText();
			if (message.length) r.addMessage(name, message);
		}

		writer.join(); // wait for writer task to exit
	}

	void postRoom(string id, string name, string message)
	{
		if (message.length)
			getOrCreateRoom(id).addMessage(name, message);
		redirect("room?id="~id.urlEncode~"&name="~name.urlEncode);
	}

	private Room getOrCreateRoom(string id)
	{
		if (auto pr = id in m_rooms) return *pr;
		return m_rooms[id] = new Room;
	}
}

final class Room {
	string[] messages;
	ManualEvent messageEvent;

	this()
	{
		messageEvent = createManualEvent();
	}

	void addMessage(string name, string message)
	{
		messages ~= name ~ ": " ~ message;
		messageEvent.emit();
	}

	void waitForMessage(size_t next_message)
	{
		while (messages.length <= next_message)
			messageEvent.wait();
	}
}

shared static this()
{
	// the router will match incoming http requests to the proper routes
	auto router = new URLRouter;
	// registers each method of WebChat in the router
	router.registerWebInterface(new WebChat);
	// match incoming requests to files in the public/ folder
	router.get("*", serveStaticFiles("public/"));

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	listenHTTP(settings, router);
	logInfo("http://127.0.0.1:8080/");
}
