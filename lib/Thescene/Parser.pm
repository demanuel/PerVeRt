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

my %REGEXP=(language=> qr/\.(DANiSH|SWEDiSH|NORWEGiAN|GERMAN|iTALiAN|FRENCH|RUSSIAN|SPANiSH|PORTUGUESE|ENGLiSH|FiNNiSH|GREEK|DUTCH)/,
            subtitles => qr/\.(NORDiC|MULTi(SUBS)?|([A-Z].?subs)|PT|HU|NL|RU|RO)/,
            resolution=> qr/\.(\d{3,4}[pi])/i,
            format => qr/\.([xh]26[45]|divx|xvid)/i,
            audio => qr/\.(mp\d|aac|ac3|dts|dd5|flac)/,
            group => qr/-([[:alnum:]]+)$/,
            episode => qr/\.([sS]\d{1,3}([dD]|[eE]|DiSC)\d{1,3}|[eE]\d{1,3})/,
            source => qr/\.(\w+rip|(?<!complete\.)bluray|web([-]?dl)?|xxx|(hd[-]?)?cam|t(ele)?s(ync)?|hdtv|(bd|dvd)scr|r5|line|(m)?bdr)/i,
            backup => qr/\.(DVDR(?![iI])|COMPLETE\.[M]?BLURAY)/,
            date => qr/\.(?!\d{3,4}[pPiI])([12]\d{1,3}(\.\d{2}\.\d{2})?)/,
            container => qr/\.(MP4|WMV|MKV)/i,
            fix => qr/\.(DIRFIX|NFOFIX|SAMPLEFIX|SYNCFIX|PROOFFIX)/i,
            type => qr/\.(PROPER|READ.NFO|REPACK|INTERNAL|VC\d|RERIP|DC|EXTENDED|UNCUT|REMASTERED|UNRATED|THEATRICAL|CHRONO|SE|WS|FS|REAL|RETAIL|EXTENDED|RATED|DUB(BED)?|SUBBED|FINAL|COLORIZED|FESTIVAL|STV|LIMITED)/
            );
            
sub parse_name{
  my ($title) = @_;
  return {source=>'ERROR'} if(0 != ($title =~ tr/a-zA-Z0-9.-//c));  
  my %data = (language=>'ENGLiSH'); #defaults
  for my $key (keys %REGEXP){
    $title =~ s/$REGEXP{$key}/./;
    $data{$key}=$1 if defined $1;
  }
  
  if($title =~ /(.*?)\.\./){
    $data{title}= $1;
    if(exists $data{backup}){
      $data{source}='backup';
      if($data{backup} =~ /bluray/i){
        $data{backup} = 'bluray';
      }elsif(lc($data{backup}) eq 'dvdr'){
        $data{backup} = 'dvd';
      }
    }
    
    if(exists $data{source} && lc($data{source}) eq 'xxx'){
      $title =~ /\.\.(.*?)\.\./;
      $data{desc} = $1;
    }
    
    for (keys %REGEXP){
      $data{$_} = undef if(!exists $data{$_});
    }
   
    return \%data;
  }else{
    return {source=>'ERROR'};
  }
  
}            

1;
