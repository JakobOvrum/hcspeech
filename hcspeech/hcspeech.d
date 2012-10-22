module hcspeech.hcspeech;

import xchat.plugin;

import speech.synthesis;

import std.algorithm;
import std.array;
import std.random;

Synthesizer tts;
Voice[] allVoices;

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

ChannelInfo[] ttsChannels;
Voice[string] userVoices;

private Voice getUserVoice(ChannelInfo channel, in char[] nick)
{
	if(auto voice = nick in userVoices)
		return *voice;

	auto voiceIndex = 0;
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

EatMode voiceListCommand(in char[][] words, in char[][] words_eol)
{
	foreach(i, voice; allVoices)
	{
		writefln("#%s: %s", i + 1, voice.name);
	}
	return EatMode.all;
}

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

	tts.setVoice(getUserVoice(channel, user.nick));
	tts.queue(message);

	return EatMode.none;
}

void init(ref PluginInfo info)
{
	info.name = "hcspeech";
	info.description = "Text To Speech";
	info.version_ = "0.1";

	tts = Synthesizer.create();
	allVoices = voiceList().array();

	hookCommand("tts", &ttsCommand, "Usage: TTS, toggle Text To Speech for the current channel");
	hookCommand("voicelist", &voiceListCommand, "Usage: VOICELIST, list installed Text To Speech voices");

	hookServer("PRIVMSG", &onMessage);

	writefln("Text To Speech plugin (hcspeech %s) successfully loaded", info.version_);
}

mixin(XchatPlugin!init);
