module hcspeech.base;

import std.algorithm;
import std.range.primitives;
import std.range : zip;
import std.string;
import std.uni : asLowerCase;

import hexchat.plugin;
import speech.synthesis;

// Used for all speech synthesis in the plugin.
__gshared Synthesizer tts;

/*
 * =========================================
 * Voice Tracking
 * =========================================
 */
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

__gshared
{
	ChannelInfo[] ttsChannels;
	Voice[] allVoices;
	Voice[string] specifiedUserVoices;
	Voice[string] userVoices;
}

auto findVoices(const(char)[] voiceSpecifier)
{
	return allVoices.filter!(voice => voice.name.asLowerCase.canFind(voiceSpecifier.asLowerCase));
}

Voice* voiceByName(in char[] name)
{
	auto search = allVoices.find!((voice, name) => voice.name == name)(name);
	return search.empty? null : &search.front;
}

Voice getUserVoice(ChannelInfo channel, in char[] nick)
{
	if(auto voice = nick in specifiedUserVoices)
		return *voice;

	if(auto voice = nick in userVoices)
		return *voice;

	// Assign least used voice
	auto min = allVoices.zip(channel.voiceDistribution).minPos!((a, b) => a[1] < b[1]);
	userVoices[nick.idup] = min.front[0];
	++min.front[1];

	writefln("Assigned voice to %s: %s", nick, min.front[0].name);
	return min.front[0];
}

