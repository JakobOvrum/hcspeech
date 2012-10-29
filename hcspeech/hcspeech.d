module hcspeech.hcspeech;

import xchat.plugin;

import speech.synthesis;

import std.algorithm;
import std.array;
import std.conv;
import std.path;
import std.random;
import std.range;
import std.string;

import file = std.file;
import io = std.stdio;

__gshared Synthesizer tts;

/*
 * =========================================
 * Voice Tracking
 * =========================================
 */
__gshared Voice[] allVoices;

struct ChannelInfo
{
	string name;
	uint[] voiceDistribution;

	this(string name)
	{
		this.name = name;
		voiceDistribution = new uint[](allVoices.length);
	}
}

auto findVoices(const(char)[] voiceSpecifier)
{
	voiceSpecifier = voiceSpecifier.toLower();

	return allVoices.filter!(voice => toLower(voice.name).canFind(voiceSpecifier))();
}

Voice* voiceByName(in char[] name)
{
	auto voiceIndex = allVoices.countUntil!((voice, name) => voice.name == name)(name);
	return voiceIndex == -1? null : &allVoices[voiceIndex];
}

__gshared
{
	ChannelInfo[] ttsChannels;
	Voice[string] specifiedUserVoices;
	Voice[string] userVoices;
}

private Voice getUserVoice(ChannelInfo channel, in char[] nick)
{
	if(auto voice = nick in specifiedUserVoices)
		return *voice;

	if(auto voice = nick in userVoices)
		return *voice;

	size_t voiceIndex = 0;
	auto leastUses = uint.max;

	foreach(i, uses; channel.voiceDistribution)
	{
		if(uses < leastUses)
		{
			leastUses = uses;
			voiceIndex = i;
		}
	}

	auto voice = allVoices[voiceIndex];

	userVoices[nick.idup] = voice;
	++channel.voiceDistribution[voiceIndex];

	writefln("Assigned voice to %s: %s", nick, voice.name);

	return voice;
}

/*
* =========================================
* Commands
* =========================================
*/
immutable ttsUsage = "Usage: TTS, toggle Text To Speech for the current channel";

EatMode ttsCommand(in char[][] words, in char[][] words_eol)
{
	auto channel = getInfo("channel");
	auto position = ttsChannels.countUntil!((channel, name) => channel.name == name)(channel);
	if(position == -1)
	{
		ttsChannels ~= ChannelInfo(channel);
		writefln("Started TTS in %s.", channel);
	}
	else
	{
		ttsChannels = ttsChannels.remove!(SwapStrategy.unstable)(position);
		writefln("Stopped TTS in %s.", channel);
	}
	return EatMode.all;
}

immutable voiceListUsage = "Usage: VOICELIST, list available Text To Speech voices";

EatMode voiceListCommand(in char[][] words, in char[][] words_eol)
{
	foreach(i, voice; allVoices)
	{
		writefln("#%s: %s", i + 1, voice.name);
	}
	return EatMode.all;
}

immutable assignVoiceUsage = "Usage: ASSIGNVOICE <nick> <voice name>, " ~
                             "assign a specific voice to a user by voice name.";

EatMode assignVoiceCommand(in char[][] words, in char[][] words_eol)
{
	if(words.length < 3)
	{
		writefln(assignVoiceUsage);
		return EatMode.all;
	}

	auto nick = words[1];
	auto voiceSpecifier = words_eol[2];
		
	auto voices = findVoices(voiceSpecifier);
	if(voices.empty)
	{
		writefln(`No voice found for specifier "%s". Use the VOICELIST command to list available voices.`, voiceSpecifier);
		return EatMode.all;
	}

	auto firstVoice = voices.front;
	voices.popFront();

	if(voices.empty) // Only one voice found
	{
		specifiedUserVoices[nick.idup] = firstVoice;
		writefln("Assigned voice to %s: %s", nick, firstVoice.name);
	}
	else // Ambiguous search
	{
		writefln("Specified name matches multiple voices. Which did you mean?");
		auto app = appender!string();
		
		static if(__VERSION__ < 2060)
		{
			auto names = map!(voice => voice.name)((&firstVoice)[0 .. 1].chain(voices));
			auto joined = joiner(names, ", ");
			copy(joined, app);
		}
		else
		{
			(&firstVoice)[0 .. 1].chain(voices)
				.map!(voice => voice.name)()
				.joiner(", ")
				.copy(app);
		}

		writefln(app.data);
	}

	return EatMode.all;
}

immutable clearVoiceUsage = "Usage: CLEARVOICE <nick>, unassign any previously " ~
                            "assigned voice for the specified user.";

EatMode clearVoiceCommand(in char[][] words, in char[][] words_eol)
{
	if(words.length < 2)
	{
		writefln(clearVoiceUsage);
	}
	else
	{
		auto nick = words[1];
		if(nick in specifiedUserVoices)
		{
			specifiedUserVoices.remove(nick.idup); // Ew, idup :(
			writefln("Voice cleared for user %s.", nick);
		}
		else
		{
			writefln("User %s doesn't have an assigned voice.", nick);
		}
	}
	return EatMode.all;
}

immutable assignedVoicesUsage = "Usage: ASSIGNEDVOICES [nick filter], list assigned voices.";

EatMode assignedVoicesCommand(in char[][] words, in char[][] words_eol)
{
	if(words.length < 2)
	{
		if(specifiedUserVoices.length == 0)
			writefln("There are no assigned voices.");
		else
		{
			foreach(nick, voice; specifiedUserVoices)
				writefln("%s: %s", nick, voice.name);
		}
	}
	else
	{
		auto nickFilter = toLower(words[1]);
		auto matches = specifiedUserVoices.keys().filter!(nick => toLower(nick).canFind(nickFilter))();
		if(matches.empty)
			writefln(`Found no assigned voices with the search "%s".`, words[1]);
		else
		{
			foreach(nick; matches)
				writefln("%s: %s", nick, specifiedUserVoices[nick].name);
		}
	}
	return EatMode.all;
}

immutable ttsVolumeUsage = "Usage: TTSVOLUME [new volume in the range 0-100], set or display TTS volume.";

EatMode ttsVolumeCommand(in char[][] words, in char[][] words_eol)
{
	if(words.length > 1)
	{
		auto volume = to!uint(words[1]);
		if(volume > 100)
			writefln("Volume level must be in the range 0-100.");
		else
			tts.volume = volume;
	}
	else
	{
		writefln("TTS volume is %s/100", tts.volume);
	}
	return EatMode.all;
}

/*
* =========================================
* TTS Hooks
* =========================================
*/
EatMode onMessage(in char[][] words, in char[][] words_eol)
{
	auto channelName = words[2];

	auto position = ttsChannels.find!((channel, name) => channel.name == name)(channelName);
	if(position.empty)
		return EatMode.none;

	auto channel = position.front;

	auto user = parseUser(words[0][1 .. $]);
	const(char)[] message = words_eol[3];

	if(message.length > 0 && message[0] == ':')
		message = message[1 .. $];

	tts.voice = getUserVoice(channel, user.nick);
	tts.queue(message);

	return EatMode.none;
}

/*
* =========================================
* Persistent Settings
* =========================================
*/
string configFilePath()
{
	return buildPath(getInfo("xchatdir"), "hcspeech.conf");
}

PluginInfo pluginInfo;

void loadSettings()
{
	auto path = configFilePath();
	if(!file.exists(path))
		return;

	auto file = io.File(path, "r");

	string nick;
	
	foreach(line; file.byLine())
	{
		auto stripped = line.strip();
		if(stripped.empty)
			continue;

		auto key = stripped.munch("^=").strip();

		stripped.popFront();
		auto value = stripped.strip();

		switch(key)
		{
			case "nick":
				nick = value.idup;
				break;
			case "voice":
				assert(nick !is null);

				if(auto voice = voiceByName(value))
					specifiedUserVoices[nick] = *voice;
				else
					writefln(`No voice found for "%s", removing entry for user %s.`, value, nick);
				break;
			default:
		}
	}
}

void saveSettings()
{
	auto file = io.File(configFilePath(), "w");

	void writeKey(in char[] key, in char[] value)
	{
		file.writefln("%s = %s", key, value);
	}

	writeKey("plugin_version", pluginInfo.version_);
	file.writeln();

	foreach(nick, voice; specifiedUserVoices)
	{
		writeKey("nick", nick);
		writeKey("voice", voice.name);
		file.writeln();
	}
}

/*
* =========================================
* Initialization
* =========================================
*/
version(GNU) extern(C) void gc_init();

void init(ref PluginInfo info)
{
	version(GNU) gc_init();
	
	info.name = "hcspeech";
	info.description = "Text To Speech";
	info.version_ = "0.1";
	pluginInfo = info;

	tts = Synthesizer.create();
	allVoices = voiceList().array();

	loadSettings();

	hookCommand("tts", &ttsCommand, ttsUsage);
	hookCommand("voicelist", &voiceListCommand, voiceListUsage);
	hookCommand("assignvoice", &assignVoiceCommand, assignVoiceUsage);
	hookCommand("clearvoice", &clearVoiceCommand, clearVoiceUsage);
	hookCommand("assignedvoices", &assignedVoicesCommand, assignedVoicesUsage);
	hookCommand("ttsvolume", &ttsVolumeCommand, ttsVolumeUsage);

	hookServer("PRIVMSG", &onMessage);

	writefln("Text To Speech plugin (hcspeech %s) successfully loaded", info.version_);
}

void shutdown()
{
	saveSettings();
}

mixin(XchatPlugin!(init, shutdown));
