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
use Thescene::Parser qw/parse_string/;
use LWP::UserAgent;
use XML::LibXML;
use Data::Dumper;

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
    my $name = $_->{name};
    print "Connecting to $name ";
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
        $title =~ s/\s+\-\s+$name$//;
        if ($title =~ /\s/){
          my @words = split(/\s+/, $title);
          $title = join('.',@words[0..$#words-1]).'-'.$words[-1];
        }
        my $data = parse_string($title);
        # say $title;
        # say Dumper($data);
        next if !$data->{source} || !$data->{resolution} || !$data->{source} || !$data->{group} || !$data->{title};
        $data->{title}=join(".",map{ucfirst $_; } split(/\./, lc($data->{title})));
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
            if($data->{$k} !~ /$regexp/){
              $approved=0;
              last;
            }
          }
          if($approved){
            $data->{url}=$item->findvalue('link');
            my $searchTerms = join(' ', map{$_.':'.$wish->{$_}} keys %$wish);
            $data->{search}=$searchTerms;
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
   print_candidate($_) for (@candidates);

   @candidates = @{_filter_and_remove_duplicates($configs, $dbh, \@candidates)};
   say "Number of candidates approved: ".@candidates;

   for my $data (@candidates){
    print 'Downloading: '.$data->{title};
    print " ".$data->{episode} if exists $data->{episode};
    print " ".$data->{date} if exists $data->{date};
    print " ".$data->{resolution} if exists $data->{resolution};

    my $isDownloaded = _download($configs, $browser, $data);
    _store_data_to_db($dbh, $data) if $isDownloaded;
   }
}

sub print_candidate {
  my ($candidate) = @_;

  print "[$candidate->{title}] ";
  print "[$candidate->{episode}] " if(exists $candidate->{episode});
  print "[$candidate->{date}] " if(exists $candidate->{date});
  print "[$candidate->{source}] " if(exists $candidate->{source});
  print "[$candidate->{group}] " if(exists $candidate->{group});
  print "[$candidate->{audio}] " if(exists $candidate->{audio});
  print "[$candidate->{fix}] " if(exists $candidate->{fix});
  print "[$candidate->{codec}] " if(exists $candidate->{fix});
  print "[$candidate->{language}] " if(exists $candidate->{language});
  print "[$candidate->{resolution}] " if(exists $candidate->{resolution});
  print "[$candidate->{subtitles}] " if(exists $candidate->{subtitles});
  print "[$candidate->{type}] " if(exists $candidate->{type});
  print "[$candidate->{desc}] " if(exists $candidate->{desc} && $candidate->{desc} ne '');
  print "[$2] " if ($candidate->{url} =~ /http(s)?:\/\/(.*?)\//);
  print "\n";

}

sub _filter_and_remove_duplicates{
  my ($configs, $dbh, $downloadList) = @_;
  my @finalDownloadList=();
  my @candidates=();
  my @finalList = ();

  # We need this to make sure that the proper realeases have priority
  my @downloadList = sort {
    if(exists $a->{type} && $a->{type} =~ /proper/i){
      return -1;
    }elsif(exists $b->{type} && $b->{type} =~ /proper/i){
      return 1;
    }else{
      # We prefer the ones with more parameters set. However if they have the same number of parameters set
      # we prefer the ones with higher resolution.
      if (keys %$a == keys %$b) {
        if(exists $a->{resolution} && exists $b->{resolution}) {
          return _convert_resolution_to_int($a->{resolution}) <=> _convert_resolution_to_int($b->{resolution});
        } else {
          return 0;
        }
      }
      return keys %$a cmp keys %$b; 
    } } @$downloadList;

  for my $candidate (@downloadList){
    print "Checking ";
    print_candidate($candidate);
    
    if(!_exists_in_history($dbh, $candidate) && !_is_filtered($configs->{filters}, $candidate)){
	my $ignore = 0;
	say "\tDoesn't exist in history and is not filtered - Checking previous candidates";
	for my $position (0..$#finalList){
	    my $finalCandidate = $finalList[$position];
	    if (lc($finalCandidate->{title}) eq lc($candidate->{title})){
		if($finalCandidate->{episode} eq $candidate->{episode}) {
		    say "Found already processed candidate for the same media. Discarding this one";
		    $ignore = 1;
		    last;
		}
	    }
	}
	push @finalList, $candidate if !$ignore;
    }
  }
  say "Candidates approved: ";
  print "\t" && print_candidate $_ for(@finalList);

  return \@finalList;
}

sub _convert_resolution_to_int{
  my ($resolution) = @_;
  return 0 if !$resolution;
  $resolution =~ /(\d+).+/;
  return int($1);
}

sub _load_wishes{

  my ($configs) = @_;
  my @wishList = ();
  
  open my $ifh,'<', $configs->{requests} or die "Unable to open file $configs->{requests}: $!";

  while (<$ifh>) {
    chomp;
    next if $_ eq '';
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

  my $outputFile = $data->{title};
  $outputFile .= '.'.$data->{episode} if exists $data->{episode};
  $outputFile .= '.'.$data->{date} if exists $data->{date};
  $outputFile .= '.nzb';

  my $response = $browser->get($data->{url}, ':content_file'=>$configs->{downloadFolder}."/$outputFile");
  if($response->is_error){
    say "[Unable to connect: ",$response->code."]";
    return 0;
  }
  print "\n";
  return 1;
}


sub _is_filtered{
  my ($filters, $data) = @_;

  my $filterName;
  my $accept_download=0;
  for my $k (keys %$data){
    next if !exists $data->{$k};
    $filterName='accept'.ucfirst $k;
      if(exists $filters->{$filterName}){
      for my $filter (@{$filters->{$filterName}}){
        my $regexp = qr/$filter/i;
        if ($data->{$k} !~ $regexp){
	    $accept_download += 1;
        }
      }

      # Didn't match any of the accepted filter
      if ($accept_download == @{$filters->{$filterName}} && @{$filters->{$filterName}} != 0) {
	  say "\tIgnored because of accepted filter @{$filters->{$filterName}}";
	  return 1;
      }
      $accept_download=0;
    }

    $filterName='ignore'.ucfirst $k;
    if(exists $filters->{$filterName}){
      for my $filter (@{$filters->{$filterName}}){
        my $regexp = qr/$filter/i;
        if ($data->{$k} =~ $regexp){
	    say "\tIgnored because of $filter [$data->{$k} vs $regexp]";
	    return 1;
        }
      }
    }
  }

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

  my $query = 'select * from history where valid=1 and title like ?';
  my @parameters = $data->{title};

  if(exists $data->{episode}){
    $query.=' and episode like ?';
    push @parameters, $data->{episode};
  }elsif(exists $data->{date}){
    $query.=' and date like ?';
    push @parameters, $data->{date};
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
    # except the url and the valid parameter.
    @parameters = grep {$_ ne 'url' && $_ ne 'valid'} keys %$data;

    $query = 'select * from history where '.join(' and ', map{ "'$_' like ?";} @parameters );
    $stmt = $dbh->prepare($query);
    $stmt->execute(map{$data->{$_}} @parameters);

    ($tuples, $rows) = $dbh->selectall_arrayref($stmt);
    return scalar(@$tuples)>0;

  }
  return 1;
}

sub _store_data_to_db{
  my ($dbh, $data) = @_;
  return 0 if !defined $data->{search} || !defined $data->{url};
  my @parameters = qw/language title subtitles resolution codec audio group episode source date fix type search url/;
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
