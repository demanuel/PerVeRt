use strict;
use warnings;
use utf8;
use open qw/:std :utf8/;
use 5.020;
use FindBin qw/$Bin/;
use lib "$Bin/lib/";
use JSON;
use Getopt::Long;
use DBI;
use DBD::SQLite;
use Thescene::Parser qw/parse_name/;
use LWP::UserAgent;
use XML::LibXML;

sub main{
  my $configFile;

  GetOptions("config=s"=>\$configFile);
  if (!defined $configFile || !-e $configFile) {
    say "Please define a valid configuration file";
    exit 0;
  }
  open my $configFH, '<', $configFile;
  my $configs;

  {
    local $/;
    $configs = decode_json( <$configFH> );
  }
  close $configFH;


  my $dbh = _load_db($configs->{historyDatabase});

  say "Starting at ".localtime;
  _start_processing($configs, $dbh);

}

sub _start_processing{
   my ($configs, $dbh) = @_;

  my $browser = LWP::UserAgent->new(agent => "PerVeRt App/1.0",
                                    ssl_opts => { verify_hostname => 0 },
                                    timeout => 10);

  my @wishes = @{_load_wishes($configs)};
  my @candidates = ();

  for (@{$configs->{feeds}}){
    print "Connecting to $_->{name} ";
    my $response = $browser->get($_->{url});

    if($response->is_error){
      say "[Unable to connect: ",$response->code."]";
      next;
    }
    print "\n";

    eval{
      my $content = $response->content;
      $content =~ s/&bull;//gi;
      my $dom = XML::LibXML->load_xml(string => $content);
      for my $item ($dom->findnodes('//channel/item')) {
        my $title = $item->findvalue('title');
        my $data = parse_name($title);

        next if $data->{source} eq 'ERROR';
        for my $wish (@wishes){
          my $approved=1;
          for my $k (keys %$wish){
            # next if !exists $data->{$k};
            #All the parameters in the wish must be present
            if (!exists $data->{$k}){
              $approved = 0;
              last;
            }

            my $regexp = qr/$wish->{$k}/i;
            if($data->{$k} !~ $regexp){
              $approved=0;
              last;
            }
          }
          if($approved){
            $data->{url}=$item->findvalue('link');
            my $query = join(' ', map{$_.':'.$wish->{$_}} keys %$wish);
            $data->{query}=$query;
            push @candidates, $data;
          }
        }
      }
    };
    if ($@) {
      warn $@;
    }

   }
   say "Number of candidates found: ".@candidates;
   for (@candidates){
    print "\t[$_->{title}] ";
    print "[$_->{episode}] " if(exists $_->{episode});
    print "[$_->{resolution}] " if(exists $_->{resolution});
    print "[$_->{language}] " if(exists $_->{language});
    print "[$_->{subtitles}] " if(exists $_->{subtitles});
    print "[$_->{date}] " if(exists $_->{date});
    print "[$_->{source}] " if(exists $_->{source});
    print "[$_->{fix}] " if(exists $_->{fix});
    print "[$_->{type}] " if(exists $_->{type});
    print "[$_->{audio}] " if(exists $_->{audio});
    print "[$_->{desc}] " if(exists $_->{desc} && $_->{desc} ne '');
    print "[$2] " if ($_->{url} =~ /http(s)?:\/\/(.*?)\//);
    print "\r\n";
   }
   @candidates = @{_filter_and_remove_duplicates($configs, $dbh, \@candidates)};
   say "Number of candidates approved: ".@candidates;

   for my $data (@candidates){
    print 'Downloading: '.$data->{title};
    my $isDownloaded = _download($configs, $browser, $data);
    _store_data_to_db($dbh, $data) if $isDownloaded;
   }
}


sub _filter_and_remove_duplicates{
  my ($configs, $dbh, $downloadList) = @_;
  my @finalDownloadList=();
  my @candidates=();
  my @finalList = ();

  for my $candidate (@$downloadList){
    if(!_exists_in_history($dbh, $candidate) && !_is_filtered($configs->{filters}, $candidate)){
      my $ignore = 0;
      for my $position (0..$#finalList){
        my $finalCandidate = $finalList[$position];
        if (!defined $finalCandidate){
          push @finalList, $candidate;
          $ignore = 1;
          next;
        }
        if(lc($finalCandidate->{title}) eq lc($candidate->{title}) ){
          if(exists $finalCandidate->{episode} && exists $candidate->{episode} && lc($finalCandidate->{episode}) eq lc($candidate->{episode}) ){
            if(exists $finalCandidate->{resolution} && exists $candidate->{resolution} && _convert_resolution_to_int($finalCandidate->{resolution}) < _convert_resolution_to_int($candidate->{resolution})){
                $finalList[$position] = $candidate;
            }
          }elsif(exists $finalCandidate->{episode} && exists $candidate->{episode} && lc($finalCandidate->{episode}) ne lc($candidate->{episode})){
            push @finalList, $candidate;
          }
          $ignore = 1;
          next;
        }
      }
      push @finalList, $candidate if !$ignore;
    }
  }

  return \@finalList;
}

sub _convert_resolution_to_int{
  my ($resolution) = @_;
  $resolution =~ /^(\d+)\.$/;
  return int($1);

}

sub _load_wishes{

  my ($configs) = @_;
  my @wishList = ();

  open my $ifh,'<', $configs->{requests};

  while (<$ifh>) {
    chomp;
    my %data = (title =>'');
    my @args=split(' ', $_);
    for my $arg (@args){
      if($arg=~ /(.*?):(.*)/){
        $data{$1}=$2;
      }else{
        $data{title}.=$arg;
      }
    }
    push @wishList, \%data;
  }
  close $ifh;

  return \@wishList;
}


sub _download{
  my ($configs, $browser, $data) = @_;

  my $response = $browser->get($data->{url}, ':content_file'=>$configs->{downloadFolder}.'/'.$data->{title}.(exists $data->{episode}?'.'.$data->{episode}:'-'.$data->{releaseGroup}).'.nzb');
  if($response->is_error){
    say "[Unable to connect: ",$response->code."]";
    return 0;
  }
  print "\n";
  return 1;
}


sub _is_filtered{
  my ($filters, $data) = @_;
  say $data->{title};

  my $filterName;
  for my $k (keys %$data){
    next if !exists $data->{$k};
    $filterName='accept'.ucfirst $k;
    if(exists $filters->{$filterName}){
      for my $filter (@{$filters->{$filterName}}){
        my $regexp = qr/$filter/i;
        if ($data->{$k} =~ $regexp){
         return 0;
        }
      }
    }
    $filterName='ignore'.ucfirst $k;
    if(exists $filters->{$filterName}){
      for my $filter (@{$filters->{$filterName}}){
        my $regexp = qr/$filter/i;
        if ($data->{$k} =~ $regexp){
          return 1;
        }
      }
    }
  }

  # All the filters run and it didn't match any
  return 0;
}

sub _load_db{
  my ($dbFile) = @_;

  if (!-e $dbFile) {
    say "Please define a correct history database in the configuration file";
    exit 0;
  }

  my $dbh = DBI->connect("dbi:SQLite:dbname=$dbFile",'','', {RaiseError=>1, AutoCommit=>1});
  my $verified = 0;
  for my $table ($dbh->tables('','main','%','TABLE')){
    $verified++ if ('history' eq lc((split(/"/, $table))[3]));
  }
  if (!$verified) {
    say "Please define a correct sqlite table.";
    exit 0;
  }

  return $dbh;
}

sub _exists_in_history{
  my ($dbh, $data) = @_;

  my $query = 'select * from history where valid=1 and title=?';
  my @parameters = ($data->{title});
  if(exists $data->{episode}){
    $query.=' and episode=?';
    push @parameters, $data->{episode};
  }
  my $stmt = $dbh->prepare($query);
  $stmt->execute(@parameters);
  my ($tuples, $rows) = $dbh->selectall_arrayref($stmt);

  # We don't want to download the same invalid url
  # At this moment it can exist as invalid, so we need to check if it already exists as an invalid
  if (scalar @$tuples == 0){
    $query = 'select * from history where valid= 0 and url=?';
    $stmt = $dbh->prepare($query);
    $stmt->execute($data->{url});
    ($tuples, $rows) = $dbh->selectall_arrayref($stmt);
    return 1 if scalar(@$tuples)>0; # Same URL

    # It can be the same episode but from a different indexer. So we need to check if all the params are different
    # except the url
    @parameters = ();
    for(keys %$data){
      push @parameters, $_ if(exists $data->{$_} && $_ ne 'url');
    }
    $query = 'select * from history where '.join(' and ', map{"$_=?"} @parameters );
    $stmt = $dbh->prepare($query);
    $stmt->execute(map{$data->{$_}} @parameters);

    ($tuples, $rows) = $dbh->selectall_arrayref($stmt);
    return scalar(@$tuples)>0;

  }else{
    return 1;
  }
}

sub _store_data_to_db{
  my ($dbh, $data) = @_;

  return 0 if !defined $data->{query} || !defined $data->{url};
  my @parameters = qw/language title subtitles resolution format audio releaseGroup episode source date container fix type desc query url/;
  my $query = 'insert into history('.join(',',map{"'$_'"} @parameters).') values('.join(',', map{'?'} @parameters).')';
  my $stmt = $dbh->prepare($query);
  my $rv = $stmt->execute(map{$data->{$_}}@parameters) or die 'Error while storing data: '.$stmt->errstr;
  return 1;
}

main;
# parse_name('Deadwood.S03E08.SPANiSH.HDTV.X264-LPH');
# parse_name('HandsOnHardcore.16.11.30.Lexi.Dona.XXX.1080p.MP4-KTR');
# parse_name('Judge.Judy.S18E45.720p.HDTV.x264-WaLMaRT');
# parse_name('La.Que.Se.Avecina.S09E17.SPANiSH.720p.HDTV.x264-BFN');
