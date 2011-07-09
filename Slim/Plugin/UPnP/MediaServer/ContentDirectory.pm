package Slim::Plugin::UPnP::MediaServer::ContentDirectory;

# $Id$

use strict;

use I18N::LangTags qw(extract_language_tags);
use URI::Escape qw(uri_escape_utf8);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Web::HTTP;

use Slim::Plugin::UPnP::Common::Utils qw(xmlEscape absURL secsToHMS trackDetails videoDetails imageDetails);

use constant EVENT_RATE => 0.2;

my $log = logger('plugin.upnp');
my $prefs = preferences('server');

my $STATE;

sub init {
	my $class = shift;
	
	Slim::Web::Pages->addPageFunction(
		'plugins/UPnP/MediaServer/ContentDirectory.xml',
		\&description,
	);
		
	$STATE = {
		SystemUpdateID => Slim::Music::Import->lastScanTime(),
		_subscribers   => 0,
		_last_evented  => 0,
	};
	
	# Monitor for changes in the database
	Slim::Control::Request::subscribe( \&refreshSystemUpdateID, [['rescan'], ['done']] );
}

sub shutdown { }

sub refreshSystemUpdateID {
	$STATE->{SystemUpdateID} = Slim::Music::Import->lastScanTime();
	__PACKAGE__->event('SystemUpdateID');
}

sub description {
	my ( $client, $params ) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('MediaServer ContentDirectory.xml requested by ' . $params->{userAgent});
	
	return Slim::Web::HTTP::filltemplatefile( "plugins/UPnP/MediaServer/ContentDirectory.xml", $params );
}

### Eventing

sub subscribe {
	# Bump the number of subscribers
	$STATE->{_subscribers}++;
	
	# Send initial event
	sendEvent( undef, 'SystemUpdateID' );
}

sub event {
	my ( $class, $var ) = @_;
	
	if ( $STATE->{_subscribers} ) {
		# Don't send more often than every 0.2 seconds
		Slim::Utils::Timers::killTimers( undef, \&sendEvent );
		
		my $lastAt = $STATE->{_last_evented};
		my $sendAt = Time::HiRes::time();
		
		if ( $sendAt - $lastAt < EVENT_RATE ) {
			$sendAt += EVENT_RATE - ($sendAt - $lastAt);
		}
		
		Slim::Utils::Timers::setTimer(
			undef,
			$sendAt,
			\&sendEvent,
			$var,
		);
	}
}

sub sendEvent {
	my ( undef, $var ) = @_;
	
	Slim::Plugin::UPnP::Events->notify(
		service => __PACKAGE__,
		id      => 0, # will notify everyone
		data    => {
			$var => $STATE->{$var},
		},
	);
	
	# Indicate when last event was sent
	$STATE->{_last_evented} = Time::HiRes::time();
}

sub unsubscribe {	
	if ( $STATE->{_subscribers} > 0 ) {
		$STATE->{_subscribers}--;
	}
}

### Action methods

sub GetSearchCapabilities {	
	return SOAP::Data->name(
		SearchCaps => 'dc:title,dc:creator,upnp:artist,upnp:album,upnp:genre',
	);
}

sub GetSortCapabilities {	
	return SOAP::Data->name(
		SortCaps => 'dc:title,dc:creator,dc:date,upnp:artist,upnp:album,upnp:genre,upnp:originalTrackNumber',
	);
}

sub GetSystemUpdateID {
	return SOAP::Data->name( Id => $STATE->{SystemUpdateID} );
}

sub Browse {
	my ( $class, undef, $args, $headers ) = @_;
	
	my $id     = $args->{ObjectID};
	my $flag   = $args->{BrowseFlag};
	my $filter = $args->{Filter};
	my $start  = $args->{StartingIndex};
	my $limit  = $args->{RequestedCount};
	my $sort   = $args->{SortCriteria};
	
	my $cmd;
	my $xml;
	my $results;
	my $count = 0;
	my $total = 0;
	
	if ( $flag !~ /^(?:BrowseMetadata|BrowseDirectChildren)$/ ) {
		return [ 720 => 'Cannot process the request (invalid BrowseFlag)' ];
	}
	
	# Strings are needed for the top-level and years menus
	my $strings;
	my $string = sub {
		# Localize menu options from Accept-Language header
		if ( !$strings ) {
			$strings = Slim::Utils::Strings::loadAdditional( $prefs->get('language') );
			
			if ( my $lang = $headers->{'accept-language'} ) {
				my $all_langs = Slim::Utils::Strings::languageOptions();

				foreach my $language (extract_language_tags($lang)) {
					$language = uc($language);
					$language =~ s/-/_/;  # we're using zh_cn, the header says zh-cn

					if (defined $all_langs->{$language}) {
						$strings = Slim::Utils::Strings::loadAdditional($language);
						last;
					}
				}
			}
		}
		
		my $token = uc(shift);
		my $string = $strings->{$token};
		if ( @_ ) { return sprintf( $string, @_ ); }
		return $string;
	};
	
	# ContentDirectory menu/IDs are as follows:                CLI query:
	
	# Home Menu
	# ---------
	# Music
	# Video
	# Pictures
	
	# Music (/music)
	# -----
	# Artists (/a)                                             artists
	#   Artist 1 (/a/<id>/l)                                   albums artist_id:<id> sort:album
	#     Album 1 (/a/<id>/l/<id>/t)                           titles album_id:<id> sort:tracknum
	#       Track 1 (/a/<id>/l/<id>/t/<id>)                    titles track_id:<id>
	# Albums (/l)                                              albums sort:album
	#   Album 1 (/l/<id>/t)                                    titles album_id:<id> sort:tracknum
	#     Track 1 (/l/<id>/t/<id>)                             titles track_id:<id>
	# Genres (/g)                                              genres sort:album
	#   Genre 1 (/g/<id>/a)                                    artists genre_id:<id> 
	#     Artist 1 (/g/<id>/a/<id>/l)                          albums genre_id:<id> artist_id:<id> sort:album
	#       Album 1 (/g/<id>/a/<id>/l/<id>/t)                  titles album_id:<id> sort:tracknum
	#         Track 1 (/g/<id>/a/<id>/l/<id>/t/<id>)           titles track_id:<id>
	# Year (/y)                                                years
	#   2010 (/y/2010/l)                                       albums year:<id> sort:album
	#     Album 1 (/y/2010/l/<id>/t)                           titles album_id:<id> sort:tracknum
	#       Track 1 (/y/2010/l/<id>/t/<id>)                    titles track_id:<id>
	# New Music (/n)                                           albums sort:new
	#   Album 1 (/n/<id>/t)                                    titles album_id:<id> sort:tracknum
	#     Track 1 (/n/<id>/t/<id>)                             titles track_id:<id>
	# Music Folder (/m)                                        musicfolder
	#   Folder (/m/<id>/m)                                     musicfolder folder_id:<id>
	# Playlists (/p)                                           playlists
	#   Playlist 1 (/p/<id>/t)                                 playlists tracks playlist_id:<id>
	#     Track 1 (/p/<id>/t/<id>)                             titles track_id:<id>
	
	# Extras for standalone track items, AVTransport uses these
	# Tracks (/t) (cannot be browsed)
	#   Track 1 (/t/<id>)
	
	# Video (/video)
	# -----
	# Browse Video Folder (/v)
	#   Video Folder (/v/<hash>/v)
	#   All Videos (/va)                                       videos
	#     Video 1 (/va/<hash>)                                 video_titles video_hash:<hash>
	
	# Images (/images)
	# -----
	#   All Pictures (/ia)                                    
	#   By Date (/id)                                          image_titles timeline:dates
	#     2011-07-03 (/id/2011/07/03)                          image_titles timeline:day search:2011-07-03
	#       Photo 1 (/id/2011/07/03/<id>)                      image_titles image_id:<id>
	#   Albums (/il)                                           image_titles albums:1
	#     Album 1 (/il/<id>)                                   image_titles albums:1 search:<id>
	#   By Year (/it)                                          image_titles timeline:years
	#     2011 (/it/2011)                                      image_titles timeline:months search:2011
	#       07 (/it/2011/07)                                   image_titles timeline:days search:2011-07
	#         03 (/it/2011/07/03)                              image_titles timeline:day search:2011-07-03
	#           Photo 1 (/it/2011/07/03/<id>)                  image_titles image_id:<id>
	
	if ( $id eq '0' || ($flag eq 'BrowseMetadata' && $id =~ m{^/(?:music|video|images)$}) ) { # top-level menu
		my $type = 'object.container';
		my $menu = [
			{ id => '/music', parentID => 0, type => $type, title => $string->('MUSIC') },
			{ id => '/images', parentID => 0, type => $type, title => $string->('PICTURES') },
			{ id => '/video', parentID => 0, type => $type, title => $string->('VIDEO') },
		];
		
		if ( $flag eq 'BrowseMetadata' ) {
			if ( $id eq '0' ) {
				$menu = [ {
					id         => 0,
					parentID   => -1,
					type       => 'object.container',
					title      => 'Logitech Media Server [' . xmlEscape(Slim::Utils::Misc::getLibraryName()) . ']',
					searchable => 1,
				} ];
			}
			else {
				# pull out the desired menu item
				my ($item) = grep { $_->{id} eq $id } @{$menu};
				$menu = [ $item ];
			}
		}
		
		($xml, $count, $total) = _arrayToDIDLLite( {
			array  => $menu,
			sort   => $sort,
			start  => $start,
			limit  => $limit,
		} );
	}
	elsif ( $id eq '/music' || ($flag eq 'BrowseMetadata' && length($id) == 2) ) { # Music menu, or metadata for a music menu item
		my $type = 'object.container';
		my $menu = [
			{ id => '/a', parentID => '/music', type => $type, title => $string->('ARTISTS') },
			{ id => '/l', parentID => '/music', type => $type, title => $string->('ALBUMS') },
			{ id => '/g', parentID => '/music', type => $type, title => $string->('GENRES') },
			{ id => '/y', parentID => '/music', type => $type, title => $string->('BROWSE_BY_YEAR') },
			{ id => '/n', parentID => '/music', type => $type, title => $string->('BROWSE_NEW_MUSIC') },
			{ id => '/m', parentID => '/music', type => $type, title => $string->('BROWSE_MUSIC_FOLDER') },
			{ id => '/p', parentID => '/music', type => $type, title => $string->('PLAYLISTS') },
		];
		
		if ( $flag eq 'BrowseMetadata' ) {
			# pull out the desired menu item
			my ($item) = grep { $_->{id} eq $id } @{$menu};
			$menu = [ $item ];
		}
		
		($xml, $count, $total) = _arrayToDIDLLite( {
			array  => $menu,
			sort   => $sort,
			start  => $start,
			limit  => $limit,
		} );
	}
	elsif ( $id eq '/video' || ($flag eq 'BrowseMetadata' && $id =~ m{^/(?:v|va)$}) ) { # Video menu
		my $type = 'object.container';
		my $menu = [
			{ id => '/v', parentID => '/video', type => $type, title => $string->('BROWSE_VIDEO_FOLDER') },
			{ id => '/va', parentID => '/video', type => $type, title => $string->('BROWSE_ALL_VIDEOS') },
		];
		
		if ( $flag eq 'BrowseMetadata' ) {
			# pull out the desired menu item
			my ($item) = grep { $_->{id} eq $id } @{$menu};
			$menu = [ $item ];
		}
		
		($xml, $count, $total) = _arrayToDIDLLite( {
			array  => $menu,
			sort   => $sort,
			start  => $start,
			limit  => $limit,
		} );
	}
	elsif ( $id eq '/images' || ($flag eq 'BrowseMetadata' && $id =~ m{^/(?:ia|id|it|il)$}) ) { # Image menu
		my $type = 'object.container';
		my $menu = [
			{ id => '/il', parentID => '/images', type => $type, title => $string->('ALBUMS') },
			{ id => '/it', parentID => '/images', type => $type, title => $string->('YEAR') },
			{ id => '/id', parentID => '/images', type => $type, title => $string->('DATE') },
			{ id => '/ia', parentID => '/images', type => $type, title => $string->('BROWSE_ALL_PICTURES') },
		];
		
		if ( $flag eq 'BrowseMetadata' ) {
			# pull out the desired menu item
			my ($item) = grep { $_->{id} eq $id } @{$menu};
			$menu = [ $item ];
		}
		
		($xml, $count, $total) = _arrayToDIDLLite( {
			array  => $menu,
			sort   => $sort,
			start  => $start,
			limit  => $limit,
		} );
	}
	else {
		# Determine CLI command to use
		# The command is different depending on the flag:
		# BrowseMetadata will request only 1 specific item
		# BrowseDirectChildren will request the desired number of children
		if ( $id =~ m{^/a} ) {
			if ( $id =~ m{/l/(\d+)/t$} ) {
				if ( $sort && $sort !~ /^\+upnp:originalTrackNumber$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit album_id:$1 sort:tracknum tags:AGldyorfTIctnDU"
					: "albums 0 1 album_id:$1 tags:alyj";
			}
			elsif ( $id =~ m{/t/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDU"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDU";
			}
			elsif ( $id =~ m{/a/(\d+)/l$} ) {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = $flag eq 'BrowseDirectChildren'
					? "albums $start $limit artist_id:$1 sort:album tags:alyj"
					: "artists 0 1 artist_id:$1";
			}
			else {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
							
				$cmd = "artists $start $limit";
			}
		}
		elsif ( $id =~ m{^/l} ) {
			if ( $id =~ m{/l/(\d+)/t$} ) {
				if ( $sort && $sort !~ /^\+upnp:originalTrackNumber$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit album_id:$1 sort:tracknum tags:AGldyorfTIctnDU"
					: "albums 0 1 album_id:$1 tags:alyj";
			}
			elsif ( $id =~ m{/t/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDU"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDU";
			}
			else {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = "albums $start $limit sort:album tags:alyj";
			}
		}
		elsif ( $id =~ m{^/g} ) {
			if ( $id =~ m{/t/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDU"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDU";
			}
			elsif ( $id =~ m{^/g/\d+/a/\d+/l/(\d+)/t$} ) {
				if ( $sort && $sort !~ /^\+upnp:originalTrackNumber$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit album_id:$1 sort:tracknum tags:AGldyorfTIctnDU"
					: "albums 0 1 album_id:$1 tags:alyj";
			}
			elsif ( $id =~ m{^/g/(\d+)/a/(\d+)/l$} ) {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = $flag eq 'BrowseDirectChildren'
					? "albums $start $limit genre_id:$1 artist_id:$2 sort:album tags:alyj"
					: "artists 0 1 genre_id:$1 artist_id:$2";
			}
			elsif ( $id =~ m{^/g/(\d+)/a$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "artists $start $limit genre_id:$1"
					: "genres 0 1 genre_id:$1"
			}
			else {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = "genres $start $limit";
			}
		}
		elsif ( $id =~ m{^/y} ) {
			if ( $id =~ m{/t/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDU"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDU";
			}
			elsif ( $id =~ m{/l/(\d+)/t$} ) {
				if ( $sort && $sort !~ /^\+upnp:originalTrackNumber$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit album_id:$1 sort:tracknum tags:AGldyorfTIctnDU"
					: "albums 0 1 album_id:$1 tags:alyj";
			}
			elsif ( $id =~ m{/y/(\d+)/l$} ) {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = $flag eq 'BrowseDirectChildren'
					? "albums $start $limit year:$1 sort:album tags:alyj"
					: "years 0 1 year:$1";
			}
			else {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = "years $start $limit";
			}
		}
		elsif ( $id =~ m{^/n} ) {
			if ( $id =~ m{/t/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDU"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDU";
			}
			elsif ( $id =~ m{/n/(\d+)/t$} ) {
				if ( $sort && $sort !~ /^\+upnp:originalTrackNumber$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit album_id:$1 sort:tracknum tags:AGldyorfTIctnDU"
					: "albums 0 1 album_id:$1 tags:alyj";
			}
			else {
				# Limit results to pref or 100
				my $preflimit = $prefs->get('browseagelimit') || 100;
				if ( $limit > $preflimit ) {
					$limit = $preflimit;
				}
				
				$cmd = "albums $start $limit sort:new tags:alyj";
			}
		}
		elsif ( $id =~ m{^/m} ) {
			if ( $id =~ m{/t/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDU"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDU";
			}
			elsif ( $id =~ m{/m/(\d+)/m$} ) {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = $flag eq 'BrowseDirectChildren'
					? "musicfolder $start $limit folder_id:$1"
					: "musicfolder 0 1 folder_id:$1 return_top:1";
			}
			else {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = "musicfolder $start $limit";
			}
		}
		elsif ( $id =~ m{^/p} ) {
			if ( $id =~ m{/t/(\d+)$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "titles $start $limit track_id:$1 tags:AGldyorfTIctnDU"
					: "titles 0 1 track_id:$1 tags:AGldyorfTIctnDU";
			}
			elsif ( $id =~ m{^/p/(\d+)/t$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "playlists tracks $start $limit playlist_id:$1 tags:AGldyorfTIctnDU"
					: "playlists 0 1 playlist_id:$1";
			}
			else {
				if ( $sort && $sort !~ /^\+dc:title$/ ) {
					$log->warn('Unsupported sort: ' . Data::Dump::dump($args));
				}
				
				$cmd = "playlists $start $limit";
			}
		}
		elsif ( $id =~ m{^/t/(\d+)$} ) {
			$cmd = "titles 0 1 track_id:$1 tags:AGldyorfTIctnDU";
		}
		
		### Video
		elsif ( $id =~ m{^/va} ) { # All Videos
			if ( $id =~ m{/([0-9a-f]{8})$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "video_titles $start $limit video_id:$1 tags:dorfcwhtnDUl"
					: "video_titles 0 1 video_id:$1 tags:dorfcwhtnDUl";
			}
			else {
				$cmd = "video_titles $start $limit tags:dorfcwhtnDUl";
			}
		}
		
		### Images
		elsif ( $id =~ m{^/ia} ) { # All Images
			if ( $id =~ m{/([0-9a-f]{8})$} ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "image_titles $start $limit image_id:$1 tags:ofwhtnDUl"
					: "image_titles 0 1 image_id:$1 tags:ofwhtnDUl";
			}
			else {
				$cmd = "image_titles $start $limit tags:ofwhtnDUl";
			}
		}
		
		elsif ( $id =~ m{^/il} ) {      # albums
			my ($albumId) = $id =~ m{^/il/(.+)};
			
			if ( $albumId ) {
				$albumId = uri_escape_utf8($albumId);
				
				$cmd = $flag eq 'BrowseDirectChildren'
					? "image_titles $start $limit albums:1 search:$albumId tags:ofwhtnDUl"
					: "image_titles 0 1 albums:1";
			}
			
			elsif ( $id eq '/il' ) {
				$cmd = "image_titles $start $limit albums:1";
			}
		}

		elsif ( $id =~ m{^/(?:it|id)} ) { # timeline hierarchy
		
			my ($tlId) = $id =~ m{^/(?:it|id)/(.+)};
			my ($year, $month, $day, $pic) = $tlId ? split('/', $tlId) : ();
		
			if ( $pic ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "image_titles 0 1 image_id:$pic tags:ofwhtnDUl"
					: "image_titles 0 1 timeline:day search:$year-$month-$day tags:ofwhtnDUl";
			}

			# if we've got a full date, show pictures
			elsif ( $year && $month && $day ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "image_titles $start $limit timeline:day search:$year-$month-$day tags:ofwhtnDUl"
					: "image_titles 0 1 timeline:days search:$year-$month";
			}

			# show days for a given month/year
			elsif ( $year && $month ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "image_titles $start $limit timeline:days search:$year-$month"
					: "image_titles 0 1 timeline:months search:$year";
			}

			# show months for a given year
			elsif ( $year ) {
				$cmd = $flag eq 'BrowseDirectChildren'
					? "image_titles $start $limit timeline:months search:$year"
					: "image_titles 0 1 timeline:years";
			}

			elsif ( $id eq '/it' ) {
				$cmd = "image_titles $start $limit timeline:years";
			}

			elsif ( $id eq '/id' ) {
				$cmd = "image_titles $start $limit timeline:dates";
			}
		}
	
		if ( !$cmd ) {
			return [ 701 => 'No such object' ];
		}
	
		main::INFOLOG && $log->is_info && $log->info("Executing command: $cmd");
	
		# Run the request
		my $request = Slim::Control::Request->new( undef, [ split( / /, $cmd ) ] );
		if ( $request->isStatusDispatchable ) {
			$request->execute();
			if ( $request->isStatusError ) {
				return [ 720 => 'Cannot process the request (' . $request->getStatusText . ')' ];
			}
			$results = $request->getResults;
		}
		else {
			return [ 720 => 'Cannot process the request (' . $request->getStatusText . ')' ];
		}
		
		my ($parentID) = $id =~ m{^(.*)/};
		
		($xml, $count, $total) = _queryToDIDLLite( {
			cmd      => $cmd,
			results  => $results,
			flag     => $flag,
			id       => $id,
			parentID => $parentID,
			filter   => $filter,
			string   => $string,
		} );
	}
		
	utf8::encode($xml); # Just to be safe, not sure this is needed
	
	return (
		SOAP::Data->name( Result         => $xml ),
		SOAP::Data->name( NumberReturned => $count ),
		SOAP::Data->name( TotalMatches   => $total ),
		SOAP::Data->name( UpdateID       => $STATE->{SystemUpdateID} ),
	);
}

sub Search {
	my ( $class, undef, $args, $headers ) = @_;
	
	my $id     = $args->{ContainerID};
	my $search = $args->{SearchCriteria} || '*';
	my $filter = $args->{Filter};
	my $start  = $args->{StartingIndex};
	my $limit  = $args->{RequestedCount};
	my $sort   = $args->{SortCriteria};
	
	my $xml;
	my $results;
	my $count = 0;
	my $total = 0;
	
	if ( $id != 0 ) {
		return [ 708 => 'Unsupported or invalid search criteria (only ContainerID 0 is supported)' ];
	}
	
	my ($cmd, $table, $searchsql, $tags) = _decodeSearchCriteria($search);

	my ($sortsql, $stags) = _decodeSortCriteria($sort, $table);
	$tags .= $stags;
	
	# Avoid 'A' and 'G' tags because they will run extra queries
	$tags .= 'agldyorfTIctnDU';
	
	if ( $sort && !$sortsql ) {
		return [ 708 => 'Unsupported or invalid sort criteria' ];
	}
	
	if ( !$cmd ) {
		return [ 708 => 'Unsupported or invalid search criteria' ];
	}
	
	# Construct query
	$cmd = [ $cmd, $start, $limit, "tags:$tags", "search:sql=($searchsql)", "sort:sql=$sortsql" ];

	main::INFOLOG && $log->is_info && $log->info("Executing command: " . Data::Dump::dump($cmd));

	# Run the request
	my $results;
	my $request = Slim::Control::Request->new( undef, $cmd );
	if ( $request->isStatusDispatchable ) {
		$request->execute();
		if ( $request->isStatusError ) {
			return [ 708 => 'Unsupported or invalid search criteria' ];
		}
		$results = $request->getResults;
	}
	else {
		return [ 708 => 'Unsupported or invalid search criteria' ];
	}
	
	($xml, $count, $total) = _queryToDIDLLite( {
		cmd      => $cmd,
		results  => $results,
		flag     => '',
		id       => $table eq 'tracks' ? '/t' : $table eq 'videos' ? '/v' : '/i',
		filter   => $filter,
	} );
	
	return (
		SOAP::Data->name( Result         => $xml ),
		SOAP::Data->name( NumberReturned => $count ),
		SOAP::Data->name( TotalMatches   => $total ),
		SOAP::Data->name( UpdateID       => $STATE->{SystemUpdateID} ),
	);
}

sub _queryToDIDLLite {
	my $args = shift;
	
	my $cmd      = $args->{cmd};
	my $results  = $args->{results};
	my $flag     = $args->{flag};
	my $id       = $args->{id};
	my $parentID = $args->{parentID};
	my $filter   = $args->{filter};
	
	my $count    = 0;
	my $total    = $results->{count};
	
	my $filterall = ($filter eq '*');
	
	if ( ref $cmd eq 'ARRAY' ) {
		$cmd = join( ' ', @{$cmd} );
	}
	
	my $xml = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:pv="http://www.pv.com/pvns/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">';
	
	if ( $cmd =~ /^artists/ ) {		
		for my $artist ( @{ $results->{artists_loop} || [] } ) {
			$count++;
			my $aid = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $artist->{id} . '/l';
			my $parent = $id;
			
			if ( $flag eq 'BrowseMetadata' ) { # point parent to the artist's parent
				($parent) = $id =~ m{^(.*/a)};
			}
			
			$xml .= qq{<container id="${aid}" parentID="${parent}" restricted="1">}
				. '<upnp:class>object.container.person.musicArtist</upnp:class>'
				. '<dc:title>' . xmlEscape($artist->{artist}) . '</dc:title>'
				. '</container>';
		}
	}
	elsif ( $cmd =~ /^albums/ ) {
		# Fixup total for sort:new listing
		if ( $cmd =~ /sort:new/ && (my $max = $prefs->get('browseagelimit')) < $total) {
			$total = $max if $max < $total;
		}
		
		for my $album ( @{ $results->{albums_loop} || [] } ) {
			$count++;
			my $aid    = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $album->{id} . '/t';
			my $parent = $id;
			
			if ( $flag eq 'BrowseMetadata' ) { # point parent to the album's parent
				($parent) = $id =~ m{^(.*/(?:l|n))}; # both /l and /n top-level items use this
			}
			
			my $coverid = $album->{artwork_track_id};
			
			# XXX musicAlbum should have childCount attr (per DLNA)
			$xml .= qq{<container id="${aid}" parentID="${parent}" restricted="1">}
				. '<upnp:class>object.container.album.musicAlbum</upnp:class>'
				. '<dc:title>' . xmlEscape($album->{album}) . '</dc:title>';
			
			if ( $filterall || $filter =~ /dc:creator/ ) {
				$xml .= '<dc:creator>' . xmlEscape($album->{artist}) . '</dc:creator>';
			}
			if ( $filterall || $filter =~ /upnp:artist/ ) {
				$xml .= '<upnp:artist>' . xmlEscape($album->{artist}) . '</upnp:artist>';
			}
			if ( $filterall || $filter =~ /dc:date/ ) {
				$xml .= '<dc:date>' . xmlEscape($album->{year}) . '-01-01</dc:date>'; # DLNA requires MM-DD
			}
			if ( $filterall || $filter =~ /upnp:albumArtURI/ ) {
				$xml .= '<upnp:albumArtURI>' . absURL("/music/$coverid/cover") . '</upnp:albumArtURI>';
			}
			
			$xml .= '</container>';
		}
	}
	elsif ( $cmd =~ /^genres/ ) {
		for my $genre ( @{ $results->{genres_loop} || [] } ) {
			$count++;			
			my $gid = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $genre->{id} . '/a';
			my $parent = $id;
			
			if ( $flag eq 'BrowseMetadata' ) { # point parent to the genre's parent
				($parent) = $id =~ m{^(.*/g)};
			}
			
			$xml .= qq{<container id="${gid}" parentID="${parent}" restricted="1">}
				. '<upnp:class>object.container.genre.musicGenre</upnp:class>'
				. '<dc:title>' . xmlEscape($genre->{genre}) . '</dc:title>'
				. '</container>';
		}
	}
	elsif ( $cmd =~ /^years/ ) {
		for my $year ( @{ $results->{years_loop} || [] } ) {
			$count++;
			my $year = $year->{year};
			
			my $yid = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $year . '/l';
			my $parent = $id;
			
			if ( $flag eq 'BrowseMetadata' ) { # point parent to the year's parent
				($parent) = $id =~ m{^(.*/y)};
			}
			
			if ( $year eq '0' ) {
				$year = $args->{string}->('UNK');
			}
			
			$xml .= qq{<container id="${yid}" parentID="${parent}" restricted="1">}
				. '<upnp:class>object.container</upnp:class>'
				. '<dc:title>' . $year . '</dc:title>'
				. '</container>';
		}
	}
	elsif ( $cmd =~ /^musicfolder/ ) {
		my @trackIds;
		for my $folder ( @{ $results->{folder_loop} || [] } ) {
			my $fid = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $folder->{id} . '/m';
			my $parent = $id;
			
			if ( $flag eq 'BrowseMetadata' ) { # point parent to the folder's parent
				($parent) = $id =~ m{^(.*/m)/\d+/m};
			}
			
			my $type = $folder->{type};
			
			if ( $type eq 'folder' || $type eq 'unknown' ) {
				$count++;
				$xml .= qq{<container id="${fid}" parentID="${parent}" restricted="1">}
					. '<upnp:class>object.container.storageFolder</upnp:class>'
					. '<dc:title>' . xmlEscape($folder->{filename}) . '</dc:title>'
					. '</container>';
			}
			elsif ( $type eq 'playlist' ) {
				warn "*** Playlist type: " . Data::Dump::dump($folder) . "\n";
				$total--;
			}
			elsif ( $type eq 'track' ) {
				# Save the track ID for later lookup
				push @trackIds, $folder->{id};
				$total--;
			}
		}
		
		if ( scalar @trackIds ) {
			my $tracks = Slim::Control::Queries::_getTagDataForTracks( 'AGldyorfTIct', {
				trackIds => \@trackIds,
			} );
			
			for my $trackId ( @trackIds ) {
				$count++;
				$total++;
				my $track = $tracks->{$trackId};
				my $tid = $id . '/' . $trackId;
				
				# Rewrite id to end with /t/<id> so it doesn't look like another folder
				$tid =~ s{m/(\d+)$}{t/$1};
				
				$xml .= qq{<item id="${tid}" parentID="${id}" restricted="1">}
				 	. trackDetails($track, $filter)
					. '</item>';
			}
		}			
	}
	elsif ( $cmd =~ /^titles/ ) {		
		for my $track ( @{ $results->{titles_loop} || [] } ) {
			$count++;			
			my $tid    = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $track->{id};
			my $parent = $id;
			
			if ( $flag eq 'BrowseMetadata' ) { # point parent to the track's parent
				($parent) = $id =~ m{^(.*/t)};
				
				# Special case for /m path items, their parent ends in /m
				if ( $parent =~ m{^/m} ) {
					$parent =~ s/t$/m/;
				}
			}
			
			$xml .= qq{<item id="${tid}" parentID="${parent}" restricted="1">}
			 	. trackDetails($track, $filter)
			 	. '</item>';
		}
	}
	elsif ( $cmd =~ /^playlists tracks/ ) {
		for my $track ( @{ $results->{playlisttracks_loop} || [] } ) {
			$count++;			
			my $tid    = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $track->{id};
			my $parent = $id;
			
			if ( $flag eq 'BrowseMetadata' ) { # point parent to the track's parent
				($parent) = $id =~ m{^(.*/t)};
			}
			
			$xml .= qq{<item id="${tid}" parentID="${parent}" restricted="1">}
			 	. trackDetails($track, $filter)
			 	. '</item>';
		}
	}
	elsif ( $cmd =~ /^playlists/ ) {
		for my $playlist ( @{ $results->{playlists_loop} || [] } ) {
			$count++;
			my $pid = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $playlist->{id} . '/t';
			
			$xml .= qq{<container id="${pid}" parentID="/p" restricted="1">}
				. '<upnp:class>object.container.playlistContainer</upnp:class>'
				. '<dc:title>' . xmlEscape($playlist->{playlist}) . '</dc:title>'
				. '</container>';
		}
	}
	elsif ( $cmd =~ /^video_titles/ ) {		
		for my $video ( @{ $results->{videos_loop} || [] } ) {
			$count++;			
			my $vid    = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $video->{id};
			my $parent = $id;
			
			if ( $flag eq 'BrowseMetadata' ) { # point parent to the video's parent
				 # XXX
			}
			
			$xml .= qq{<item id="${vid}" parentID="${parent}" restricted="1">}
			 	. videoDetails($video, $filter)
			 	. '</item>';
		}
	}
	elsif ( $cmd =~ /^image_titles.*timeline:(?:years|months|days|dates)/ 
		|| ($cmd =~ /^image_titles.*albums:/ && $cmd !~ /search:/) ) {

		for my $image ( @{ $results->{images_loop} || [] } ) {
			$count++;			
			my $vid    = $flag eq 'BrowseMetadata' ? $id : ($id . '/' . $image->{id});
			my $parent = $id;
			
			if ( $flag eq 'BrowseMetadata' ) { # point parent to the image's parent
				 # XXX
			}
			
			$xml .= qq{<container id="${vid}" parentID="${parent}" restricted="1">}
				. '<upnp:class>object.container</upnp:class>'
				. '<dc:title>' . xmlEscape($image->{title}) . '</dc:title>'
			 	. '</container>';
		}
	}
	elsif ( $cmd =~ /^image_titles/ ) {
		for my $image ( @{ $results->{images_loop} || [] } ) {
			$count++;			
			my $vid    = $flag eq 'BrowseMetadata' ? $id : $id . '/' . $image->{id};

			my $parent = $id;
			
			if ( $flag eq 'BrowseMetadata' ) { # point parent to the image's parent
				 # XXX
			}
			
			$xml .= qq{<item id="${vid}" parentID="${parent}" restricted="1">}
			 	. imageDetails($image, $filter)
			 	. '</item>';
		}
	}
	
	$xml .= '</DIDL-Lite>';
	
	# Return empty string if we got no results
	if ( $count == 0 ) {
		$xml = '';
	}
	
	return ($xml, $count, $total);
}

sub _arrayToDIDLLite {
	my $args = shift;
	
	my $array  = $args->{array};
	my $sort   = $args->{sort};
	my $start  = $args->{start};
	my $limit  = $args->{limit};
	
	my $count = 0;
	my $total = 0;
	
	my $xml = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">';
	
	my @sorted;
	
	# Only title is available for sorting here
	if ( $sort && $sort =~ /([+-])dc:title/ ) {
		if ( $1 eq '+' ) {
			@sorted = sort { $a->{title} cmp $b->{title} } @{$array};
		}
		else {
			@sorted = sort { $b->{title} cmp $a->{title} } @{$array};
		}		
	}
	else {
		@sorted = @{$array};
	}
	
	for my $item ( @sorted ) {
		$total++;
		
		if ($start) {
			next if $start >= $total;
		}
		
		if ($limit) {
			next if $limit <= $count;
		}
		
		$count++;
		
		my $id         = $item->{id};
		my $parentID   = $item->{parentID};
		my $type       = $item->{type};
		my $title      = $item->{title};
		my $searchable = $item->{searchable} || 0;
		
		if ( $type =~ /container/ ) {
			$xml .= qq{<container id="${id}" parentID="${parentID}" restricted="1" searchable="${searchable}">}
				. "<upnp:class>${type}</upnp:class>"
				. '<dc:title>' . xmlEscape($title) . '</dc:title>'
				. '</container>';
		}
	}
	
	$xml .= '</DIDL-Lite>';
	
	return ($xml, $count, $total);
}

sub _decodeSearchCriteria {
	my $search = shift;
	
	my $cmd = 'titles';
	my $table = 'tracks';
	my $idcol = 'id'; # XXX switch to hash for audio tracks
	my $tags = '';
	
	if ( $search eq '*' ) {
		return '1=1';
	}
	
	# Fix quotes and apos
	$search =~ s/&quot;/"/g;
	$search =~ s/&apos;/'/g;
	
	# Handle derivedfrom
	if ( $search =~ s/upnp:class derivedfrom "([^"]+)"/1=1/ig ) {
		my $sclass = $1;
		if ( $sclass =~ /object\.item\.videoItem/i ) {
			$cmd = 'video_titles';
			$table = 'videos';
			$idcol = 'hash';
		}
		elsif ( $sclass =~ /object\.item\.imageItem/i ) {
			$cmd = 'image_titles';
			$table = 'images';
			$idcol = 'hash';
		}
	}
	
	# Replace 'contains "x"' and 'doesNotContain "x" with 'LIKE "%X%"' and 'NOT LIKE "%X%"'
	$search =~ s/contains\s+"([^"]+)"/LIKE "%%\U$1%%"/ig;
	$search =~ s/doesNotContain\s+"([^"]+)"/NOT LIKE "%%\U$1%%"/ig;

	$search =~ s/\@id/${table}.${idcol}/g;
	$search =~ s/\@refID exists (?:true|false)/1=1/ig;

	# Replace 'exists true' and 'exists false'
	$search =~ s/exists\s+true/IS NOT NULL/ig;
	$search =~ s/exists\s+false/IS NULL/ig;
	
	# Replace properties
	$search =~ s/dc:title/${table}.titlesearch/g;
	
	if ( $search =~ s/pv:lastUpdated/${table}.updated_time/g ) {
		$tags .= 'U';
	}
	
	if ( $cmd eq 'titles' ) {
		# These search params are only valid for audio
		if ( $search =~ s/dc:creator/contributors.namesearch/g ) {
			$tags .= 'a';
		}
	
		if ( $search =~ s/upnp:artist/contributors.namesearch/g ) {
			$tags .= 'a';
		}
	
		if ( $search =~ s/upnp:album/albums.titlesearch/g ) {
			$tags .= 'l';
		}
	
		if ( $search =~ s/upnp:genre/genres.namesearch/g ) {
			$tags .= 'g';
		}
	}
	
	return ( $cmd, $table, $search, $tags );
}

sub _decodeSortCriteria {
	my $sort = shift;
	my $table = shift;
	
	# Note: collate intentionally not used here, doesn't seem to work with multiple values
	
	my @sql;
	my $tags = '';
	
	# Supported SortCaps:
	# 
	# dc:title                       
	# dc:creator
	# dc:date
	# upnp:artist
	# upnp:album
	# upnp:genre
	# upnp:originalTrackNumber
	# pv:modificationTime
	# pv:addedTime
	# pv:lastUpdated
	
	for ( split /,/, $sort ) {
		if ( /^([+-])(.+)/ ) {
			my $dir = $1 eq '+' ? 'ASC' : 'DESC';
			
			if ( $2 eq 'dc:title' ) {
				push @sql, "${table}.titlesort $dir";
			}
			elsif ( $2 eq 'dc:creator' || $2 eq 'upnp:artist' ) {
				push @sql, "contributors.namesort $dir";
				$tags .= 'a';
			}
			elsif ( $2 eq 'upnp:album' ) {
				push @sql, "albums.titlesort $dir";
				$tags .= 'l';
			}
			elsif ( $2 eq 'upnp:genre' ) {
				push @sql, "genres.namesort $dir";
				$tags .= 'g';
			}
			elsif ( $2 eq 'upnp:originalTrackNumber' ) {
				push @sql, "tracks.tracknum $dir";
			}
			elsif ( $2 eq 'pv:modificationTime' || $2 eq 'dc:date' ) {
				if ( $table eq 'tracks' ) {
					push @sql, "${table}.timestamp $dir";
				}
				else {
					push @sql, "${table}.mtime $dir";
				}
			}
			elsif ( $2 eq 'pv:addedTime' ) {
				push @sql, "${table}.added_time $dir";
			}
			elsif ( $2 eq 'pv:lastUpdated' ) {
				push @sql, "${table}.updated_time $dir";
			}
		}
	}
	
	return ( join(', ', @sql), $tags );
}

1;