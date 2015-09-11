module hcspeech.base;

import std.algorithm;
import std.string;

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
	voiceSpecifier = voiceSpecifier.toLower();

	return allVoices.filter!(voice => toLower(voice.name).canFind(voiceSpecifier))();
}

Voice* voiceByName(in char[] name)
{
	auto voiceIndex = allVoices.countUntil!((voice, name) => voice.name == name)(name);
	return voiceIndex == -1? null : &allVoices[voiceIndex];
}

Voice getUserVoice(ChannelInfo channel, in char[] nick)
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
