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

my $HISTORY_TABLE="history";


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
    
    if ($name =~ /$rSerieID/) {
      $name = $1;
      $episode = $2;

      $checkTVStatement->execute($name, uc($episode));
      $rows= $checkTVStatement->fetchrow_array;
      $isTV++;
      $nzbName=$configs->{downloadFolder}."/$name.$episode";
    }else {
      $checkMovieStatement->execute($name);
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
	  $insertTV->execute($name, uc($episode), $url, $group);
	}else {
	  $insertMovie->execute($name, $url, $group);
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
				    ssl_opts => { verify_hostname => 0 },
				   );

  my $rRequired = $configs->{requiredRegexp};
  my $rIgnored = $configs->{ignoredRegexp};
  my $rMovieName = $configs->{movieNameRegexp};
  my $rSerieID = $configs->{serieIdRegexp};
  my %candidates = ();

  
  open my $ifh,'<', $configs->{requests};
  my @wishList = ();
  while (<$ifh>) {
    chomp;
    push @wishList, $_ if($_ ne '');
  }
  
  close $ifh;

  for my $data (@{$configs->{feeds}}) {
    my $url = $data->{url};
    my $website = $data->{name};
    say "Extracting from $website";

    my $response = $browser->get($url);
    eval{
      my $dom = XML::LibXML->load_xml(string => $response->content);
      for my $item ($dom->findnodes('//channel/item')) {
	my $title = $item->findvalue('title');
	if ($title !~ /$rIgnored/i && $title =~ /$rRequired/) {
	  
	  my $reg = qr/$rMovieName/;
	  
	  if ($title =~ /$reg/i) {
	    my $name = $1;
	    my $group = $3;
	    my $episode = 0;

	    $reg = qr/$rSerieID/i;
	    if ($name =~ /$reg/) {
	      my %data = ();
	      $name = $1;
	      $episode = $2;
	    }

	    my @titleWords = split(/\./, $name);
	    
	    for my $wish (@wishList) {
	      my @words = split(' ',$wish);
	      my $count = 0;
	      for my $wishWord (@words) {
		for (@titleWords) {
		  if ($_ eq $wishWord || $episode =~ /$wishWord/i) {
		    $count++;
		  }
		}
		
	      }
	      #TODO: confirm this
	      #say "[$count]",Dumper(@words);

	      
	      if ($count == @words) {
		say "\t\tmatch: $title [$wish]";
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

