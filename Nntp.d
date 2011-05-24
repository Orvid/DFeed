module Nntp;

import std.date;
import std.string;

import Team15.ASockets;
import Team15.Timing;
import Team15.Utils;

const POLL_PERIOD = 5*TicksPerSecond;

class NntpClient
{
private:
	LineBufferedSocket conn;
	d_time last;
	string[] reply;
	string server;
	int queued;
	string lastTime;

	void reconnect()
	{
		queued = 0;
		lastTime = null;
		conn.connect(server, 119);
	}

	void onDisconnect(ClientSocket sender, string reason, DisconnectType type)
	{
		setTimeout(&reconnect, 10*TicksPerSecond);
	}

	void onReadLine(LineBufferedSocket s, string line)
	{
		debug(NNTP) std.stdio.writefln("> %s", line);

		if (line == ".")
		{
			onReply(reply);
			reply = null;
		}
		else
		if (reply.length==0 && (line.startsWith("200") || line.startsWith("111")))
			onReply([line]);
		else
			reply ~= line;
	}

	void send(string line)
	{
		debug(NNTP) std.stdio.writefln("< %s", line);
		conn.send(line);
	}

	void onReply(string[] reply)
	{
		auto firstLine = split(reply[0]);
		switch (firstLine[0])
		{
			case "200":
				send("DATE");
				break;
			case "111":
			{	
				auto time = firstLine[1];
				assert(time.length == 14);
				if (lastTime is null)
					setTimeout(&poll, POLL_PERIOD);
				lastTime = time;
				break;
			}
			case "230":
			{
				auto messages = reply[1..$];
				foreach (message; messages)
					send("HEAD " ~ message);
				int queued = messages.length;
				if (queued==0)
					setTimeout(&poll, POLL_PERIOD);
				break;
			}
			case "221":
			{
				auto message = reply[1..$];
				if (handleMessage)
					handleMessage(message);
				queued--;
				if (queued==0)
					setTimeout(&poll, POLL_PERIOD);
				break;
			}
			default:
				throw new Exception("Unknown reply: " ~ reply[0]);
		}
	}

	void poll()
	{
		send("DATE");
		send("NEWNEWS * "~ lastTime[0..8] ~ " " ~ lastTime[8..14] ~ " GMT");
	}

public:
	void connect(string server)
	{
		this.server = server;

		conn = new LineBufferedSocket(60*TicksPerSecond);
		conn.handleDisconnect = &onDisconnect;
		conn.handleReadLine = &onReadLine;
		reconnect();
	}

	void delegate(string[] head) handleMessage;
}