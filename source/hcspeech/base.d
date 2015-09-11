module hcspeech.base;

import std.algorithm;
import std.range.primitives;
import std.range : cycle, drop, iota, takeExactly, zip;
import std.string;
import std.random;
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
	auto offset = uniform(0, allVoices.length);
	auto min = zip(iota(0, allVoices.length),
				channel.voiceDistribution.cycle.drop(offset),
				allVoices.cycle.drop(offset))
		.minPos!((a, b) => a[1] < b[1]).front;

	auto minIndex = min[0];
	auto voice = min[2];

	userVoices[nick.idup] = voice;
	++channel.voiceDistribution[minIndex];

	writefln("Assigned voice to %s: %s", nick, voice.name);
	return voice;
}

