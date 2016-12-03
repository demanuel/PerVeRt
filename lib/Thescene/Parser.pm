package Thescene::Parser;
use 5.020;
use strict;
use warnings;
use Data::Dumper;

use Exporter 'import';
our @EXPORT_OK = qw/parse_name/;

# Language Tags: MULTiSUBS/MULTi/NL/NORDiC/iTALiAN

# This module doesn't pretend to match all the names. There are a bunch of rules that aren't followed...
# so what's the point of the rules ?!?

my @REGULAR_EXPRESSION_ORDER=qw/releaseGroup format audio container episode resolution source date title language subtitles fix type desc/;

my %REGULAR_EXPRESSIONS=(
  releaseGroup => [qr/(?<!web)-([[:alnum:]]+)$/],
  format => [qr/\.([xh]26[45]|divx|xvid)/i],
  audio => [qr/\.(mp\d|aac(\d\.\d)?|ac3|dts|dd5\.1|flac)/i],
  container => [qr/\.(mp4|wmv|mkv)/i],
  episode => [
    qr/\.(s\d{1,3}e\d{1,3})/i,
    qr/\.(s\d{1,3}d\d{1,3})/i,
    qr/\.(s\d{1,3}d\d{1,3})/i,
    qr/\.((s\d{1,3})?DiSC\d{1,3})/i,
    qr/\.(e\d{1,3})/i,
    ],
  resolution => [
    qr/\.(720[pi])/i,
    qr/\.(1080[pi])/i,
    qr/\.(\d{3,4}[pi])/i,
    qr/\.(4k)/i,
    qr/\.(uhd)/i,
  ],
  source => [
    qr/((?<!complete\.)blu[-]?ray)/i,
    qr/\.((hd[-]?)?cam)/i,
    qr/\.(xxx)/i,
    qr/\.(t(ele)?s(ync)?)/i,
    qr/\.(t(ele)?c(ine)?)/i,
    qr/\.((bd|dvd)?scr(eener)?)/i,
    qr/\.((bd|br|web[-]?|tv|dvd|vhs|hd|vod|ds|sat|dth|dvb|hdtv|cam|ppv)rip)/i,
    qr/\.(r[0-9](\.line)?)/i,
    qr/\.(web[-]?(dl|cap)?)/i,
    qr/\.(pdvd)/i,
    qr/\.((hd|pd)tv)/i,
    qr/\.(wp|workprint|ppv|ddc|dsr|vodr)/i,
    qr/\.(blu[-]?ray)/i,
    qr/\.(dvdr)\./i
  ],
  date => [
    qr/\.(\d{4}\.\d{2}\.\d{2})/i,
    qr/\.(\d{2}\.\d{2}\.\d{4})/i,
    qr/\.(\d{2}\.\d{2}\.\d{2})/i,
    qr/\.(\d{4})/i,
  ],
  title => [qr/^(.*?)\.\./],
  language => [
    qr/\.(MULTi|DANiSH|SWEDiSH|NORWEGiAN|GERMAN|iTALiAN|FRENCH|RUSSIAN|SPANiSH|PORTUGUESE|ENGLiSH|FiNNiSH|GREEK|DUTCH)/,
    qr/\.([A-Za-z]{2,3}[\.-]audio)\./i
  ],
  subtitles => [
    qr/\.(ingebakken.subs)\./i,
    qr/\.([A-Za-z]{2,3}[\.-]sub(bed|s)?)\./i,
    qr/\.(sub(DANiSH|SWEDiSH|NORWEGiAN|GERMAN|iTALiAN|FRENCH|RUSSIAN|SPANiSH|PORTUGUESE|ENGLiSH|FiNNiSH|GREEK|DUTCH))\./i,
    ],
  fix => [qr/\.((DIR|NFO|SAMPLE|SYNC|PROOF)FIX)\./i],
  type => [qr/\.(PROPER|READ\.?NFO|REPACK|iNTERNAL|VC\d|RERiP|DC|EXTENDED|UNCUT|REMASTERED|UNRATED|THEATRiCAL|CHRONO|SE|WS|FS|REAL|CONVERT|RETAIL|EXTENDED|RATED|DUB(BED)?|SUBBED|FINAL|COLORIZED|FESTIVAL|STV|LIMITED)/],
  desc => [qr/\.\.((?<!\.)[A-Za-z0-9\.]*?)\.\./]

);

sub parse_name{
  my ($title) = @_;
  return {source=>'ERROR'} if(0 != ($title =~ tr/a-zA-Z0-9.-//c));

  my %data = ();
  for my $k (@REGULAR_EXPRESSION_ORDER){
    for my $regexp (@{$REGULAR_EXPRESSIONS{$k}}){
      if($title =~ $regexp){
        $data{$k} = $1;
        $title =~ s/$regexp/\.\./;
        if($k eq 'episode'){
          $data{$k} = uc($data{$k});
        }
      }
    }
  }

  return {source=>'ERROR'} if (!exists $data{source} || !exists $data{title} || !exists $data{releaseGroup});

  $data{language}='ENGLiSH' if(!exists $data{language} ||  $data{language} eq '');
  # use Data::Dumper;
  # say Dumper(%data);
  return \%data;

}

# sub parse_name{
#   my ($title) = @_;
#   say $title;
#   parse_name2($title);
#
#   return {source=>'ERROR'} if(0 != ($title =~ tr/a-zA-Z0-9.-//c));
#   my %data = (language=>'ENGLiSH'); #defaults
#   for my $key (keys %REGEXP){
#     $title =~ s/$REGEXP{$key}/./;
#     if (defined $1){
#       my $val = $1;
#       if($key eq 'episode'){
#         $val =~ s/s/S/;
#         $val =~ s/e/E/;
#       }
#       $data{$key}=$val;
#     }
#   }
#
#   say join(' ', map{"[$_ $data{$_}]"} keys %data)."\n";
#
#   if($title =~ /(.*?)\.\./){
#
#     return {source=>'ERROR'} if $1=~ /[A-Z]/;
#
#     $data{title}= join('.', map {ucfirst $_;} split(/\./, $1));
#     if(exists $data{backup}){
#       $data{source}='backup';
#       if($data{backup} =~ /bluray/i){
#         $data{backup} = 'bluray';
#       }elsif(lc($data{backup}) eq 'dvdr'){
#         $data{backup} = 'dvd';
#       }
#     }
#
#     if(exists $data{source} && lc($data{source}) eq 'xxx'){
#       $title =~ /\.\.(.*?)\.\./;
#       $data{desc} = $1;
#     }
#
#     for (keys %REGEXP){
#       $data{$_} = undef if(!exists $data{$_});
#     }
#     print "\t\t".join(' ', map{"[$_: $data{$_}]"} keys %data)."\n";
#     return \%data;
#   }else{
#     return {source=>'ERROR'};
#   }
#
# }

1;
