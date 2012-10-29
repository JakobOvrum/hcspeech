module hcspeech.commands;

import std.algorithm;
import std.array;
import std.conv;
import std.range;
import std.string;

import xchat.plugin;

import speech.synthesis;

import hcspeech.base;

/*
 * =========================================
 * Commands
 * =========================================
 */
// TTS context management
immutable toggleUsage = "TOGGLE, toggle TTS for the current channel.";
immutable addUsage = "ADD <channel>, start TTS in the specified channel.";
immutable removeUsage = "REMOVE <channel>, stop TTS in the specified channel.";
immutable listUsage = "LIST, list channels with TTS running.";

void toggleCommand(in char[][] words, in char[][] words_eol)
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
}

void addCommand(in char[][] words, in char[][] words_eol)
{
	auto channel = words[1];

	auto position = ttsChannels.countUntil!((channel, name) => channel.name == name)(channel);
	if(position == -1)
	{
		ttsChannels ~= ChannelInfo(channel.idup);
		writefln("Started TTS in %s.", channel);
	}
	else
	{
		writefln("TTS is already enabled in %s.", channel);
	}
}

void removeCommand(in char[][] words, in char[][] words_eol)
{
	auto channel = words[1];

	auto position = ttsChannels.countUntil!((channel, name) => channel.name == name)(channel);
	if(position != -1)
	{
		ttsChannels = ttsChannels.remove!(SwapStrategy.unstable)(position);
		writefln("Stopped TTS in %s.", channel);
	}
	else
	{
		writefln("%s is not in the list of TTS channels.", channel);
	}
}

void listCommand(in char[][] words, in char[][] words_eol)
{
	if(ttsChannels.empty)
	{
		writefln("TTS is not enabled for any channels.");
	}
	else
	{
		auto app = appender!string();

		static if(__VERSION__ < 2060)
		{
			auto names = map!(channel => channel.name)(ttsChannels);
			auto joined = joiner(names, ", ");
			copy(joined, app);
		}
		else
		{
			ttsChannels.map!(channel => channel.name)()
				.joiner(", ")
				.copy(app);
		}

		writefln(app.data);
	}
}

// Voice management
immutable voiceListUsage =      "VOICELIST, list available TTS voices.";

immutable assignUsage =         "ASSIGN <nick> <voice name>, " ~
                                "assign a specific voice to a user by voice name.";

immutable unassignUsage =       "UNASSIGN <nick>, unassign any previously " ~
                                "assigned voice for the specified user.";

immutable assignedVoicesUsage = "ASSIGNEDVOICES [nick filter], list assigned voices.";


void voiceListCommand(in char[][] words, in char[][] words_eol)
{
	foreach(i, voice; allVoices)
		writefln("#%s: %s", i + 1, voice.name);
}

void assignCommand(in char[][] words, in char[][] words_eol)
{
	auto nick = words[1];
	auto voiceSpecifier = words_eol[2];

	auto voices = findVoices(voiceSpecifier);
	if(voices.empty)
	{
		writefln(`No voice found for specifier "%s". Use "/TTS VOICELIST" to list available voices.`, voiceSpecifier);
		return;
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
}

void unassignCommand(in char[][] words, in char[][] words_eol)
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

void assignedVoicesCommand(in char[][] words, in char[][] words_eol)
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
}

// TTS configuration management
immutable volumeUsage = "VOLUME [new volume in the range 0-100], set or display TTS volume.";

void volumeCommand(in char[][] words, in char[][] words_eol)
{
	if(words.length > 1)
	{
		auto volume = to!uint(words[1]);
		if(volume > 100)
			writefln("Volume level must be in the range 0-100.");
		else
		{
			tts.volume = volume;
			writefln("TTS volume is now %s/100", tts.volume);
		}
	}
	else
	{
		writefln("TTS volume is %s/100", tts.volume);
	}
}
