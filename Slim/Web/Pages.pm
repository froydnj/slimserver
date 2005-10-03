package Slim::Web::Pages;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Date::Parse qw(str2time);
use File::Spec::Functions qw(:ALL);
use POSIX ();

use Slim::DataStores::Base;
use Slim::Music::LiveSearch;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

our %additionalLinks = ();

our $fieldInfo;

our %hierarchy = (
	'artist' => 'album,track',
	'album'  => 'track',
	'song '  => '',
);

sub init {

	$fieldInfo = Slim::DataStores::Base->fieldInfo;

	addLinks("browse",{'BROWSE_BY_ARTIST' => "browsedb.html?hierarchy=artist,album,track&level=0"});
	addLinks("browse",{'BROWSE_BY_GENRE'  => "browsedb.html?hierarchy=genre,artist,album,track&level=0"});
	addLinks("browse",{'BROWSE_BY_ALBUM'  => "browsedb.html?hierarchy=album,track&level=0"});
	addLinks("browse",{'BROWSE_BY_YEAR'   => "browsedb.html?hierarchy=year,album,track&level=0"});
	addLinks("browse",{'BROWSE_NEW_MUSIC' => "browsedb.html?hierarchy=age,track&level=0"});
	addLinks("search", {'SEARCH' => "search.html?liveSearch=1"});
	addLinks("search", {'ADVANCEDSEARCH' => "advanced_search.html"});
	addLinks("help",{'GETTING_STARTED' => "html/docs/quickstart.html"});
	addLinks("help",{'PLAYER_SETUP' => "html/docs/ipconfig.html"});
	addLinks("help",{'USING_REMOTE' => "html/docs/interface.html"});
	addLinks("help",{'HELP_REMOTE' => "html/help_remote.html"});
	addLinks("help",{'HELP_RADIO' => "html/docs/radio.html"});
	addLinks("help",{'REMOTE_STREAMING' => "html/docs/remotestreaming.html"});
	addLinks("help",{'FAQ' => "html/docs/faq.html"});
	addLinks("help",{'SOFTSQUEEZE' => "html/softsqueeze/index.html"});
	addLinks("help",{'TECHNICAL_INFORMATION' => "html/docs/index.html"});
}

sub home {
	my ($client, $params) = @_;

	my %listform = %$params;

	if (defined $params->{'forget'}) {
		Slim::Player::Client::forgetClient(Slim::Player::Client::getClient($params->{'forget'}));
	}

	$params->{'nosetup'}  = 1 if $::nosetup;
	$params->{'noserver'} = 1 if $::noserver;
	$params->{'newVersion'} = $::newVersion if $::newVersion;

	if (!exists $additionalLinks{"browse"}) {
		addLinks("browse",{'BROWSE_BY_ARTIST' => "browsedb.html?hierarchy=artist,album,track&level=0"});
		addLinks("browse",{'BROWSE_BY_GENRE'  => "browsedb.html?hierarchy=genre,artist,album,track&level=0"});
		addLinks("browse",{'BROWSE_BY_ALBUM'  => "browsedb.html?hierarchy=album,track&level=0"});
		addLinks("browse",{'BROWSE_BY_YEAR'   => "browsedb.html?hierarchy=year,album,track&level=0"});
		addLinks("browse",{'BROWSE_NEW_MUSIC' => "browsedb.html?hierarchy=age,track&level=0"});
	}

	if (!exists $additionalLinks{"search"}) {
		addLinks("search", {'SEARCH' => "livesearch.html"});
		addLinks("search", {'ADVANCEDSEARCH' => "advanced_search.html"});
	}

	if (!exists $additionalLinks{"help"}) {
		addLinks("help",{'GETTING_STARTED' => "html/docs/quickstart.html"});
		addLinks("help",{'PLAYER_SETUP' => "html/docs/ipconfig.html"});
		addLinks("help",{'USING_REMOTE' => "html/docs/interface.html"});
		addLinks("help",{'HELP_REMOTE' => "html/help_remote.html"});
		addLinks("help",{'HELP_RADIO' => "html/docs/radio.html"});
		addLinks("help",{'REMOTE_STREAMING' => "html/docs/remotestreaming.html"});
		addLinks("help",{'FAQ' => "html/docs/faq.html"});
		addLinks("help",{'SOFTSQUEEZE' => "html/softsqueeze/index.html"});
		addLinks("help",{'TECHNICAL_INFORMATION' => "html/docs/index.html"});
	}

	if (Slim::Utils::Prefs::get('lookForArtwork')) {
		addLinks("browse",{'BROWSE_BY_ARTWORK' => "browsedb.html?hierarchy=artwork,track&level=0"});
	} else {
		addLinks("browse",{'BROWSE_BY_ARTWORK' => undef});
		$params->{'noartwork'} = 1;
	}
	
	if (Slim::Utils::Prefs::get('audiodir')) {
		addLinks("browse",{'BROWSE_MUSIC_FOLDER'   => "browsetree.html"});
	} else {
		addLinks("browse",{'BROWSE_MUSIC_FOLDER' => undef});
		$params->{'nofolder'}=1;
	}

	# Always show Browse Playlists, as it's stored in the db now.
	addLinks("browse",{'SAVED_PLAYLISTS' => "browsedb.html?hierarchy=playlist,playlistTrack&level=0"});

	# fill out the client setup choices
	for my $player (sort { $a->name() cmp $b->name() } Slim::Player::Client::clients()) {

		# every player gets a page.
		# next if (!$player->isPlayer());
		$listform{'playername'}   = $player->name();
		$listform{'playerid'}     = $player->id();
		$listform{'player'}       = $params->{'player'};
		$listform{'skinOverride'} = $params->{'skinOverride'};
		$params->{'player_list'} .= ${Slim::Web::HTTP::filltemplatefile("homeplayer_list.html", \%listform)};
	}

	Slim::Buttons::Plugins::addSetupGroups();
	$params->{'additionalLinks'} = \%additionalLinks;

	_addPlayerList($client, $params);
	
	addLibraryStats($params);

	my $template = $params->{"path"}  =~ /home\.(htm|xml)/ ? 'home.html' : 'index.html';
	
	return Slim::Web::HTTP::filltemplatefile($template, $params);
}

sub addLinks {
	my ($category, $links, $noquery) = @_;

	return if (ref($links) ne 'HASH');

	while (my ($title, $path) = each %$links) {
		if (defined($path)) {
			$additionalLinks{$category}->{$title} = $path . 
				($noquery ? '' : (($path =~ /\?/) ? '&' : '?'));
		} else {
			delete($additionalLinks{$category}->{$title});
		}
	}

	if (not keys %{$additionalLinks{$category}}) {
		delete($additionalLinks{$category});
	}
}

# Check to make sure the ref is valid, and not a wildcard.
sub _refCheck {
	my $ref = shift;

	return defined $ref && scalar @$ref && $ref->[0] && $ref->[0] ne '*' ? 1 : 0;
}

sub _lcPlural {
	my ($count, $singular, $plural) = @_;

	# only convert to lowercase if our language does not wand uppercase (default lc)
	my $word = ($count == 1 ? string($singular) : string($plural));
	$word = (string('MIDWORDS_UPPER', '', 1) ? $word : lc($word));
	return sprintf("%s %s", $count, $word);
}

sub addLibraryStats {
	my ($params, $genre, $artist, $album) = @_;
	
	if (Slim::Music::Import::stillScanning()) {
		$params->{'warn'} = 1;
		return;
	}

	my $ds    = Slim::Music::Info::getCurrentDataStore();
	my $find  = {};

	$find->{'genre'}       = $genre  if _refCheck($genre);
	$find->{'contributor'} = $artist if _refCheck($artist) && !_refCheck($album);
	$find->{'album'}       = $album  if _refCheck($album);

	$params->{'song_count'}   = _lcPlural($ds->count('track', $find), 'SONG', 'SONGS');
	$params->{'artist_count'} = _lcPlural($ds->count('contributor', $find), 'ARTIST', 'ARTISTS');
	$params->{'album_count'}  = _lcPlural($ds->count('album', $find), 'ALBUM', 'ALBUMS');

	# Right now hitlist.html is the only page that uses genre_count -
	# which can be expensive. Only generate it if we need to.
	if ($params->{'path'} =~ /hitlist/) {

		$params->{'genre_count'}  = _lcPlural($ds->count('genre', $find), 'GENRE', 'GENRES');
	}
}

# Send the status page (what we're currently playing, contents of the playlist)
sub status_header {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	$params->{'omit_playlist'} = 1;

	return status(@_);
}

sub status {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	_addPlayerList($client, $params);

	$params->{'refresh'} = Slim::Utils::Prefs::get('refreshRate');
	
	if (!defined($client)) {

		# fixed faster rate for noclients
		$params->{'refresh'} = 10;
		return Slim::Web::HTTP::filltemplatefile("status_noclients.html", $params);

	} elsif ($client->needsUpgrade()) {

		$params->{'player_needs_upgrade'} = 1;
		$params->{'modestop'} = 'Stop';
		return Slim::Web::HTTP::filltemplatefile("status_needs_upgrade.html", $params);
	}

	my $current_player;
	my $songcount = 0;
	 
	if (defined($client)) {

		$songcount = Slim::Player::Playlist::count($client);
		
		if ($client->defaultName() ne $client->name()) {
			$params->{'player_name'} = $client->name();
		}

		$params->{'shuffle'} = Slim::Player::Playlist::shuffle($client);
		if (Slim::Player::Playlist::shuffle($client) == 1) {
			$params->{'shuffleon'} = "on";
		} elsif (Slim::Player::Playlist::shuffle($client) == 2) {
			$params->{'shufflealbum'} = "album";
		} else {
			$params->{'shuffleoff'} = "off";
		}
	
		$params->{'songtime'} = int(Slim::Player::Source::songTime($client));

		if (Slim::Player::Source::playingSong($client)) { 
			my $dur = Slim::Player::Source::playingSongDuration($client);
			if ($dur) { $dur = int($dur); }
			$params->{'durationseconds'} = $dur; 
		}

		#
		$params->{'repeat'} = Slim::Player::Playlist::repeat($client);
		if (!Slim::Player::Playlist::repeat($client)) {
			$params->{'repeatoff'} = "off";
		} elsif (Slim::Player::Playlist::repeat($client) == 1) {
			$params->{'repeatone'} = "one";
		} else {
			$params->{'repeatall'} = "all";
		}

		#
		if (Slim::Player::Source::playmode($client) eq 'play') {

			$params->{'modeplay'} = "Play";

			if (defined($params->{'durationseconds'}) && defined($params->{'songtime'})) {

				my $remaining = $params->{'durationseconds'} - $params->{'songtime'};

				if ($remaining < $params->{'refresh'}) {	
					$params->{'refresh'} = ($remaining < 5) ? 5 : $remaining;
				}
			}

		} elsif (Slim::Player::Source::playmode($client) eq 'pause') {

			$params->{'modepause'} = "Pause";
		
		} else {
			$params->{'modestop'} = "Stop";
		}

		#
		if (Slim::Player::Source::rate($client) > 1) {
			$params->{'rate'} = 'ffwd';
		} elsif (Slim::Player::Source::rate($client) < 0) {
			$params->{'rate'} = 'rew';
		} else {
			$params->{'rate'} = 'norm';
		}
		
		$params->{'rateval'} = Slim::Player::Source::rate($client);
		$params->{'sync'}    = Slim::Player::Sync::syncwith($client);
		$params->{'mode'}    = $client->power() ? 'on' : 'off';

		if ($client->isPlayer()) {

			$params->{'sleeptime'} = $client->currentSleepTime();
			$params->{'isplayer'}  = 1;
			$params->{'mute'}      = $client->prefGet('mute');
			$params->{'volume'}    = int($client->prefGet("volume") + 0.5);
			$params->{'bass'}      = int($client->bass() + 0.5);
			$params->{'treble'}    = int($client->treble() + 0.5);
			$params->{'pitch'}     = int($client->pitch() + 0.5);

			my $sleep = $client->sleepTime() - Time::HiRes::time();
			$params->{'sleep'} = $sleep < 0 ? 0 : int($sleep/60);
		}
		
		$params->{'fixedVolume'} = !$client->prefGet('digitalVolumeControl');
		$params->{'player'} = $client->id();
	}
	
	if ($songcount > 0) {
		my $song = Slim::Player::Playlist::song($client);

		$params->{'currentsong'} = Slim::Player::Source::playingSongIndex($client) + 1;
		$params->{'thissongnum'} = Slim::Player::Source::playingSongIndex($client);
		$params->{'songcount'}   = $songcount;
		$params->{'itempath'}    = $song;

		_addSongInfo($client, $params, 1);

		# for current song, display the playback bitrate instead.
		my $undermax = Slim::Player::Source::underMax($client,$song);
		if (defined $undermax && !$undermax) {
			$params->{'bitrate'} = string('CONVERTED_TO')." ".Slim::Utils::Prefs::maxRate($client).Slim::Utils::Strings::string('KBPS').' ABR';
		}
		if (Slim::Utils::Prefs::get("playlistdir")) {
			$params->{'cansave'} = 1;
		}
	}
	
	if (!$params->{'omit_playlist'}) {

		$params->{'callback'} = $callback;

		$params->{'playlist'} = playlist($client, $params, \&status_done, $httpClient, $response);

		if (!$params->{'playlist'}) {
			# playlist went into background, stash $callback and exit
			return undef;
		} else {
			$params->{'playlist'} = ${$params->{'playlist'}};
		}

	} else {
		# Special case, we need the playlist info even if we don't want
		# the playlist itself
		if ($client &&
		    defined $client->currentPlaylist && 
		    ref($client->currentPlaylist) ne 'Class::DBI::Object::Has::Been::Deleted' && 
		    !Slim::Music::Info::isRemoteURL($client->currentPlaylist)) {

			$params->{'current_playlist'} = $client->currentPlaylist;
			$params->{'current_playlist_modified'} = $client->currentPlaylistModified;
			$params->{'current_playlist_name'} = Slim::Music::Info::standardTitle($client, $client->currentPlaylist);
		}
	}

	$params->{'noArtist'}      = Slim::Utils::Strings::string('NO_ARTIST');
	$params->{'noAlbum'}       = Slim::Utils::Strings::string('NO_ALBUM');

	$params->{'nosetup'} = 1   if $::nosetup;

	return Slim::Web::HTTP::filltemplatefile($params->{'omit_playlist'} ? "status_header.html" : "status.html" , $params);
}

sub status_done {
	my ($client, $params, $bodyref, $httpClient, $response) = @_;

	$params->{'playlist'} = $$bodyref;

	my $output = Slim::Web::HTTP::filltemplatefile("status.html" , $params);

	$params->{'callback'}->($client, $params, $output, $httpClient, $response);
}

sub playlist {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	
	if (!defined($client)) {

		# fixed faster rate for noclients
		$params->{'playercount'} = 0;
		return Slim::Web::HTTP::filltemplatefile("playlist.html", $params);
	
	} elsif ($client->needsUpgrade()) {

		$params->{'player_needs_upgrade'} = '1';
		return Slim::Web::HTTP::filltemplatefile("playlist_needs_upgrade.html", $params);
	}

	$params->{'playercount'} = Slim::Player::Client::clientCount();
	
	my $songcount = Slim::Player::Playlist::count($client);

	$params->{'playlist_items'} = '';
	$params->{'skinOverride'} ||= '';
	
	my $count = Slim::Utils::Prefs::get('itemsPerPage');

	unless (defined($params->{'start'}) && $params->{'start'} ne '') {

		$params->{'start'} = (int(Slim::Player::Source::playingSongIndex($client)/$count)*$count);
	}

	if ($client->currentPlaylist() && !Slim::Music::Info::isRemoteURL($client->currentPlaylist())) {
		$params->{'current_playlist'} = $client->currentPlaylist();
		$params->{'current_playlist_modified'} = $client->currentPlaylistModified();
		$params->{'current_playlist_name'} = Slim::Music::Info::standardTitle($client,$client->currentPlaylist());
	}

	if ($::d_playlist && $client->currentPlaylistRender() && ref($client->currentPlaylistRender()) eq 'ARRAY') {

		msg("currentPlaylistChangeTime : " . localtime($client->currentPlaylistChangeTime()) . "\n");
		msg("currentPlaylistRender     : " . localtime($client->currentPlaylistRender()->[0]) . "\n");
		msg("currentPlaylistRenderSkin : " . $client->currentPlaylistRender()->[1] . "\n");
		msg("currentPlaylistRenderStart: " . $client->currentPlaylistRender()->[2] . "\n");

		msg("skinOverride: $params->{'skinOverride'}\n");
		msg("start: $params->{'start'}\n");
	}

	# Only build if we need to.
	# Check to see if we're newer, and the same skin.
	if ($songcount > 0 && 
		defined $params->{'skinOverride'} &&
		defined $params->{'start'} &&
		$client->currentPlaylistRender() && 
		ref($client->currentPlaylistRender()) eq 'ARRAY' && 
		$client->currentPlaylistChangeTime() && 
		$client->currentPlaylistRender()->[1] eq $params->{'skinOverride'} &&
		$client->currentPlaylistRender()->[2] eq $params->{'start'} &&
		$client->currentPlaylistChangeTime() < $client->currentPlaylistRender()->[0]) {

		if (Slim::Utils::Prefs::get("playlistdir")) {
			$params->{'cansave'} = 1;
		}

		$::d_playlist && msg("Skipping playlist build - not modified.\n");

		$params->{'playlist_header'}  = $client->currentPlaylistRender()->[3];
		$params->{'playlist_pagebar'} = $client->currentPlaylistRender()->[4];
		$params->{'playlist_items'}   = $client->currentPlaylistRender()->[5];

		return Slim::Web::HTTP::filltemplatefile("playlist.html", $params);
	}

	if (!$songcount) {
		return Slim::Web::HTTP::filltemplatefile("playlist.html", $params);
	}

	my %listBuild = ();
	my $item;
	my %list_form;

	$params->{'cansave'} = 1;
	
	my ($start, $end);
	
	if (defined $params->{'nopagebar'}) {

		($start, $end) = simpleHeader(
			$songcount,
			\$params->{'start'},
			\$params->{'playlist_header'},
			$params->{'skinOverride'},
			$params->{'itemsPerPage'},
			0
		);

	} else {

		($start, $end) = pageBar(
			$songcount,
			$params->{'path'},
			Slim::Player::Source::playingSongIndex($client),
			"player=" . Slim::Web::HTTP::escape($client->id()) . "&", 
			\$params->{'start'}, 
			\$params->{'playlist_header'},
			\$params->{'playlist_pagebar'},
			$params->{'skinOverride'},
			$params->{'itemsPerPage'}
		);
	}

	$listBuild{'start'} = $start;
	$listBuild{'end'}   = $end;

	$listBuild{'offset'} = $listBuild{'start'} % 2 ? 0 : 1; 

	my $webFormat = Slim::Utils::Prefs::getInd("titleFormat",Slim::Utils::Prefs::get("titleFormatWeb"));

	$listBuild{'includeAlbum'}  = ($webFormat !~ /ALBUM/) ;
	$listBuild{'currsongind'}   = Slim::Player::Source::playingSongIndex($client);
	$listBuild{'item'}          = $listBuild{'start'};

	my $itemCount    = 0;
	my $itemsPerPass = Slim::Utils::Prefs::get('itemsPerPass');
	my $itemsPerPage = Slim::Utils::Prefs::get('itemsPerPage');
	my $composerIn   = Slim::Utils::Prefs::get('composerInArtists');
	my $starttime    = Time::HiRes::time();

	my $ds           = Slim::Music::Info::getCurrentDataStore();

	$params->{'playlist_items'} = '';
	$params->{'myClientState'}  = $client;
	$params->{'noArtist'}       = Slim::Utils::Strings::string('NO_ARTIST');
	$params->{'noAlbum'}        = Slim::Utils::Strings::string('NO_ALBUM');

	my $needIdleStreams = Slim::Player::Client::needIdleStreams();

	# This is a hot loop.
	# But it's better done all at once than through the scheduler.
	while ($listBuild{'item'} < ($listBuild{'end'} + 1) && $itemCount < $itemsPerPage) {

		# These should all be objects - but be safe.
		my $objOrUrl = Slim::Player::Playlist::song($client, $listBuild{'item'});
		my $track    = $objOrUrl;

		if (!ref $objOrUrl) {

			$track = $ds->objectForUrl($objOrUrl) || do {
				msg("Couldn't retrieve objectForUrl: [$objOrUrl] - skipping!\n");
				$listBuild{'item'}++;
				$itemCount++;
				next;
			};
		}

		my %list_form = %$params;
		my $fieldInfo = Slim::DataStores::Base->fieldInfo;
		my $levelInfo = $fieldInfo->{'track'};

		&{$levelInfo->{'listItem'}}($ds, \%list_form, $track);

		$list_form{'num'} = $listBuild{'item'};
		$list_form{'odd'} = ($listBuild{'item'} + $listBuild{'offset'}) % 2;

		if ($listBuild{'item'} == $listBuild{'currsongind'}) {
			$list_form{'currentsong'} = "current";
			$list_form{'title'}    = Slim::Music::Info::isRemoteURL($track) ? Slim::Music::Info::standardTitle(undef, $track) : Slim::Music::Info::getCurrentTitle(undef, $track);
		} else {
			$list_form{'currentsong'} = undef;
			$list_form{'title'}    = Slim::Music::Info::standardTitle(undef, $track);
		}

		$list_form{'nextsongind'} = $listBuild{'currsongind'} + (($listBuild{'item'} > $listBuild{'currsongind'}) ? 1 : 0);

		$params->{'playlist_items'} .= ${Slim::Web::HTTP::filltemplatefile("status_list.html", \%list_form)};

		$listBuild{'item'}++;
		$itemCount++;

		# don't neglect the streams for over 0.25 seconds
		if ($needIdleStreams && $itemCount > 1 && !($itemCount % $itemsPerPass) && (Time::HiRes::time() - $starttime) > 0.25) {

			main::idleStreams();
		}
	}

	$::d_playlist && msg("End playlist build. $itemCount items\n");

	undef %listBuild;

	# Give some player time after the loop, but before rendering.
	main::idleStreams();

	if ($client) {

		# Stick the rendered data into the client object as a stopgap
		# solution to the cpu spike issue.
		$client->currentPlaylistRender([
			time(),
			($params->{'skinOverride'} || ''),
			($params->{'start'}),
			$params->{'playlist_header'},
			$params->{'playlist_pagebar'},
			$params->{'playlist_items'}
		]);
	}

	return Slim::Web::HTTP::filltemplatefile("playlist.html", $params),
}

sub _addPlayerList {
	my ($client, $params) = @_;

	$params->{'playercount'} = Slim::Player::Client::clientCount();
	
	my @players = Slim::Player::Client::clients();

	if (scalar(@players) > 1) {

		my %clientlist = ();

		for my $eachclient (@players) {

			$clientlist{$eachclient->id()} =  $eachclient->name();

			if (Slim::Player::Sync::isSynced($eachclient)) {
				$clientlist{$eachclient->id()} .= " (".string('SYNCHRONIZED_WITH')." ".
					Slim::Player::Sync::syncwith($eachclient).")";
			}	
		}

		$params->{'player_chooser_list'} = options($client->id(), \%clientlist, $params->{'skinOverride'});
	}
}

# Call into the memory usage class - this will return live data about memory
# usage, opcodes, and more. Note that loading this takes up memory itself!
sub memory_usage {
	my ($client, $params) = @_;

	my $item    = $params->{'item'};
	my $type    = $params->{'type'};
	my $command = $params->{'command'};

	unless ($item && $command) {

		return Slim::Utils::MemoryUsage->status_memory_usage();
	}

	if (defined $item && defined $command && Slim::Utils::MemoryUsage->can($command)) {

		return Slim::Utils::MemoryUsage->$command($item, $type);
	}
}

sub basicSearch {
	my ($client, $params) = @_;

	my $player = $params->{'player'};
	my $query  = $params->{'query'};

	# set some defaults for the template
	$params->{'browse_list'} = " ";
	$params->{'numresults'}  = -1;

	# short circuit
	if (!defined($query) || ($params->{'manualSearch'} && !$query)) {
		return Slim::Web::HTTP::filltemplatefile("search.html", $params);
	}

	# Don't auto-search for 2 chars, but allow manual search. IE: U2
	if (!$params->{'manualSearch'} && length($query) <= 2) {
		return \'';
	}

	# Don't kill the database - use limit & offsets
	my $data = Slim::Music::LiveSearch->queryWithLimit($query, [ $params->{'type'} ], undef, $params->{'start'});

	# The user has hit enter, or has a browser that can't handle the javascript.
	if ($params->{'manualSearch'}) {

		# Tell the template not to do a livesearch request anymore.
		$params->{'liveSearch'} = 0;

		my @results = ();
		my $descend = 1;
		my @qstring = ('manualSearch=1');

		for my $item (@$data) {

			$params->{'type'}       = $item->[0];
			$params->{'numresults'} = $item->[1];
			$params->{'path'}       = 'search.html';

			if ($params->{'type'} eq 'track' && $params->{'numresults'}) {

				push @results, $item->[2];

				$descend = undef;
			}

			_fillInSearchResults($params, $item->[2], $descend, \@qstring);
		}

		if (defined $client && scalar @results) {

			$client->param('searchResults', @results);
		}

		return Slim::Web::HTTP::filltemplatefile("search.html", $params);
	}

	# do it live - and send back the div
	if ($params->{'xmlmode'}) {
		return Slim::Music::LiveSearch->outputAsXML($query, $data, $player);
	} else {
		return Slim::Music::LiveSearch->outputAsXHTML($query, $data, $player);
	}
}

sub advancedSearch {
	my ($client, $params) = @_;

	my $player  = $params->{'player'};
	my %query   = ();
	my @qstring = ();
	my $ds      = Slim::Music::Info::getCurrentDataStore();

	# template defaults
	$params->{'browse_list'} = " ";
	$params->{'liveSearch'}  = 0;

	# Prep the date format
	$params->{'dateFormat'} = Slim::Utils::Misc::shortDateF();

	# Check for valid search terms
	for my $key (keys %$params) {
		
		next unless $key =~ /^search\.(\S+)/;
		next unless $params->{$key};

		my $newKey = $1;

		# Stuff the requested item back into the params hash, under
		# the special "search" hash. Because Template Toolkit uses '.'
		# as a delimiter for hash access.
		$params->{'search'}->{$newKey}->{'value'} = $params->{$key};

		# Apply the logical operator to the item in question.
		if ($key =~ /\.op$/) {

			my $op = $params->{$key};

			$key    =~ s/\.op$//;
			$newKey =~ s/\.op$//;

			next unless $params->{$key};

			# Do the same for 'op's
			$params->{'search'}->{$newKey}->{'op'} = $params->{$key};

			# add these onto the query string. kinda jankey.
			push @qstring, join('=', "$key.op", $op);
			push @qstring, join('=', $key, $params->{$key});

			# Bitrate needs to changed a bit
			if ($key =~ /bitrate$/) {
				$params->{$key} *= 100;
			}

			# Duration is also special
			if ($key =~ /age$/) {
				$params->{$key} = str2time($params->{$key});
			}

			# Map the type to the query
			# This will be handed to SQL::Abstract
			$query{$newKey} = { $op => $params->{$key} };

			delete $params->{$key};

			next;
		}

		# Append to the query string
		push @qstring, join('=', $key, Slim::Web::HTTP::escape($params->{$key}));

		# Normalize the string queries
		# 
		# Turn the track_title into track.title for the query.
		# We need the _'s in the form, because . means hash key.
		if ($newKey =~ s/_(titlesearch|namesearch)$/\.$1/) {

			$params->{$key} = searchStringSplit($params->{$key});
		}

		# Wildcard comment searches
		if ($newKey =~ /comment/) {

			$params->{$key} = "\*$params->{$key}\*";
		}

		$query{$newKey} = $params->{$key};
	}

	# Turn our conversion list into a nice type => name hash.
	my %types  = ();

	for my $type (keys %{ Slim::Player::Source::Conversions() }) {

		$type = (split /-/, $type)[0];

		$types{$type} = string($type);
	}

	$params->{'fileTypes'} = \%types;

	# load up the genres we know about.
	$params->{'genres'}    = $ds->find({
		'field'  => 'genre',
		'sortBy' => 'genre',
	});

	# short-circuit the query
	if (scalar keys %query == 0) {
		$params->{'numresults'}  = -1;
		return Slim::Web::HTTP::filltemplatefile("advanced_search.html", $params);
	}

	# Do the actual search
	my $results = $ds->find({
		'field'  => 'track',
		'find'   =>  \%query,
		'sortBy' => 'title',
	});

	$client->param('searchResults', $results) if defined $client;

	_fillInSearchResults($params, $results, undef, \@qstring, $ds);

	return Slim::Web::HTTP::filltemplatefile("advanced_search.html", $params);
}

sub _fillInSearchResults {
	my ($params, $results, $descend, $qstring, $ds) = @_;

	my $player = $params->{'player'};
	my $query  = $params->{'query'}  || '';
	my $type   = $params->{'type'}   || 'track';

	$params->{'type'} = $type;
	
	my $otherParams = 'player=' . Slim::Web::HTTP::escape($player) . 
			  '&type=' . ($type ? $type : ''). 
			  '&query=' . Slim::Web::HTTP::escape($query) . '&' .
			  join('&', @$qstring);

	# Make sure that we have something to show.
	if (!defined $params->{'numresults'} && defined $results && ref($results) eq 'ARRAY') {

		$params->{'numresults'} = scalar @$results;
	}

	# put in the type separator
	if ($type && !$ds) {

		$params->{'browse_list'} .= sprintf("<tr><td><hr width=\"75%%\"/><br/>%s \"$query\": %d<br/><br/></td></tr>",
			Slim::Utils::Strings::string(uc($type . 'SMATCHING')), $params->{'numresults'},
		);
	}

	if ($params->{'numresults'}) {

		my ($start, $end);

		if (defined $params->{'nopagebar'}) {

			($start, $end) = simpleHeader(
				$params->{'numresults'},
				\$params->{'start'},
				\$params->{'browselist_header'},
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
				0
			);

		} else {

			($start, $end) = pageBar(
				$params->{'numresults'},
				$params->{'path'},
				0,
				$otherParams,
				\$params->{'start'},
				\$params->{'searchlist_header'},
				\$params->{'searchlist_pagebar'},
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
			);
		}
		
		my $itemnumber = 0;
		my $lastAnchor = '';

		for my $item (@$results) {

			next unless defined $item && ref($item);

			# Contributor/Artist uses name, Album & Track uses title.
			my $title     = $item->can('title')     ? $item->title()     : $item->name();
			my $sorted    = $item->can('titlesort') ? $item->titlesort() : $item->namesort();
			my %list_form = %$params;

			$list_form{'attributes'}   = '&' . join('=', $type, $item->id());
			$list_form{'descend'}      = $descend;
			$list_form{'odd'}          = ($itemnumber + 1) % 2;

			if ($type eq 'track') {
				
				# if $ds is undefined here, make sure we have it now.
				$ds = Slim::Music::Info::getCurrentDataStore() unless $ds;
				
				# If we can't get an object for this url, skip it, as the
				# user's database is likely out of date. Bug 863
				my $itemObj = $item;

				if (!ref($itemObj)) {

					$itemObj = $ds->objectForUrl($item) || next;
				}
				
				my $itemname = &{$fieldInfo->{$type}->{'resultToName'}}($itemObj);

				&{$fieldInfo->{$type}->{'listItem'}}($ds, \%list_form, $itemObj, $itemname, 0);

			} else {
				if ($type eq 'artist') {
					$list_form{'hierarchy'}	   = 'artist,album,track';
					$list_form{'level'}        = 1;
				} elsif ($type eq 'album') {
					$list_form{'hierarchy'}	   = 'album,track';
					$list_form{'level'}        = 1;				
				}
				
				$list_form{'text'} = $title;
			}

			$itemnumber++;

			my $anchor = substr($sorted, 0, 1);

			if ($lastAnchor ne $anchor) {
				$list_form{'anchor'} = $lastAnchor = $anchor;
			}

			$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_list.html", \%list_form)};
		}
	}
}

sub _addSongInfo {
	my ($client, $params, $getCurrentTitle) = @_;

	# 
	my $url = $params->{'itempath'};
	my $id  = $params->{'item'};

	# kinda pointless, but keeping with compatibility
	return unless $url || $id;

	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $track;

	if ($url) {

		$track = $ds->objectForUrl($url, 1, 1);

	} elsif ($id) {

		$track = $ds->objectForId('track', $id);
		$url   = $track->url() if $track;
	}

	if ($track) {

		# let the template access the object directly.
		$params->{'itemobj'}    = $track unless $params->{'itemobj'};

		$params->{'filelength'} = Slim::Utils::Misc::delimitThousands($track->filesize());
		$params->{'bitrate'}    = $track->bitrate();

		if ($getCurrentTitle) {
			$params->{'songtitle'} = Slim::Music::Info::getCurrentTitle(undef, $track);
		} else {
			$params->{'songtitle'} = Slim::Music::Info::standardTitle(undef, $track);
		}

		# make urls in comments into links
		for my $comment ($track->comment()) {

			next unless defined $comment && $comment !~ /^\s*$/;

			if (!($comment =~ s!\b(http://[\-~A-Za-z0-9_/\.]+)!<a href=\"$1\" target=\"_blank\">$1</a>!igo)) {

				# handle emusic-type urls which don't have http://
				$comment =~ s!\b(www\.[\-~A-Za-z0-9_/\.]+)!<a href=\"http://$1\" target=\"_blank\">$1</a>!igo;
			}

			$params->{'comment'} .= $comment;
		}
	
		# handle artwork bits
		if ($track->coverArt('thumb')) {
			$params->{'coverThumb'} = $track->id;
		}

		if (Slim::Music::Info::isRemoteURL($url)) {

			$params->{'download'} = $url;

		} else {

			$params->{'download'} = sprintf('%smusic/%d/download', $params->{'webroot'}, $track->id());
		}
	}
}

sub songInfo {
	my ($client, $params) = @_;

	_addSongInfo($client, $params, 0);

	return Slim::Web::HTTP::filltemplatefile("songinfo.html", $params);
}

sub browsedb {
	my ($client, $params) = @_;

	# XXX - why do we default to genre?
	my $hierarchy = $params->{'hierarchy'} || "genre";
	my $level     = $params->{'level'} || 0;
	my $player    = $params->{'player'};

	$::d_info && msg("browsedb - hierarchy: $hierarchy level: $level\n");

	my @levels = split(",", $hierarchy);

	my $maxLevel = scalar(@levels) - 1;

	if ($level > $maxLevel)	{
		$level = $maxLevel;
	}

	my $ds = Slim::Music::Info::getCurrentDataStore();

	my $itemnumber = 0;
	my $lastAnchor = '';
	my $descend;
	my %names = ();
	my @attrs = ();
	my %findCriteria = ();	

	for my $field (@levels) {

		my $info = $fieldInfo->{$field} || $fieldInfo->{'default'};

		# XXX - is this the right thing to do?
		# For artwork browsing - we want to display the album.
		if (my $transform = $info->{'nameTransform'}) {
			push @levels, $transform;
		}

		# If we don't have this check, we'll create a massive query
		# for each level in the hierarchy, even though it's not needed
		next unless defined $params->{$field};

		$names{$field} = &{$info->{'idToName'}}($ds, $params->{$field});
	}

	# Just go directly to the params.
	# Don't show stats when only showing playlists - extra queries that
	# aren't needed.
	if (!grep { /playlist/ } @levels) {
		addLibraryStats($params, [$params->{'genre'}], [$params->{'artist'}], [$params->{'album'}], [$params->{'song'}]);
	}

	# This pulls the appropriate anonymous function list out of the
	# fieldInfo hash, which we then retrieve data from.
	my $firstLevelInfo = $fieldInfo->{$levels[0]} || $fieldInfo->{'default'};
	my $title = $params->{'browseby'} = $firstLevelInfo->{'title'};

	for my $key (keys %{$fieldInfo}) {

		if (defined($params->{$key})) {

			# Populate the find criteria with all query parameters in the URL
			$findCriteria{$key} = $params->{$key};

			# Skip this for the top level
			next if $key eq 'album.compilation';

			# Pre-populate the attrs list with all query parameters that 
			# are not part of the hierarchy. This allows a URL to put
			# query constraints on a hierarchy using a field that isn't
			# necessarily part of the hierarchy.
			if (!grep {$_ eq $key} @levels) {
				push @attrs, $key . '=' . Slim::Web::HTTP::escape($params->{$key});
			}
		}
	}

	my %list_form = (
		'player'       => $player,
		'pwditem'      => string($title),
		'skinOverride' => $params->{'skinOverride'},
		'title'	       => $title,
		'hierarchy'    => $hierarchy,
		'level'	       => 0,
		'attributes'   => (scalar(@attrs) ? ('&' . join("&", @attrs)) : ''),
	);

	$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_pwdlist.html", \%list_form)};

	# We want to include Compilations in the pwd, so we need the artist,
	# but not in the actual search.
	if ($findCriteria{'artist'} && $findCriteria{'album.compilation'}) {

		delete $findCriteria{'artist'};

		push @attrs, 'album.compilation=1';
	}

	for (my $i = 0; $i < $level ; $i++) {

		my $attr = $levels[$i];

		# XXX - is this the right thing to do?
		# For artwork browsing - we want to display the album.
		if (my $transform = $firstLevelInfo->{'nameTransform'}) {
			$attr = $transform;
		}

		if ($params->{$attr}) {

			push @attrs, $attr . '=' . Slim::Web::HTTP::escape($params->{$attr});

			my %list_form = (
				 'player'       => $player,
				 'pwditem'      => $names{$attr},
				 'skinOverride' => $params->{'skinOverride'},
				 'title'	=> $title,
				 'hierarchy'	=> $hierarchy,
				 'level'	=> $i+1,
				 'attributes'   => (scalar(@attrs) ? ('&' . join("&", @attrs)) : ''),
			 );

			$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_pwdlist.html", \%list_form)};

			# Send down the attributes down to the template
			#
			# These may be overwritten below.
			# This is useful/needed for the playlist case where we
			# want access to the containing playlist object.
			$params->{$attr} = $ds->objectForId($attr, $params->{$attr});
		}
	}

	my $otherparams = join('&',
		'player=' . Slim::Web::HTTP::escape($player || ''),
		"hierarchy=$hierarchy",
		"level=$level",
		@attrs,
	);

	my $levelInfo = $fieldInfo->{$levels[$level]} || $fieldInfo->{'default'};
	my $items     = &{$levelInfo->{'find'}}($ds, $levels[$level], \%findCriteria);

	if ($items && scalar(@$items)) {

		my ($start, $end);

		my $ignoreArticles = $levelInfo->{'ignoreArticles'};

		if (defined $params->{'nopagebar'}) {

			($start, $end) = simpleHeader(
				scalar(@$items),
				\$params->{'start'},
				\$params->{'browselist_header'},
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
				$ignoreArticles ? (scalar(@$items) > 1) : 0,
			);

		} elsif (&{$levelInfo->{'alphaPageBar'}}(\%findCriteria)) {

			my $alphaitems = [ map &{$levelInfo->{'resultToSortedName'}}($_), @$items ];

			($start, $end) = alphaPageBar(
				$alphaitems,
				$params->{'path'},
				$otherparams,
				\$params->{'start'},
				\$params->{'browselist_pagebar'},
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
			);

		} else {

			($start, $end) = pageBar(
				scalar(@$items),
				$params->{'path'},
				0,
				$otherparams,
				\$params->{'start'},
				\$params->{'browselist_header'},
				\$params->{'browselist_pagebar'},
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
			);
		}

		#$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_list.html", \%list_form)};

		$descend = ($level >= $maxLevel) ? undef : 'true';

		if (scalar(@$items) > 1 && !$levelInfo->{'suppressAll'}) {

			if ($params->{'includeItemStats'} && !Slim::Utils::Misc::stillScanning()) {
				# XXX include statistics
			}

			my $nextLevelInfo;

			if ($descend) {
				my $nextLevel  = $levels[$level+1];
				$nextLevelInfo = $fieldInfo->{$nextLevel} || $fieldInfo->{'default'};
			} else {
				$nextLevelInfo = $fieldInfo->{'track'};
			}

			if ($level == 0) {
				$list_form{'hierarchy'}	= $levelInfo->{'descendTransform'} ? $levelInfo->{'descendTransform'} : join(',', @levels[1..$#levels]);
				$list_form{'level'}	= 0;
			} else {
				$list_form{'hierarchy'}	= $hierarchy;
				$list_form{'level'}	= $descend ? $level+1 : $level;
			}

			if ($nextLevelInfo->{'allTitle'}) {
				$list_form{'text'} = string($nextLevelInfo->{'allTitle'});
			}

			$list_form{'descend'}      = 1;
			$list_form{'player'}       = $player;
			$list_form{'odd'}	   = ($itemnumber + 1) % 2;
			$list_form{'skinOverride'} = $params->{'skinOverride'};
			$list_form{'attributes'}   = (scalar(@attrs) ? ('&' . join("&", @attrs)) : '');

			$itemnumber++;

			$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_list.html", \%list_form)};
		}

		# Dynamic VA/Compilation listing
		if ($levels[$level] eq 'artist' && Slim::Utils::Prefs::get('variousArtistAutoIdentification')) {

			my %list_form  = %$params;
			my $vaObj      = $ds->variousArtistsObject;
			my @attributes = (@attrs, 'album.compilation=1', sprintf('artist=%d', $vaObj->id));

			# Only show VA item if there's valid listings below
			# the current level.
			my %find = map { split /=/ } @attrs, 'album.compilation=1';

			if ($ds->count('album', \%find)) {

				$list_form{'text'}        = $vaObj->name;
				$list_form{'descend'}     = $descend;
				$list_form{'hiearchy'}    = $hierarchy;
				$list_form{'level'}	  = $level + 1;
				$list_form{'odd'}	  = ($itemnumber + 1) % 2;
				$list_form{'attributes'}  = (scalar(@attributes) ? ('&' . join("&", @attributes, )) : '');

				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_list.html", \%list_form)};

				$itemnumber++;
			}
		}

		# Don't bother with idle streams if we only have SB2 clients
		my $needIdleStreams = Slim::Player::Client::needIdleStreams();

		for my $item ( @{$items}[$start..$end] ) {

			my %list_form = %$params;

			my $attrName  = $levelInfo->{'nameTransform'} || $levels[$level];

			# We might not be inflated yet...(but skip for years)
			if (!ref($item) && $item =~ /^\d+$/ && $levels[$level] ne 'year') {

				$item = $ds->objectForId($attrName, $item);
			}

			my $itemid   = &{$levelInfo->{'resultToId'}}($item);
			my $itemname = &{$levelInfo->{'resultToName'}}($item);
			my $itemsort = &{$levelInfo->{'resultToSortedName'}}($item);

			$list_form{'hierarchy'}	    = $hierarchy;
			$list_form{'level'}	    = $level + 1;
			$list_form{'attributes'}    = (scalar(@attrs) ? ('&' . join("&", @attrs)) : '') . '&' .
				$attrName . '=' . Slim::Web::HTTP::escape($itemid);

			$list_form{'levelName'}	    = $attrName;
			$list_form{'text'}	    = $itemname;
			$list_form{'descend'}	    = $descend;
			$list_form{'odd'}	    = ($itemnumber + 1) % 2;
			$list_form{$levelInfo->{'nameTransform'} || $levels[$level]} = $itemid;
			$list_form{'skinOverride'}  = $params->{'skinOverride'};
			$list_form{'itemnumber'}    = $itemnumber;
			$list_form{'itemobj'}	    = $item;

			# This is calling into the %fieldInfo hash
			&{$levelInfo->{'listItem'}}($ds, \%list_form, $item, $itemname, $descend, \%findCriteria);

			if (defined $itemsort) {

				my $anchor = substr($itemsort, 0, 1);

				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'} = $lastAnchor = $anchor;
				}
			}

			$itemnumber++;

			if ($levels[$level] eq 'artwork') {
				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_artwork.html", \%list_form)};
			} else {
				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_list.html", \%list_form)};
			}

			if ($needIdleStreams) {
				main::idleStreams();
			}
		}

		if ($level == $maxLevel && $levels[$level] eq 'track') {

			if ($items->[$start]->coverArt()) {
				$params->{'coverArt'} = $items->[$start]->id;
			}
		}
	}

	# Give players a bit of time.
	main::idleStreams();

	$params->{'descend'} = $descend;

	# override the template for the playlist case.
	my $template = $levelInfo->{'browseBodyTemplate'} || 'browsedb.html';

	return Slim::Web::HTTP::filltemplatefile($template, $params);
}

sub browsetree {
	my ($client, $params) = @_;

	my $hierarchy  = $params->{'hierarchy'} || '';
	my $player     = $params->{'player'};
	my $itemsPer   = $params->{'itemsPerPage'} || Slim::Utils::Prefs::get('itemsPerPage');

	my $ds         = Slim::Music::Info::getCurrentDataStore();
	my @levels     = split(/\//, $hierarchy);
	my $itemnumber = 0;

	# Pull the directory list, which will be used for looping.
	my ($topLevelObj, $items, $count) = Slim::Utils::Misc::findAndScanDirectoryTree(\@levels);

	# Page title
	$params->{'browseby'} = 'MUSIC';

	for (my $i = 0; $i < scalar @levels; $i++) {

		my $obj = $ds->objectForId('track', $levels[$i]);

		my %list_form = (
			'player'       => $player,
			'skinOverride' => $params->{'skinOverride'},
			'title'        => $i == 0 ? string('MUSIC') : $obj->title,
			'hierarchy'    => join('/', @levels[0..$i]),
		);

		$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsetree_pwdlist.html", \%list_form)};
	}

	my ($start, $end) = (0, $count);

	# Create a numeric pagebar if we need to.
	if ($count > $itemsPer) {

		($start, $end) = pageBar(
			$count,
			$params->{'path'},
			0,
			"hierarchy=$hierarchy&player=$player",
			\$params->{'start'},
			\$params->{'browselist_header'},
			\$params->{'browselist_pagebar'},
			$params->{'skinOverride'},
			$params->{'itemsPerPage'},
		);
	}

	# Setup an 'All' button.
	# I believe this will play only songs, and not playlists.
	if ($count) {
		my %list_form = %$params;

		$list_form{'hierarchy'}	    = undef;
		$list_form{'descend'}	    = 1;
		$list_form{'text'}	    = string('ALL_SONGS');
		$list_form{'itemobj'}	    = $topLevelObj;

		$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsetree_list.html", \%list_form)};
	}

	#
	my $topPath = $topLevelObj->path;
	my $osName  = Slim::Utils::OSDetect::OS();

	for my $relPath (@$items[$start..$end]) {

		my $url  = Slim::Utils::Misc::fixPath($relPath, $topPath) || next;

		# Amazingly, this just works. :)
		# Do the cheap compare for osName first - so non-windows users
		# won't take the penalty for the lookup.
		if ($osName eq 'win' && Slim::Music::Info::isWinShortcut($url)) {
			$url = Slim::Utils::Misc::fileURLFromWinShortcut($url);
		}

		my $item = $ds->objectForUrl($url, 1) || next;

		# Bug: 1360 - Don't show files referenced in a cuesheet
		next if ($item->content_type eq 'cur');

		my %list_form = %$params;

		# Turn the utf8 flag on for proper display - since this is
		# coming directly from the filesystem.
		$list_form{'text'}	    = Slim::Utils::Unicode::utf8decode_locale($relPath);

		$list_form{'hierarchy'}	    = join('/', @levels, $item->id);
		$list_form{'descend'}	    = Slim::Music::Info::isList($item) ? 1 : 0;
		$list_form{'odd'}	    = ($itemnumber + 1) % 2;
		$list_form{'itemobj'}	    = $item;

		# Don't display the edit dialog for cue sheets.
		if ($item->isCUE) {
			$list_form{'noEdit'} = '&noEdit=1';
		}

		$itemnumber++;

		$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsetree_list.html", \%list_form)};

		if (!$params->{'coverArt'} && $item->coverArt) {
			$params->{'coverArt'} = $item->id;
		}
	}

	$params->{'descend'} = 1;
	
	if (Slim::Music::Import::stillScanning()) {
		$params->{'warn'} = 1;
	}
	
	return Slim::Web::HTTP::filltemplatefile("browsedb.html", $params);
}

# Implement browseid3 in terms of browsedb.
sub browseid3 {
	my ($client, $params) = @_;

	my @hierarchy  = ();
	my %categories = (
		'genre'  => 'genre',
		'artist' => 'artist',
		'album'  => 'album',
		'song'   => 'track'
	);

	my %queryMap = (
		'genre'  => 'genre.name',
		'artist' => 'artist.name',
		'album'  => 'album.title',
		'track'  => 'track.title'
	);

	my $ds = Slim::Music::Info::getCurrentDataStore();

	$params->{'level'} = 0;

	# Turn the browseid3 params into something browsedb can use.
	for my $category (keys %categories) {

		next unless $params->{$category};

		$params->{ $categories{$category} } = $params->{$category};
	}

	# These must be in order.
	for my $category (qw(genre artist album track)) {

		if (!defined $params->{$category}) {

			push @hierarchy, $category;

		} elsif ($params->{$category} eq '*') {

			delete $params->{$category};

		} elsif ($params->{$category}) {

			# Search for each real name - normalize the query,
			# then turn it into the ID suitable for browsedb()
			my $cat = $params->{$category} = (@{$ds->find({

				'field' => $category,
				'find'  => { $queryMap{$category} => $params->{$category} },

			})})[0];

			return browsedb($client, $params) unless $cat;

			$params->{$category} = $cat->id;
		}
	}

	$params->{'hierarchy'} = join(',', @hierarchy);

	return browsedb($client, $params);
}

sub searchStringSplit {
	my $search  = shift;
	my $searchSubString = shift;
	
	$searchSubString = defined $searchSubString ? $searchSubString : Slim::Utils::Prefs::get('searchSubString');

	# normalize the string
	$search = Slim::Utils::Text::ignoreCaseArticles($search);
	
	my @strings = ();

	# Don't split - causes an explict AND, which is what we want.. I think.
	# for my $string (split(/\s+/, $search)) {
	my $string = $search;

		if ($searchSubString) {

			push @strings, "\*$string\*";

		} else {

			push @strings, [ "$string\*", "\* $string\*" ];
		}
	#}

	return \@strings;
}

sub anchor {
	my $item = shift;
	my $suppressArticles = shift;
	
	if ($suppressArticles) {
		$item = Slim::Utils::Text::ignoreCaseArticles($item) || return '';
	}

	return Slim::Utils::Text::matchCase(substr($item, 0, 1));
}

sub options {
	my ($selected, $option, $skinOverride) = @_;

	# pass in the selected value and a hash of value => text pairs to get the option list filled
	# with the correct option selected.

	my $optionlist = '';

	for my $curroption (sort { $option->{$a} cmp $option->{$b} } keys %{$option}) {

		$optionlist .= ${Slim::Web::HTTP::filltemplatefile("select_option.html", {
			'selected'     => ($curroption eq $selected),
			'key'          => $curroption,
			'value'        => $option->{$curroption},
			'skinOverride' => $skinOverride,
		})};
	}

	return $optionlist;
}

# Build a simple header 
sub simpleHeader {
	my ($itemCount, $startRef, $headerRef, $skinOverride, $count, $offset) = @_;

	$count ||= Slim::Utils::Prefs::get('itemsPerPage');

	my $start = (defined($$startRef) && $$startRef ne '') ? $$startRef : 0;

	if ($start >= $itemCount) {
		$start = $itemCount - $count;
	}

	$$startRef = $start;

	my $end    = $start + $count - 1 - $offset;

	if ($end >= $itemCount) {
		$end = $itemCount - 1;
	}

	# Don't bother with a pagebar on a non-pagable item.
	if ($itemCount < $count) {
		return ($start, $end);
	}

	$$headerRef = ${Slim::Web::HTTP::filltemplatefile("pagebarheader.html", {
		"start"        => $start,
		"end"          => $end,
		"itemcount"    => $itemCount - 1,
		'skinOverride' => $skinOverride
	})};

	return ($start, $end);
}

# Build a bar of links to multiple pages of items
sub pageBar {
	my $itemcount = shift;
	my $path = shift;
	my $currentitem = shift;
	my $otherparams = shift;
	my $startref = shift; #will be modified
	my $headerref = shift; #will be modified
	my $pagebarref = shift; #will be modified
	my $skinOverride = shift;

	my $count = shift || Slim::Utils::Prefs::get('itemsPerPage');

	my $start = (defined($$startref) && $$startref ne '') ? $$startref : (int($currentitem/$count)*$count);
	if ($start >= $itemcount) { $start = $itemcount - $count; }
	$$startref = $start;

	my $end = $start+$count-1;
	if ($end >= $itemcount) { $end = $itemcount - 1;}

	# Don't bother with a pagebar on a non-pagable item.
	if ($itemcount < $count) {
		return ($start, $end);
	}

	if ($itemcount > $count) {
		$$headerref = ${Slim::Web::HTTP::filltemplatefile("pagebarheader.html", { "start" => ($start+1), "end" => ($end+1), "itemcount" => $itemcount, 'skinOverride' => $skinOverride})};

		my %pagebar = ();

		my $numpages  = POSIX::ceil($itemcount/$count);
		my $curpage   = int($start/$count);
		my $pagesperbar = 10; #make this a preference
		my $pagebarstart = (($curpage - int($pagesperbar/2)) < 0 || $numpages <= $pagesperbar) ? 0 : ($curpage - int($pagesperbar/2));
		my $pagebarend = ($pagebarstart + $pagesperbar) > $numpages ? $numpages : ($pagebarstart + $pagesperbar);

		$pagebar{'pagesstart'} = ($pagebarstart > 0);

		if ($pagebar{'pagesstart'}) {
			$pagebar{'pagesprev'} = ($curpage - $pagesperbar) * $count;
			if ($pagebar{'pagesprev'} < 0) { $pagebar{'pagesprev'} = 0; };
		}

		if ($pagebarend < $numpages) {
			$pagebar{'pagesend'} = ($numpages -1) * $count;
			$pagebar{'pagesnext'} = ($curpage + $pagesperbar) * $count;
			if ($pagebar{'pagesnext'} > $pagebar{'pagesend'}) { $pagebar{'pagesnext'} = $pagebar{'pagesend'}; }
		}

		$pagebar{'pageprev'} = $curpage > 0 ? (($curpage - 1) * $count) : undef;
		$pagebar{'pagenext'} = ($curpage < ($numpages - 1)) ? (($curpage + 1) * $count) : undef;
		$pagebar{'otherparams'} = defined($otherparams) ? $otherparams : '';
		$pagebar{'skinOverride'} = $skinOverride;
		$pagebar{'path'} = $path;

		for (my $j = $pagebarstart;$j < $pagebarend;$j++) {
			$pagebar{'pageslist'} .= ${Slim::Web::HTTP::filltemplatefile('pagebarlist.html'
							,{'currpage' => ($j == $curpage)
							,'itemnum0' => ($j * $count)
							,'itemnum1' => (($j * $count) + 1)
							,'pagenum' => ($j + 1)
							,'otherparams' => $otherparams
							,'skinOverride' => $skinOverride
							,'path' => $path})};
		}
		$$pagebarref = ${Slim::Web::HTTP::filltemplatefile("pagebar.html", \%pagebar)};
	}
	return ($start, $end);
}

sub alphaPageBar {
	my $itemsref = shift;
	my $path = shift;
	my $otherparams = shift;
	my $startref = shift; #will be modified
	my $pagebarref = shift; #will be modified
	my $skinOverride = shift;
	my $maxcount = shift || Slim::Utils::Prefs::get('itemsPerPage');

	my $itemcount = scalar(@$itemsref);

	my $start = $$startref;

	if (!$start) { 
		$start = 0;
	}

	if ($start >= $itemcount) { 
		$start = $itemcount - $maxcount; 
	}

	$$startref = $start;

	my $end = $itemcount - 1;

	# Don't bother with a pagebar on a non-pagable item.
	if ($itemcount < $maxcount) {
		return ($start, $end);
	}

	if ($itemcount > ($maxcount / 2)) {

		my $lastLetter = '';
		my $lastLetterIndex = 0;
		my $pageslist = '';

		$end = -1;

		# This could be more efficient.
		for (my $j = 0; $j < $itemcount; $j++) {

			my $curLetter = substr($itemsref->[$j], 0, 1);
			$curLetter = '' if (!defined($curLetter));

			if ($lastLetter ne $curLetter) {

				if (($j - $lastLetterIndex) > $maxcount) {
					if ($end == -1 && $j > $start) {
						$end = $j - 1;
					}
					$lastLetterIndex = $j;
				}

				$pageslist .= ${Slim::Web::HTTP::filltemplatefile('alphapagebarlist.html', {
					'currpage'     => ($lastLetterIndex == $start),
					'itemnum0'     => $lastLetterIndex,
					'itemnum1'     => ($lastLetterIndex + 1),
					'pagenum'      => $curLetter,
					'fragment'     => ("#" . $curLetter),
					'otherparams'  => ($otherparams || ''),
					'skinOverride' => $skinOverride,
					'path'         => $path
				})};

				$lastLetter = $curLetter;
			}
		}

		if ($end == -1) {
			$end = $itemcount - 1;
		}

		my %pagebar_params = (
			'otherparams'  => ($otherparams || ''),
			'pageslist'    => $pageslist,
			'skinOverride' => $skinOverride,
		);

		$$pagebarref = ${Slim::Web::HTTP::filltemplatefile("pagebar.html", \%pagebar_params)};
	}
	
	return ($start, $end);
}

sub firmware {
	my ($client, $params) = @_;

	return Slim::Web::HTTP::filltemplatefile("firmware.html", $params);
}

# This is here just to support SDK4.x (version <=10) clients
# so it always sends an upgrade to version 10 using the old upgrade method.
sub update_firmware {
	my ($client, $params) = @_;

	$params->{'warning'} = Slim::Player::Squeezebox::upgradeFirmware($params->{'ipaddress'}, 10) 
		|| string('UPGRADE_COMPLETE_DETAILS');
	
	return Slim::Web::HTTP::filltemplatefile("update_firmware.html", $params);
}

sub tuneIn {
	my ($client, $params) = @_;
	return Slim::Web::HTTP::filltemplatefile('tunein.html', $params);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
