module hcspeech.hcspeech;

import std.algorithm;
import std.path;
import std.range;
import std.string;

import file = std.file;
import io = std.stdio;

import xchat.plugin;
import speech.synthesis;

import hcspeech.base, hcspeech.commands;

/*
 * =========================================
 * Command Setup
 * =========================================
 */
struct TTSAction
{
	alias void function(in char[][], in char[][]) Callback;

	Callback callback;
	string usage;
	size_t minArgs;
}

__gshared TTSAction[string] actions;
__gshared string[] actionList; // For ordered help output.

void addAction(string name, TTSAction.Callback callback, string usage, size_t minArgs = 0)
{
	actions[name] = TTSAction(callback, usage, minArgs);
	actionList ~= usage;
}

void addHelpSeparator()
{
	actionList ~= "";
}

shared static this()
{
	addAction("help", &helpCommand, helpUsage);
	addHelpSeparator();

	addAction("toggle", &toggleCommand, toggleUsage);
	addAction("add", &addCommand, addUsage, 1);
	addAction("remove", &removeCommand, removeUsage, 1);
	addAction("list", &listCommand, listUsage);
	addHelpSeparator();

	addAction("voicelist", &voiceListCommand, voiceListUsage);
	addAction("assign", &assignCommand, assignUsage, 2);
	addAction("unassign", &unassignCommand, unassignUsage, 1);
	addAction("assignedvoices", &assignedVoicesCommand, assignedVoicesUsage);
	addHelpSeparator();

	addAction("volume", &volumeCommand, volumeUsage);
	addAction("rate", &rateCommand, rateUsage);
}

immutable ttsUsage = "Usage: TTS [action [args]], main TTS command. " ~
"Toggles TTS for the current channel when given no arguments. " ~
`Use "/TTS help" to see available actions.`;

EatMode ttsCommand(in char[][] words, in char[][] words_eol)
{
	if(words.length == 1)
	{
		toggleCommand(words[1 .. $], words_eol[1 .. $]);
	}
	else
	{
		auto actionName = words[1];

		if(auto action = toLower(actionName) in actions)
		{
			auto args = words[1 .. $];
			auto args_eol = words_eol[1 .. $];

			if(args.length - 1 >= action.minArgs)
				action.callback(args, args_eol);
			else
			{
				writefln("Usage: %s", action.usage);
				writefln(`Action "%s" requires at least %s argument(s).`, actionName, action.minArgs);
			}
		}
		else
		{
			writefln(`Unknown TTS action "%s". Use "/TTS HELP" to see usage.`, actionName);
		}
	}
	return EatMode.all;
}

immutable helpUsage = "HELP [action], display help information.";

void helpCommand(in char[][] words, in char[][] words_eol)
{
	if(words.length > 1)
	{
		auto actionName = words[1];
		if(auto action = toLower(actionName) in actions)
		{
			writefln("Usage: %s", action.usage);
		}
		else
		{
			writefln(`Unknown TTS action "%s". Use "/TTS HELP" to see usage.`, actionName);
		}
	}
	else
	{
		writefln("Usage: TTS [action [arguments]], perform the specified Text To Speech related action.");
		writefln("");
		foreach(usage; actionList)
			writefln("    %s", usage);
		writefln("");
		writefln("When no action is specified, the TOGGLE action is performed.");
	}
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

	hookServer("PRIVMSG", &onMessage);

	writefln("Text To Speech plugin (hcspeech %s) successfully loaded", info.version_);
}

void shutdown()
{
	saveSettings();
}

mixin(XchatPlugin!(init, shutdown));
