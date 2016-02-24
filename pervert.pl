#!/usr/bin/perl -w

###############################################################################
#     NewsUP - create backups of your files to the usenet.
#     Copyright (C) David Santiago
#  
#     This program is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
#
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <http://www.gnu.org/licenses/>.
##############################################################################
use warnings;
use strict;
use utf8;
use 5.018;
use Getopt::Long;
use JSON;
use XML::LibXML;
use LWP::UserAgent;
use DBI;
use POSIX qw/floor/;
use HTML::Entities;

my $HISTORY_TABLE="history";
binmode STDOUT, ":utf8";

sub check_duplicates_and_download{
  my ($DBH, $configs, $candidates, $ua) = @_;
  my $rMovieName = qr/$configs->{movieNameRegexp}/i;
  my $rSerieID = qr/$configs->{serieIdRegexp}/i;
  my %approvedCandidates = ();

  my $checkTVStatement = $DBH->prepare("select * from $HISTORY_TABLE where name=? and episode=?");
  my $checkMovieStatement = $DBH->prepare("select * from $HISTORY_TABLE where name = ?");
  my $insertTV = $DBH->prepare("insert into $HISTORY_TABLE(name, episode, url,release) values(?, ?, ?, ?)");
  my $insertMovie = $DBH->prepare("insert into $HISTORY_TABLE(name, url,release) values(?, ?, ?)");

  for my $key (keys %$candidates) {
    $key =~ /$rMovieName/;
    my $name = $1;
    my $group = $3;
    my $rows = 0;
    my $isTV=0;
    my $episode='';
    my $nzbName = $configs->{downloadFolder}."/$name";
    
    if ($name =~ $rSerieID) {
      $name = $1;
      $episode = $2;

      $checkTVStatement->execute(lc($name), uc($episode));
      $rows= $checkTVStatement->fetchrow_array;
      $isTV++;
      $nzbName=$configs->{downloadFolder}."/$name.$episode";
    }else {
      $checkMovieStatement->execute(lc($name));
      $rows= $checkMovieStatement->fetchrow_array;
    }
    $nzbName.=".nzb";
    if (!$rows) {
      $approvedCandidates{$key} = $candidates->{$key};

      for my $url (@{$candidates->{$key}}) {

	my $response = $ua->get($url, ':content_file'=>$nzbName);

	unless ( $response->is_success ) {
	  warn $response->status_line;
	  next;
	}
	if ($isTV) {
	  $insertTV->execute(lc($name), uc($episode), $url, $group);
	}else {
	  $insertMovie->execute(lc($name), $url, $group);
	}

	
	last;
      }
    }
  }

  return \%approvedCandidates;
  
}

sub start_processing{
  my ($DBH, $configs) = @_;
  my $browser = LWP::UserAgent->new(
				    agent => "PerVerT App/1.0",
				    ssl_opts => { verify_hostname => 0 },
				   );

  my $rRequired = $configs->{requiredRegexp};
  my $rIgnored = $configs->{ignoredRegexp};
  my $rMovieName = $configs->{movieNameRegexp};
  my $rSerieID = $configs->{serieIdRegexp};
#  say "$rSerieID";
  my %candidates = ();

  
  open my $ifh,'<', $configs->{requests};
  my @wishList = ();
  while (<$ifh>) {
    chomp;
    push @wishList, $_ if($_ ne '');
  }
#  use Data::Dumper;
#  say Dumper(@wishList);
  
  close $ifh;

  for my $data (@{$configs->{feeds}}) {
    my $url = $data->{url};
    my $website = $data->{name};
    say "Extracting from $website";

    my $response = $browser->get($url);
    
    eval{
      my $content = $response->content;
      $content =~ s/&bull;//gi;
      my $dom = XML::LibXML->load_xml(string => $content);
      for my $item ($dom->findnodes('//channel/item')) {
	my $title = $item->findvalue('title');
	if ($title !~ /$rIgnored/i && $title =~ /$rRequired/) {
#	  say "\t\t1st Check!: $rMovieName";
	  my $reg = qr/$rMovieName/i;

	  #Algorithm:
	  #1- The title needs to match the movie name regexp, so we can extract the requested info
	  #2- We need to split the words from the title and from the wish
	  #3- We need to compare them one by one.
	  #4- If the count is zero then goes to the next wish
	  #5- If the count isn't zero then apply treshold.
	  if ($title =~ $reg) {

	    my $name = $1;
	    my $group = $3;
	    my $episode = 0;

#	    say "\t\t Extracted the name [$name - [$group]]";
	    
	    $reg = qr/$rSerieID/i;
	    my $isSeries=0;
	    if ($name =~ $reg) {
#	      say "\t\t\t It's a series!";
	      my %data = ();
	      $name = $1;
	      $episode = $2;
	      $isSeries=1;
	    }

	    my $titleWordsCount = split(/\./, $name);
	    for my $wish (@wishList) {
	      my $count=0;
	      my $removeSeries=0;
	      my @wishWords = split(/\.|\s/, $wish);
	      for my $wishWanted (@wishWords) {
		$reg = qr/$wishWanted/i;
		if ($name =~ $reg) {
		  $count++;
		  if (index(lc($wishWanted), 's0') != -1 ||
		      lc($wishWanted) =~ /^s\\d/ ||
		      lc($wishWanted) =~  /^s\d/)   {
		    $removeSeries++;
		  }
		}elsif ($isSeries && $episode =~ $reg) {
		  $count++;
		}
	      }
	      next if $count == 0;
	      $count-- if $removeSeries; #To remove the S
	      #apply treshold
	      my $minimumTresholdCount = floor($titleWordsCount * 0.3);
	      #If count is bigger than the treshold and it matched all the wishwords
	      if ($count > $minimumTresholdCount && $count == @wishWords || 1==@wishWords) {
		say "$title => $wish";
		
		my @dataList = ();
		
		if (exists $candidates{$title}) {
		  @dataList = @{$candidates{$title}};
		}
		
		push @dataList, $item->findvalue('link');
		$candidates{$title}= \@dataList;
		
	      }
	    }
	  }
	}
      }
    };
    if ($@) {
      warn $@;
    }
      
  }
  
  check_duplicates_and_download($DBH, $configs, \%candidates, $browser);
  $DBH->disconnect;
}


sub main{
  my $CONFIG;

  GetOptions("config=s"=>\$CONFIG);
  if (!defined $CONFIG || !-e $CONFIG) {
    say "Please define a valid configuration file";
    exit 0;
  }
  open my $configFH, '<', $CONFIG;
  my $configs;
  
  {
    local $/;
    $configs = decode_json( <$configFH> );
  }
  close $configFH;

  if (!-e $configs->{historyDatabase}) {
    say "Please define a correct history database in the configuration file";
    exit 0;
  }

  my $DBH = DBI->connect("dbi:SQLite:dbname=".$configs->{historyDatabase},"","", {RaiseError=>1, AutoCommit=>1});
  my $verified = 0;
  for my $table ($DBH->tables('','main','%','TABLE')){
    $verified++ if ($HISTORY_TABLE eq (split(/"/, $table))[3]);
  }
  if (!$verified) {
    say "Please define a correct sqlite table.";
    exit 0;
  }

  start_processing $DBH, $configs;

  $DBH->disconnect;
  
}
main;

