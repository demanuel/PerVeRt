package Thescene::Parser;
use 5.020;
use strict;
use warnings;
use Data::Dumper;

use Exporter 'import';
our @EXPORT = qw/
parse_episode
parse_resolution
parse_language
parse_subtitles
parse_date
parse_source
parse_fix
parse_type
parse_audio
parse_release_group
parse_codec
parse_string
/;

my %RESTRICTED = map {$_ => 1} qw/
subs
/;

sub parse_date {
  my ($title) = @_;
  return _extract_simple(qr/\.(((\d{4}\.\d{2}\.\d{2}))|((\d{2}\.\d{2}\.\d{4}))|((\d{2}\.\d{2}\.\d{2}))|((\d{4})))[\.-]/, $title);
}

sub parse_release_group {
  my ($title) = @_;
  my $group;
  my @regexp = (
    qr/-([aA-zZ0-0]+)$/,
    qr/^([aA-zZ0-0]+?)\.*-/,
  );
  for my $re (@regexp) {
    if($title =~ /$re/ && !$RESTRICTED{$1}) {
      $group = $1;
      $title =~ s/$group//;
      $title =~ s/^-|-$//;
      last;
    }
  }
  return [$group, $title];
}

sub parse_codec {
  my ($title) = @_;

  my $results = _extract_simple(qr/\.(([xh]\.*26[45])|(divx)|(xvid))[\.-]?/i, $title );
  if ($results->[0]) {
    $results->[0] =~ s/\.//;
    $results->[0] = lc $results->[0];

  }
  return $results;
}


sub parse_resolution {
  my ($title) = @_;
  return _extract_simple(qr/\.(\d{3,4}[pi])[\.-]?/i, $title);
}

sub parse_type {
  my ($title) = @_;
  return _extract_simple(qr/\.((PROPER)|(READ\.*NFO)|(REPACK)|(iNTERNAL)|(VC\d)|(RERiP)|(DC)|(EXTENDED)|(UNCUT)|(REMASTERED)|(UNRATED)|(THEATRiCAL)|(CHRONO)|(SE)|(WS)|(FS)|(REAL)|(CONVERT)|(RETAIL)|(EXTENDED)|(RATED)|(DUB(BED)?)|(FINAL)|(COLORIZED)|(FESTIVAL)|(STV)|(LIMITED))[\.-]?/, $title);
}

sub parse_fix {
  my ($title) = @_;
  return _extract_simple(qr/\.(((DIR)|(NFO)|(SAMPLE)|(SYNC)|(PROOF))\.*(FIX)*)[\.-]?/, $title);
}

sub parse_audio {
  my ($title) = @_;
  my $results = _extract_simple(qr/\.((mp\d)|(aac(\d\.\d)?)|(ac3d*)|(dts(\.dl)*)|(dd[\.p]*[25]\.[01])|(flac))[\.-]?/i,$title);
  if ($results->[0]) {
    $results->[0] = uc $results->[0];
    my $count = $results->[0] =~ tr/.//;
    $results->[0] =~ s/\.// if($count == 2);
  }

  return $results;
}

sub parse_source {
  my ($title) = @_;
  my @regexps = (
    qr/\.((complete\.)?(m?blu-?ray))[\.-]?/i,
    qr/\.(((bd(scr(eener)?)?)|(p?dvd((scr(eener)?))?)|(ts)|(bd)|(br)|((((amzn)|(hulu)|(nf))\.)?web-?((dl)|(cap))?)|(tv)|(vhs)|(hd-?((tv|ts)|(cam))?)|(vod)|(ds)|(sat)|(dth)|(dvb)|(ppv)|(ddc)|(wp)|(workprint)|(r[0-9](\.line)?))(ri?p?)?)[\.-]?/i,
    qr/\.(t(ele)?((sync)|(cine))?)[\.-]?/i
  );
  my $source;
  for my $re (@regexps) {
    if($title =~ /$re/) {
      $source = $1;
      $title =~ s/\.$source//;
      $source = uc $source;
      last;
    }
  }

  return [$source, $title];
}

sub parse_language {
  my ($title) = @_;

  my $data = [];

  if($title =~ /\.audio\./i) {
    (my $stripped = $title) =~ s/\.audio\..*//i;
    my %langs = map {$_=> 1} qw/en pt cn de no se nordic fr french english swedish norwegian spa spanish eng portuguese multi nl dutch dk dan danish/;
    my @words = reverse split(/\./, $stripped); 

    for my $w (@words) {
      if($langs{lc $w}) {
        if ($data->[0]) {
          $data->[0] .= ", $w";
        } else {
          $data->[0] = $w;
        }
        $title =~ s/[\.-]$w(?=\.audio)//i;
        $data->[1] = $title;
      } else {
        $title =~ s/\.audio//i;
        last;
      }
    }
  } else {
    while(1) {
      my $new_data = _extract_simple(qr/[\.-](dutch|nordic|german|portuguese|ita(lian)*|multi|((dan|eng*l*|span*|swed*)(ish)*)|(true)*french|dk)[\.-](?!subs*)/i, $title);
      $title = $new_data->[1];
      $data->[1] = $title;
      last if !$new_data->[0];
      if ($data->[0]) {
        $data->[0] .= ", $new_data->[0]";
      } else {
        $data->[0] = $new_data->[0];
      }
    }
  }

  if (!$data->[0]) {
    $data->[0] = 'original' 
  }
  else {
    $data->[0] = uc $data->[0];
  }

  return [$data->[0], $data->[1]];
}

sub parse_subtitles {
  my ($title) = @_;

  my $data = [];
  my @langs = sort {length $b <=> length $a} qw/multi pt italian ita cn kor dk swe swedish heb portuguese pt korean en eng english 
  ger german nl dutch fin finnish danish spa spanish nor norwegian fr french ingebakken/;
  if($title =~ /\.subs*\./i) {
    my %langs = map {$_ => 1} @langs;
    (my $stripped = $title) =~ s/\.subs\..*//i;
    my @words = reverse (split(/\./,$stripped));
    # say Dumper(@words);
    for my $w (@words) {
      if($langs{lc $w}) {
        # say "EXIST $w!";
        $title =~ s/\.$w(?=.subs)//i;
        if ($data->[0]) {
          $data->[0] .=", $w";
        } else {
          $data->[0] = $w;
        }
      } else {
        $title =~ s/\.subs//i;
        last;
      }
    }
    $data->[1] = $title;
  }
  elsif ($title =~ /(?:[\.-])*((vost(fr)*)|(subbed|hc))(?:[\.-])*/i) {
    $data->[0] = $1;
    $data->[1] = $title;
    $data->[1] =~ s/[\.-]\Q$data->[0]\E//; 
  }
  else {
    for my $lang (@langs) {
      if ($title =~  /((\Q$lang\Esubs*)|(sub$lang))/i) {
        $data->[0] = $1;
        $title =~ s/\.\Q$data->[0]\E//;
        $data->[1] = $title;
        last;
      } 
    }
  }
  $data->[1] = $title if !$data->[0];
  return $data;
}

sub parse_episode {
  my ($title) = @_;
  my $data = _extract_simple(qr/\.((s?\d{1,3}(\.*[exd]\d{1,3})*)|(s\d{1,3}disc\d{1,3})|(e\d{1,3}))[\.-]/i,$title);
  if ($data->[0]) {
    $data->[0] = uc $data->[0];
    $data->[0] =~ s/\.//;
  }
  return $data;
}

sub parse_title {
  my ($title) = @_;
  return _extract_simple(qr/([^-]*?)\.(?:(((\d{2,4})*(\d{2,4})*(\d{2,4}))|(s?\d{1,3}([exd]\d{1,3})?)|(\d{3,4}p)))/i, $title);
  # return _extract_simple(qr/^(.*)\.?(?:((\d{2,4})*(\d{2,4})*(\d{2,4}))|(\.s{2,3}))?/i, $title);
}

sub parse_string {
  my ($string) = @_;
  my %data = ();
  return \%data if $string =~ /[^aA-zZ0-9\-\.]/;
  # say $string;
  # $string = quotemeta($string);
  # $string =~ s/\\$//;

  my $data = parse_audio($string);
  $data{audio} = $data->[0] if $data->[0];
  # say "2",$data->[1];

  $data = parse_codec($data->[1]);
  $data{codec} = $data->[0] if $data->[0];
  # say "5",$data->[1];

  $data = parse_episode($data->[1]);
  $data{episode} = $data->[0] if $data->[0];
  # say "1",$data->[1];

  $data = parse_date($data->[1]);
  $data{date} = $data->[0] if $data->[0];
  # say "3",$data->[1];

  $data = parse_fix($data->[1]);
  $data{fix} = $data->[0] if $data->[0];
  # say "4",$data->[1];

  $data = parse_language($data->[1]);
  $data{language} = $data->[0] if $data->[0];
  # say "6",$data->[1];

  $data = parse_release_group($data->[1]);
  $data{group} = $data->[0] if $data->[0];
  # say "7",$data->[1];

  $data = parse_resolution($data->[1]);
  $data{resolution} = $data->[0] if $data->[0];
  # say "8",$data->[1];

  $data = parse_source($data->[1]);
  $data{source} = $data->[0] if $data->[0];

  $data = parse_subtitles($data->[1]);
  $data{subtitles} = $data->[0] if $data->[0];

  $data = parse_type($data->[1]);
  $data{type} = $data->[0] if $data->[0];

  $data = parse_title($string);
  $data{title} = $data->[0] if $data->[0];
  

  return \%data;
}

sub _extract_simple {
  my ($re, $title) = @_;
  # say "'$title' >>>$re<<< ". (caller())[2];
  my $match;
  if($title =~ /$re/) {
    $match = $1;
    $match =~ s/^\.+|\.+$//g;
    $title =~ s/[\.-]$match//;
  }

  return [$match, $title];
}


1;
