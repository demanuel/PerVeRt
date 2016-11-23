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

  my $browser = LWP::UserAgent->new(agent => "PerVerT App/1.0",
                                    ssl_opts => { verify_hostname => 0 });
   
   my @wishes = @{_load_wishes($configs)};
   my @candidates = ();
  
   for (@{$configs->{feeds}}){
    my $response = $browser->get($_->{url});
    eval{
      my $content = $response->content;
      $content =~ s/&bull;//gi;
      my $dom = XML::LibXML->load_xml(string => $content);
      for my $item ($dom->findnodes('//channel/item')) {
        my $title = $item->findvalue('title');
        my $data = parse_name($title);
        
        next if defined $data->{source} && $data->{source} eq 'ERROR';
        for my $wish (@wishes){
          my $approved=1;
          for my $k (keys %$wish){
            next if !defined $data->{$k};
            #say "Checking [$k] -=> ".$data->{$k};
            my $regexp = qr/$wish->{$k}/i;
            if($data->{$k} !~ $regexp){
              #say "Doesnt match!";
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
    print "[$_->{episode}] " if(defined $_->{episode});
    print "[$_->{language}] " if(defined $_->{language});
    print "[$_->{subtitle}] " if(defined $_->{subtitle});
    print "\r\n";
   }
   @candidates = @{_filter_and_remove_duplicates($configs, $dbh, \@candidates)};
   say "Number of candidates approved: ".@candidates;
   
   for my $data (@candidates){
    say 'Downloading: '.$data->{title};
    _download($configs, $browser, $data);
    _store_data_to_db($dbh, $data);
   }
}

sub _filter_and_remove_duplicates{
  my ($configs, $dbh, $downloadList) = @_;
  my @finalDownloadList=();
  my %candidates=();
  my @finalList = ();
  
  my %resolutions=(0=>[]);
  for my $candidate (@$downloadList){
    if(!_exists_in_history($dbh, $candidate) && !_is_filtered($configs->{filters}, $candidate)){
      if(!defined $candidate->{resolution}){
        push @{$resolutions{0}}, $candidate;
      }else{
        $candidate->{resolution} =~ /(\d+)[pi]/i;
        my $resolution = $1;
  
        if(!exists $resolutions{$resolution}){
        $resolutions{$resolution}=[$candidate];
        }else{
          push @{$resolutions{$resolution}}, $candidate;
        }
      }
    }
  }
  
  for my $resolution (sort{$b<=>$a;} keys(%resolutions)){
    for my $possibleCandidate (@{$resolutions{$resolution}}){
      my $append = 1;
      for my $finalCandidate (@finalList){
        if($possibleCandidate->{title} eq $finalCandidate->{title}){
          
          if(defined $possibleCandidate->{episode}){
            if($possibleCandidate->{episode} eq $finalCandidate->{episode}){
              $append = 0;
            }
          }else{
            $append = 0;
          }
        }
      }
      push @finalList, $possibleCandidate if($append);
    }
  }
  return \@finalList;
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
  my $response = $browser->get($data->{url}, ':content_file'=>$configs->{downloadFolder}.'/'.$data->{title}.(defined $data->{episode}?'.'.$data->{episode}:'-'.$data->{group}).'.nzb');
}


sub _is_filtered{
  my ($filters, $data) = @_;
  say $data->{title};
  #use Data::Dumper;
  #say Dumper($filters);
  my $filterName;
  for my $k (keys %$data){
    next if !defined $data->{$k};
    $filterName='accept'.ucfirst $k;
    if(exists $filters->{$filterName}){
      for my $filter (@{$filters->{$filterName}}){
        my $regexp = qr/$filter/i;
        say "Accept $data->{$k} =~ $filter ? ";
        if ($data->{$k} =~ $regexp){
         return 0;
        }
      }
    }
    $filterName='ignore'.ucfirst $k;
    if(exists $filters->{$filterName}){
      for my $filter (@{$filters->{$filterName}}){
        my $regexp = qr/$filter/i;
        say "Ignore $data->{$k} =~ $filter ? ";
        if ($data->{$k} =~ $regexp){
          say "\tIgnored!";
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
  if(defined $data->{episode}){
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
    return scalar(@$tuples)>0;
  }else{
    return 1;  
  }  
}

sub _store_data_to_db{
  my ($dbh, $data) = @_;
  
  return 0 if !defined $data->{query} || !defined $data->{url};
  my @parameters = qw/language title subtitles resolution format audio group episode source backup date container fix type desc query url/;
  my $query = 'insert into history('.join(',',map{"'$_'"} @parameters).') values('.join(',', map{'?'} @parameters).')';
  my $stmt = $dbh->prepare($query);
  my $rv = $stmt->execute(map{$data->{$_}}@parameters) or die 'Error while storing data: '.$stmt->errstr;
  return 1;
}

           
main;
#my $HISTORY_TABLE="history";
#
#
#sub main{
#
#  my $CONFIG;
#
#  GetOptions("config=s"=>\$CONFIG);
#  if (!defined $CONFIG || !-e $CONFIG) {
#    say "Please define a valid configuration file";
#    exit 0;
#  }
#  open my $configFH, '<', $CONFIG;
#  my $configs;
#  
#  {
#    local $/;
#    $configs = decode_json( <$configFH> );
#  }
#  close $configFH;
#
#  if (!-e $configs->{historyDatabase}) {
#    say "Please define a correct history database in the configuration file";
#    exit 0;
#  }
#  
#  my $DBH = DBI->connect("dbi:SQLite:dbname=".$configs->{historyDatabase},"","", {RaiseError=>1, AutoCommit=>1});
#  my $verified = 0;
#  for my $table ($DBH->tables('','main','%','TABLE')){
#    $verified++ if ($HISTORY_TABLE eq (split(/"/, $table))[3]);
#  }
#  if (!$verified) {
#    say "Please define a correct sqlite table.";
#    exit 0;
#  }
#  
#  
#  $DBH->disconnect;
#  
#  
#}
#
#main;

#
#parse_name('Solkongen.DVDRip.XviD-PlayTime');
####say '*'x80;
#parse_name('One.Million.Years.B.C.DVDrip.Hu.XviD-Jethro');
####say '*'x80;
#parse_name('Psyclops.DVDRip.XviD-iMpiRE');
####say '*'x80;
#parse_name('Shaun.Of.The.Dead.2004.DVDRip.XviD-DMT');
####say '*'x80;
#parse_name('Emmas.Chance.2016.DVDRip.XviD-FRAGMENT');
####say '*'x80;
#parse_name('Blood.In.Blood.Out.1993.iNTERNAL.DVDRip.XviD-MULTiPLY');
####say '*'x80;
#parse_name('Diplomacy.2014.SUBBED.DVDRip.XviD-FRAGMENT');
####say '*'x80;
#parse_name('The.Border.1982.DVDrip.XViD-Jack.Nicholson');
####say '*'x80;
#parse_name('The.Big.Boss.1971.REMASTERED.WS.ENGLISH.DUB.DvdRip.Xvid.ac3-bRUCElEE');
####say '*'x80;
#parse_name('The.Beastmaster.1982.DVDRiP.XviD.AC3-RipTorn');
####say '*'x80;
#parse_name('The.Amazing.Spiderman.1977.DVDrIp.XViD-RaRe');
####say '*'x80;
#parse_name('The.Adventures.Of.Rocky.And.Bullwinkle.2000.DvDrip.XViD-RB');
####say '*'x80;
#parse_name('The.Accused.1988.DVDRip.XviD-BDMF');
####say '*'x80;
#parse_name('Harley.Davidson.and.the.Marlboro.Man.1991.iNTERNAL.DVDRip.XviD-MUPP');
####say '*'x80;
#parse_name('My.Beautiful.Laundrette.1985.DVDRip.AC3.Xvid.iNT-420RipZ');
####say '*'x80;
#parse_name('Masters.of.the.Universe.1987.DVDRip.XviD-CrEwSaDe');
####say '*'x80;
#parse_name('Madeline.1998.DVDrIP.XViD-RedHead');
####say '*'x80;
#parse_name('Lord.Of.The.Flies.1990.DVDRip.XviD-MgM');
####say '*'x80;
#parse_name('Little.Nemo.1989.DVDrIp.XVId-ClassiC');
####say '*'x80;
#parse_name('Kung.Fu.Panda.Secrets.Of.The.Furious.Five.DVDRip.XviD-VoMiT');
####say '*'x80;
#parse_name('Hollow.Man.2.2006.DVDrIP.XViD-Slater');
####say '*'x80;
#parse_name('Hail.Mary.1985.DVDRip.XViD-RPS');
####say '*'x80;
#parse_name('Gullivers.Travels.1996.DVDrIP.XViD-Danson');
####say '*'x80;
#parse_name('Gorgo.1961.DVDRiP.XViD-OldSkool');
####say '*'x80;
#parse_name('Gideons.Trumpet.1980.DVDrIp.XViD-Henryfonda');
####say '*'x80;
#parse_name('Boyish.2011.DVDRiP.XviD-SCARED');
####say '*'x80;
#parse_name('The.Day.The.Earth.Stood.Still.DVDRip.XviD.2008.BiAUDiO-USL');
####say '*'x80;
#parse_name('Wild.2014.DVDScr.XVID.AC3.HQ.Hive-CM8');
####say '*'x80;
#parse_name('The.Hobbit.The.Battle.of.the.Five.Armies.2014.TS.XViD-BiG');
####say '*'x80;
#parse_name('Exodus.Gods.And.Kings.2014.TS.XViD-BiG');
####say '*'x80;
#parse_name('The.Vanished.Empire.2008.PRIVATE.RU.DVDRip.XviD-FLS');
####say '*'x80;
#parse_name('The.Icelandic.Dream.2000.DVDRip.XviD-AEN');
####say '*'x80;
#parse_name('Help.Gone.Mad.2009.INTERNAL.RU.DVDRip.XviD-FLS');
####say '*'x80;
#parse_name('Armour.Of.God.2.1991.iNTERNAL.DVDRiP.XViD-VH');
####say '*'x80;
#parse_name('Radio.Day.2008.INTERNAL.RU.DVDRip.XviD-FLS');
####say '*'x80;
#parse_name('007.Skyfall.2012.TS.XviD-MiLKYBARKiD');
####say '*'x80;
#parse_name('Fable_-_Kiss_My_Trance_Vol_01_Af_Green.INTERNAL.DVDRip.XviD-YT');
####say '*'x80;
#parse_name('The.Forgiveness.of.Blood.2011.LIMITED.DVDRip.XviD.NFOFiX-ESPiSE');
####say '*'x80;
#parse_name('Floorplay-The_Beatr.LIMITED.DVDRip.XviD-DMT');
####say '*'x80;
#parse_name('Flucht.aus.LA.Germ01E01.DVDRiP.XviD-PyRo');
####say '*'x80;
#parse_name('Northpole.Open.For.Christmas.2015.DVDRip.x264-GHOULS');
####say '*'x80;
#parse_name('Billionaire.Boy.2016.DVDRip.x264-GHOULS');
####say '*'x80;
#parse_name('The.BFG.2016.1080p.BluRay.x264-SPARKS');
####say '*'x80;
#parse_name('Smokey.And.The.Bandit.3.1983.1080p.BluRay.x264-MOOVEE');
####say '*'x80;
#parse_name('Sex.Ed.2014.720p.BluRay.x264-VETO');
####say '*'x80;
#parse_name('The.BFG.2016.BDRip.x264-SPARKS');
####say '*'x80;
#parse_name('Sex.Ed.2014.1080p.BluRay.x264-VETO');
####say '*'x80;
#parse_name('The.BFG.2016.720p.BluRay.x264-SPARKS');
####say '*'x80;
#parse_name('Wonders.of.the.Arctic.3D.2014.1080p.BluRay.x264-GUACAMOLE');
####say '*'x80;
#parse_name('Smokey.And.The.Bandit.3.1983.720p.BluRay.x264-CiNEFiLE');
####say '*'x80;
#parse_name('Wonders.of.the.Arctic.2014.1080p.BluRay.x264-GUACAMOLE');
####say '*'x80;
#parse_name('Wonders.of.the.Arctic.2014.720p.BluRay.x264-GUACAMOLE');
####say '*'x80;
#parse_name('Wonders.of.the.Arctic.2014.BDRiP.x264-GUACAMOLE');
####say '*'x80;
#parse_name('Smokey.and.the.Bandit.II.1980.720p.BluRay.x264-PSYCHD');
####say '*'x80;
#parse_name('Panzer.Chocolate.2013.DVDRip.x264-EiDER');
####say '*'x80;
#parse_name('Strike.1925.REMASTERED.BDRip.x264-VoMiT');
####say '*'x80;
#parse_name('Manos.The.Hands.of.Fate.1966.THEATRiCAL.iNTERNAL.BDRip.x264-LiBRARiANS');
####say '*'x80;
#parse_name('The.Sect.2014.1080p.BluRay.x264-SADPANDA');
####say '*'x80;
#parse_name('Manos.The.Hands.of.Fate.1966.THEATRiCAL.1080p.BluRay.x264-SADPANDA');
####say '*'x80;
#parse_name('Manos.The.Hands.of.Fate.1966.THEATRiCAL.720p.BluRay.x264-SADPANDA');
####say '*'x80;
#parse_name('Manos.The.Hands.of.Fate.1966.1080p.BluRay.x264-SADPANDA');
####say '*'x80;
#parse_name('Manos.The.Hands.of.Fate.1966.720p.BluRay.x264-SADPANDA');
####say '*'x80;
#parse_name('Strike.1925.1080p.BluRay.x264-SADPANDA');
####say '*'x80;
#parse_name('Strike.1925.720p.BluRay.x264-SADPANDA');
####say '*'x80;
#parse_name('Manos.The.Hands.of.Fate.1966.REMASTERED.BDRip.x264-VoMiT');
####say '*'x80;
#parse_name('The.Squid.and.the.Whale.2005.REMASTERED.1080p.BluRay.x264-HD4U');
####say '*'x80;
#parse_name('The.Squid.and.the.Whale.2005.REMASTERED.720p.BluRay.x264-HD4U');
####say '*'x80;
#parse_name('The.Unbidden.2016.DVDRip.x264-EiDER');
####say '*'x80;
#parse_name('One-Eyed.Jacks.1961.REMASTERED.1080p.BluRay.x264-DEPTH');
####say '*'x80;
#parse_name('One-Eyed.Jacks.1961.REMASTERED.720p.BluRay.x264-DEPTH');
####say '*'x80;
#parse_name('One-Eyed.Jacks.1961.REMASTERED.BDRip.x264-DEPTH');
####say '*'x80;
#parse_name('Looking.The.Movie.2016.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Billy.Connolly.High.Horse.Tour.2016.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Billy.Connolly.High.Horse.Tour.2016.BDRip.x264-HAGGiS');
####say '*'x80;
#parse_name('Billy.Connolly.High.Horse.Tour.2016.720p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Emergency.Call.A.Murder.Mystery.2014.DVDRip.x264-FiCO');
####say '*'x80;
#parse_name('Dont.Breathe.2016.1080p.BluRay.x264-SPARKS');
####say '*'x80;
#parse_name('Dont.Breathe.2016.BDRip.x264-SPARKS');
####say '*'x80;
#parse_name('Dont.Breathe.2016.720p.BluRay.x264-SPARKS');
####say '*'x80;
#parse_name('Finances.of.the.Grand.Duke.1924.BDRip.x264-BiPOLAR');
####say '*'x80;
#parse_name('Nine.Lives.2016.NTSC.MULTi.DVDR-FUTiL');
####say '*'x80;
#parse_name('Uncle.Nick.2015.COMPLETE.BLURAY-BRDC');
####say '*'x80;
#parse_name('Bastille.Day.2016.MULTi.COMPLETE.BLURAY-MHT');
####say '*'x80;
#parse_name('Alien.Arrival.2016.NTSC.MULTi.DVDR-FUTiL');
####say '*'x80;
#parse_name('Finding.Dory.2016.NTSC.MULTi.DVDR-FUTiL');
####say '*'x80;
#parse_name('Grown.Ups.2.2013.MULTiSUBS.COMPLETE.BLURAY-GERUDO');
####say '*'x80;
#parse_name('Passenger.Legs.of.Steel.2016.COMPLETE.BLURAY-13');
####say '*'x80;
#parse_name('Now.You.See.Me.2.2016.MULTi.COMPLETE.BLURAY-MHT');
####say '*'x80;
#parse_name('Hellraiser.Hellworld.2005.COMPLETE.BLURAY-BRDC');
####say '*'x80;
#parse_name('Scary.Movie.2.2001.COMPLETE.BLURAY-CiNEMATiC');
####say '*'x80;
#parse_name('Mittwoch.04.45.2015.DUAL.COMPLETE.BLURAY-iFPD');
####say '*'x80;
#parse_name('Dont.Look.Now.Were.Being.Shot.At.1966.COMPLETE.BLURAY-UNRELiABLE');
####say '*'x80;
#parse_name('The.Secret.Life.of.Pets.2016.PAL.MULTi.DVDR-FUTiL');
####say '*'x80;
#parse_name('Sweet.Charity.1969.COMPLETE.BLURAY-CiNEMATiC');
####say '*'x80;
#parse_name('Grandview.U.S.A.1984.COMPLETE.BLURAY-watchHD');
####say '*'x80;
#parse_name('McQ.1974.COMPLETE.BLURAY-watchHD');
####say '*'x80;
#parse_name('Assassination.1987.RA.COMPLETE.BLURAY-watchHD');
####say '*'x80;
#parse_name('Hotel.Rwanda.2004.MULTi.COMPLETE.BLURAY-COJONUDO');
####say '*'x80;
#parse_name('Bridge.To.Terabithia.2007.MULTi.COMPLETE.BLURAY-COJONUDO');
####say '*'x80;
#parse_name('Family.Man.2000.DUAL.COMPLETE.BLURAY-iFPD');
####say '*'x80;
#parse_name('Awol.72.2015.MULTI.COMPLETE.BLURAY-FORBiDDEN');
####say '*'x80;
#parse_name('Mercury.Plains.2016.MULTI.COMPLETE.BLURAY-FORBiDDEN');
####say '*'x80;
#parse_name('Brothers.of.War.2015.MULTI.COMPLETE.BLURAY-FORBiDDEN');
####say '*'x80;
#parse_name('Little.Savages.2016.COMPLETE.PAL.DVDR-WaLMaRT');
####say '*'x80;
#parse_name('Alienate.2016.MULTI.COMPLETE.BLURAY-FORBiDDEN');
####say '*'x80;
#parse_name('Savva.3D.2015.MULTi.COMPLETE.BLURAY-FRiENDLESS');
####say '*'x80;
#parse_name('I.Origins.2014.DUAL.COMPLETE.BLURAY-GMB');
####say '*'x80;
#parse_name('Out.1.1971.COMPLETE.BLURAY-watchHD');
####say '*'x80;
#parse_name('The.Blackcoats.Daughter.2015.DUAL.COMPLETE.BLURAY-BDA');
####say '*'x80;
#parse_name('Interiors.1978.COMPLETE.BLURAY-SUPERSIZE');
####say '*'x80;
#parse_name('Sirens.1993.COMPLETE.BLURAY-OCULAR');
####say '*'x80;
#parse_name('The.Pyramid.2014.MULTI.COMPLETE.BLURAY-FORBiDDEN');
####say '*'x80;
#parse_name('Admission.2013.MULTi.COMPLETE.BLURAY.iNTERNAL-XANOR');
####say '*'x80;
#parse_name('True.Story.2015.MULTI.COMPLETE.BLURAY-FORBiDDEN');
####say '*'x80;
#parse_name('The.Tall.Blond.Man.with.One.Black.Shoe.1972.COMPLETE.BLURAY-watchHD');
####say '*'x80;
#parse_name('The.Guard.2011.RA.COMPLETE.BLURAY-watchHD');
####say '*'x80;
#parse_name('Things.to.Come.2016.COMPLETE.BLURAY-watchHD');
####say '*'x80;
#parse_name('Nine.Lives.2016.COMPLETE.QC.BLURAY-4FR');
####say '*'x80;
#parse_name('Skiptrace.2016.COMPLETE.QC.BLURAY-4FR');
####say '*'x80;
#parse_name('The.Godfather.Part.III.1990.iNTERNAL.COMPLETE.BLURAY-watchHD');
####say '*'x80;
#parse_name('Will.Britain.Ever.Have.A.Black.Prime.Minister.HDTV.x264-PLUTONiUM');
####say '*'x80;
#parse_name('Carson.Daly.2016.11.14.Thandie.Newton.HDTV.x264-CROOKS');
####say '*'x80;
#parse_name('Dancing.With.The.Stars.US.S23E13.HDTV.x264-ALTEREGO');
####say '*'x80;
#parse_name('The.Ellen.DeGeneres.Show.2016.11.11.HDTV.x264-ALTEREGO');
####say '*'x80;
#parse_name('The.Daily.Show.2016.11.14.Nate.Silver.HDTV.x264-CROOKS');
####say '*'x80;
#parse_name('Jimmy.Kimmel.2016.11.14.Dwayne.Johnson.HDTV.x264-CROOKS');
####say '*'x80;
#parse_name('Life.With.Boys.S01E07.HDTV.x264-W4F');
####say '*'x80;
#parse_name('Life.With.Boys.S01E16.HDTV.x264-W4F');
####say '*'x80;
#parse_name('Killer.Swarms.2016.HDTV.x264-W4F');
####say '*'x80;
#parse_name('Seth.Meyers.2016.11.14.Aaron.Eckhart.HDTV.x264-CROOKS');
####say '*'x80;
#parse_name('Divorce.S01E06.iNTERNAL.HDTV.x264-TURBO');
####say '*'x80;
#parse_name('Shaun.The.Sheep.S05E17.Checklist.HDTV.x264-DEADPOOL');
####say '*'x80;
#parse_name('Conan.2016.11.14.Lin-Manuel.Miranda.HDTV.x264-CROOKS');
####say '*'x80;
#parse_name('The.Next.Step.S04E16.WEB.h264-ROFL');
####say '*'x80;
#parse_name('SciTech.Now.S02E47.WEB.h264-ROFL');
####say '*'x80;
#parse_name('James.Corden.2016.11.14.Gina.Rodriguez.HDTV.x264-CROOKS');
####say '*'x80;
#parse_name('Stephen.Colbert.2016.11.14.Eddie.Redmayne.HDTV.x264-SORNY');
####say '*'x80;
#parse_name('Winners.and.Losers.S05E13.DVDRip.x264-PFa');
####say '*'x80;
#parse_name('Winners.and.Losers.S05E12.DVDRip.x264-PFa');
####say '*'x80;
#parse_name('Winners.and.Losers.S05E11.DVDRip.x264-PFa');
####say '*'x80;
#parse_name('Winners.and.Losers.S05E10.DVDRip.x264-PFa');
####say '*'x80;
#parse_name('Winners.and.Losers.S05E09.DVDRip.x264-PFa');
####say '*'x80;
#parse_name('Winners.and.Losers.S05E08.DVDRip.x264-PFa');
####say '*'x80;
#parse_name('Winners.and.Losers.S05E07.DVDRip.x264-PFa');
####say '*'x80;
#parse_name('Winners.and.Losers.S05E06.DVDRip.x264-PFa');
####say '*'x80;
#parse_name('Winners.and.Losers.S05E05.DVDRip.x264-PFa');
####say '*'x80;
#parse_name('Winners.and.Losers.S05E04.DVDRip.x264-PFa');
####say '*'x80;
#parse_name('Jimmy.Fallon.2016.11.14.Billy.Bob.Thornton.HDTV.x264-SORNY');
####say '*'x80;
#parse_name('Winners.and.Losers.S05E03.DVDRip.x264-PFa');
####say '*'x80;
#parse_name('Winners.and.Losers.S05E02.DVDRip.x264-PFa');
####say '*'x80;
#parse_name('Winners.and.Losers.S05E01.DVDRip.x264-PFa');
####say '*'x80;
#parse_name('Escape.To.The.Country.S17E05.HDTV.x264-DOCERE');
####say '*'x80;
#parse_name('Kiwi.Living.S02E27.HDTV.x264-FiHTV');
####say '*'x80;
#parse_name('Shortland.Street.S25E196.HDTV.x264-FiHTV');
####say '*'x80;
#parse_name('Escape.To.The.Country.S17E04.HDTV.x264-DOCERE');
####say '*'x80;
#parse_name('Extinct.or.Alive-The.Tasmanian.Tiger.2016.HDTV.x264-W4F');
####say '*'x80;
#parse_name('Love.and.Hip.Hop.Hollywood.S03E14.Reunion.Part.2.HDTV.x264-CRiMSON');
####say '*'x80;
#parse_name('Killer.Hornet.Invasion.2015.HDTV.x264-W4F');
####say '*'x80;
#parse_name('Mike.The.Knight.S02E10.INTERNAL.WEB.h264-ROFL');
####say '*'x80;
#parse_name('Bargain.Hunt.S45E19.Ardingly.15.REAL.WEB.h264-ROFL');
####say '*'x80;
#parse_name('Will.Britain.Ever.Have.A.Black.Prime.Minister.1080p.HDTV.x264-PLUTONiUM');
####say '*'x80;
#parse_name('Will.Britain.Ever.Have.A.Black.Prime.Minister.720p.HDTV.x264-PLUTONiUM');
####say '*'x80;
#parse_name('One.Punch.Man.E07.MULTi.1080p.BluRay.x264-SHiNiGAMi');
####say '*'x80;
#parse_name('Carson.Daly.2016.11.14.Thandie.Newton.720p.HDTV.x264-CROOKS');
####say '*'x80;
#parse_name('Dancing.With.The.Stars.US.S23E13.720p.HDTV.x264-ALTEREGO');
####say '*'x80;
#parse_name('The.Ellen.DeGeneres.Show.2016.11.11.720p.HDTV.x264-ALTEREGO');
####say '*'x80;
#parse_name('The.Daily.Show.2016.11.14.Nate.Silver.720p.HDTV.x264-CROOKS');
####say '*'x80;
#parse_name('Jimmy.Kimmel.2016.11.14.Dwayne.Johnson.720p.HDTV.x264-CROOKS');
####say '*'x80;
#parse_name('Life.With.Boys.S01E07.720p.HDTV.x264-W4F');
####say '*'x80;
#parse_name('Life.With.Boys.S01E16.720p.HDTV.x264-W4F');
####say '*'x80;
#parse_name('Killer.Swarms.2016.720p.HDTV.x264-W4F');
####say '*'x80;
#parse_name('Seth.Meyers.2016.11.14.Aaron.Eckhart.720p.HDTV.x264-CROOKS');
####say '*'x80;
#parse_name('Shaun.The.Sheep.S05E17.Checklist.720p.HDTV.x264-DEADPOOL');
####say '*'x80;
#parse_name('Conan.2016.11.14.Lin-Manuel.Miranda.720p.HDTV.x264-CROOKS');
####say '*'x80;
#parse_name('SciTech.Now.S02E45.720p.WEB.h264-ROFL');
####say '*'x80;
#parse_name('SciTech.Now.S02E46.720p.WEB.h264-ROFL');
####say '*'x80;
#parse_name('SciTech.Now.S02E46.1080p.WEB.h264-ROFL');
####say '*'x80;
#parse_name('SciTech.Now.S02E45.1080p.WEB.h264-ROFL');
####say '*'x80;
#parse_name('SciTech.Now.S02E44.1080p.WEB.h264-ROFL');
####say '*'x80;
#parse_name('Doctors.S18E104.720p.WEB.h264-ROFL');
####say '*'x80;
#parse_name('James.Corden.2016.11.14.Gina.Rodriguez.720p.HDTV.x264-CROOKS');
####say '*'x80;
#parse_name('Stephen.Colbert.2016.11.14.Eddie.Redmayne.720p.HDTV.x264-SORNY');
####say '*'x80;
#parse_name('Jimmy.Fallon.2016.11.14.Billy.Bob.Thornton.720p.HDTV.x264-SORNY');
####say '*'x80;
#parse_name('Looking.S02E10.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Looking.S02E09.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Looking.S02E08.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Looking.S02E07.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Looking.S02E06.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Looking.S02E05.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Looking.S02E04.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Looking.S02E03.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Looking.S02E02.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Looking.S02E01.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Escape.To.The.Country.S17E05.720p.HDTV.x264-DOCERE');
####say '*'x80;
#parse_name('Kiwi.Living.S02E27.720p.HDTV.x264-FiHTV');
####say '*'x80;
#parse_name('Red.Dwarf.S11E06.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Red.Dwarf.S11E05.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Red.Dwarf.S11E04.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Red.Dwarf.S11E03.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Red.Dwarf.S11E02.1080p.BluRay.x264-SHORTBREHD');
####say '*'x80;
#parse_name('Your.Family.Or.Mine.S01D2.COMPLETE.NTSC.DVDR-JFKDVD');
####say '*'x80;
#parse_name('Your.Family.Or.Mine.S01D1.COMPLETE.NTSC.DVDR-JFKDVD');
####say '*'x80;
#parse_name('Suits.S04D04.MULTiSUBS.COMPLETE.BLURAY-GERUDO');
####say '*'x80;
#parse_name('Suits.S04D03.MULTiSUBS.COMPLETE.BLURAY-GERUDO');
####say '*'x80;
#parse_name('Suits.S04D02.MULTiSUBS.COMPLETE.BLURAY-GERUDO');
####say '*'x80;
#parse_name('Suits.S04D01.MULTiSUBS.COMPLETE.BLURAY-GERUDO');
####say '*'x80;
#parse_name('Peanuts.2014.S01D06.DUAL.COMPLETE.BLURAY-FULLSiZE');
####say '*'x80;
#parse_name('Turn.Washingtons.Spies.S03D3.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('Turn.Washingtons.Spies.S03D2.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('Turn.Washingtons.Spies.S03D1.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('The.Making.Of.The.Mob.S02D2.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('The.Making.Of.The.Mob.S02D1.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('Into.The.Badlands.S01D2.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('Into.The.Badlands.S01D1.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('Black.Sails.S03D3.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('Black.Sails.S03D2.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('Black.Sails.S03D1.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('Billions.S01D4.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('Billions.S01D3.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('Billions.S01D2.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('Billions.S01D1.NTSC.DVDR-ToF');
####say '*'x80;
#parse_name('Killjoys.S02D02.MULTi.COMPLETE.BLURAY-XORBiTANT');
####say '*'x80;
#parse_name('Killjoys.S02D01.MULTi.COMPLETE.BLURAY-XORBiTANT');
####say '*'x80;
#parse_name('SAS.Who.Dares.Wins.S01D02.COMPLETE.PAL.DVDR-WaLMaRT');
####say '*'x80;
#parse_name('SAS.Who.Dares.Wins.S01D01.PAL.DVDR-WaLMaRT');
####say '*'x80;
#parse_name('Person.Of.Interest.S04D04.MULTiSUBS.COMPLETE.BLURAY-GERUDO');
####say '*'x80;
#parse_name('Person.Of.Interest.S04D03.MULTiSUBS.COMPLETE.BLURAY-GERUDO');
####say '*'x80;
#parse_name('Person.Of.Interest.S04D02.MULTiSUBS.COMPLETE.BLURAY-GERUDO');
####say '*'x80;
#parse_name('Thomas.The.Tank.Engine.And.Friends.S17D02.PAL.DVDR-WaLMaRT');
####say '*'x80;
#parse_name('Thomas.The.Tank.Engine.And.Friends.S17D01.PAL.DVDR-WaLMaRT');
####say '*'x80;
#parse_name('Alvinnn.And.the.Chipmunks.S01.Vol.3.PAL.DVDR-WaLMaRT');
####say '*'x80;
#parse_name('Attack.on.Titan.S01.DiSC.1.ANiME.DUAL.COMPLETE.BLURAY-iFPD');
####say '*'x80;
#parse_name('Ripper.Street.S04D01.COMPLETE.BLURAY-VEXHD');
####say '*'x80;
#parse_name('Under.The.Dome.S02D04.COMPLETE.BLURAY-HD_Leaks');
####say '*'x80;
#parse_name('Billions.S01D04.COMPLETE.BluRay-o0o');
####say '*'x80;
#parse_name('Billions.S01D03.COMPLETE.BluRay-o0o');
####say '*'x80;
#parse_name('Billions.S01D02.COMPLETE.BluRay-o0o');
####say '*'x80;
#parse_name('Billions.S01D01.COMPLETE.BluRay-o0o');
####say '*'x80;
#parse_name('Rick.and.Morty.S01D01.COMPLETE.BLURAY-UltraHD');
####say '*'x80;
#parse_name('Hell.On.Wheels.S05D03-D4.PROOF.FIX.COMPLETE.BLURAY-COASTER');
####say '*'x80;
#parse_name('SexuallyBroken.16.11.14.Syren.De.Mer.XXX.720p.MP4-MiSTRESS');
####say '*'x80;
#parse_name('BSkow.Big.Ass.Dreams.XXX.720p.MP4-KTR');
####say '*'x80;
#parse_name('Vixen.16.11.15.Kimberly.Moss.XXX.2160p.MP4-KTR');
####say '*'x80;
#parse_name('Vixen.16.11.15.Kimberly.Moss.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('POVPerv.E93.Maria.Jade.32278.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('SinsLife.16.11.11.Halloween.And.Exxxotica.Snaps.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('SinsLife.16.11.07.GoPro.Sex.Tour.Cadence.Lux.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('SinsLife.16.11.05.Darci.Dolce.And.Kissa.Sins.Lesbian.Bedtime.Stories.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('SinsLife.16.11.03.Kissa.Sins.And.Veronica.Rodriguez.Las.Diablas.Rojas.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('VeronicaRodriguez.16.11.14.Veronica.Rodriguez.Cum.On.In.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('VeronicaRodriguez.16.11.12.Veronica.Rodriguez.Uma.Jolie.Live.Show.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('BigGulpGirls.16.11.13.Nicole.Clitman.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('BigGulpGirls.16.11.08.Lexi.Loads.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('BigGulpGirls.16.11.07.Temple.Welch.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('BigGulpGirls.16.11.06.Harmony.Rose.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('BigGulpGirls.16.11.07.Harmony.Rain.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('BackstageBangers.16.11.15.Amirah.Adara.And.Virus.Vellons.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('SisLovesMe.16.11.15.Demi.Lopez.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('BreakingAsses.16.11.15.Tina.Kay.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('TeensLoveMoney.16.11.15.Lilly.Ford.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('FemaleAgent.16.11.15.Alexis.XXX.1080p.MP4-KTR');
#####say '*'x80;
#parse_name('DaneJones.16.11.15.Kayla.Green.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('Pop.Shots.101.Vol.2.XXX.DVDRip.x264-VBT');
####say '*'x80;
#parse_name('Big.Anal.Asses.5.XXX.DVDRip.x264-VBT');
####say '*'x80;
#parse_name('Fucked.Hard.XXX.DVDRip.x264-MOFOXXX');
####say '*'x80;
#parse_name('Couple.Seeking.Teen.21.XXX.DVDRip.x264-MOFOXXX');
####say '*'x80;
#parse_name('Executive.Secretaries.XXX.DVDRip.x264-MOFOXXX');
####say '*'x80;
#parse_name('Party.Hardcore.Gone.Crazy.30.XXX.DVDRip.x264-MOFOXXX');
####say '*'x80;
#parse_name('Teen.Town.XXX.720P.WEBRIP.MP4-GUSH');
####say '*'x80;
#parse_name('Home.Made.Girlfriends.3.XXX.720P.WEBRIP.MP4-GUSH');
####say '*'x80;
#parse_name('Way.Over.40.2.XXX.1080p.WEBRip.MP4-VSEX');
####say '*'x80;
#parse_name('AllOver30.16.11.15.Helen.Volga.XXX.1080p.WMV-YAPG');
####say '*'x80;
#parse_name('AllOver30.16.11.15.Tiffany.Doll.XXX.1080p.WMV-YAPG');
####say '*'x80;
#parse_name('ColombiaFuckFest.16.11.15.Diana.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('Way.Over.40.2.XXX.720p.WEBRip.MP4-VSEX');
####say '*'x80;
#parse_name('FirstBGG.16.11.15.Luna.Corazon.And.Daisy.XXX.2160p.MP4-KTR');
####say '*'x80;
#parse_name('FirstBGG.16.11.15.Luna.Corazon.And.Daisy.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('Personal.Assistant.XXX.1080p.WEBRip.MP4-VSEX');
####say '*'x80;
#parse_name('Personal.Assistant.XXX.720p.WEBRip.MP4-VSEX');
####say '*'x80;
#parse_name('BangPOV.16.11.15.Alice.March.XXX.1080p.MP4-KTR');
####say '*'x80;
#parse_name('Solkongen.DVDRip.XviD-PlayTime');
###say '*'x80;
#parse_name('One.Million.Years.B.C.DVDrip.Hu.XviD-Jethro');
###say '*'x80;
#parse_name('Psyclops.DVDRip.XviD-iMpiRE');
###say '*'x80;
#parse_name('Shaun.Of.The.Dead.2004.DVDRip.XviD-DMT');
###say '*'x80;
#parse_name('Emmas.Chance.2016.DVDRip.XviD-FRAGMENT');
###say '*'x80;
#parse_name('Blood.In.Blood.Out.1993.iNTERNAL.DVDRip.XviD-MULTiPLY');
###say '*'x80;
#parse_name('Diplomacy.2014.SUBBED.DVDRip.XviD-FRAGMENT');
###say '*'x80;
#parse_name('The.Border.1982.DVDrip.XViD-Jack.Nicholson');
###say '*'x80;
#parse_name('The.Big.Boss.1971.REMASTERED.WS.ENGLISH.DUB.DvdRip.Xvid.ac3-bRUCElEE');
###say '*'x80;
#parse_name('The.Beastmaster.1982.DVDRiP.XviD.AC3-RipTorn');
###say '*'x80;
#parse_name('The.Amazing.Spiderman.1977.DVDrIp.XViD-RaRe');
###say '*'x80;
#parse_name('The.Adventures.Of.Rocky.And.Bullwinkle.2000.DvDrip.XViD-RB');
###say '*'x80;
#parse_name('The.Accused.1988.DVDRip.XviD-BDMF');
###say '*'x80;
#parse_name('Harley.Davidson.and.the.Marlboro.Man.1991.iNTERNAL.DVDRip.XviD-MUPP');
###say '*'x80;
#parse_name('My.Beautiful.Laundrette.1985.DVDRip.AC3.Xvid.iNT-420RipZ');
###say '*'x80;
#parse_name('Masters.of.the.Universe.1987.DVDRip.XviD-CrEwSaDe');
###say '*'x80;
#parse_name('Madeline.1998.DVDrIP.XViD-RedHead');
###say '*'x80;
#parse_name('Lord.Of.The.Flies.1990.DVDRip.XviD-MgM');
###say '*'x80;
#parse_name('Little.Nemo.1989.DVDrIp.XVId-ClassiC');
###say '*'x80;
#parse_name('Kung.Fu.Panda.Secrets.Of.The.Furious.Five.DVDRip.XviD-VoMiT');
###say '*'x80;
#parse_name('Hollow.Man.2.2006.DVDrIP.XViD-Slater');
###say '*'x80;
#parse_name('Hail.Mary.1985.DVDRip.XViD-RPS');
###say '*'x80;
#parse_name('Gullivers.Travels.1996.DVDrIP.XViD-Danson');
###say '*'x80;
#parse_name('Gorgo.1961.DVDRiP.XViD-OldSkool');
###say '*'x80;
#parse_name('Gideons.Trumpet.1980.DVDrIp.XViD-Henryfonda');
###say '*'x80;
#parse_name('Boyish.2011.DVDRiP.XviD-SCARED');
###say '*'x80;
#parse_name('The.Day.The.Earth.Stood.Still.DVDRip.XviD.2008.BiAUDiO-USL');
###say '*'x80;
#parse_name('Wild.2014.DVDScr.XVID.AC3.HQ.Hive-CM8');
###say '*'x80;
#parse_name('The.Hobbit.The.Battle.of.the.Five.Armies.2014.TS.XViD-BiG');
###say '*'x80;
#parse_name('Exodus.Gods.And.Kings.2014.TS.XViD-BiG');
###say '*'x80;
#parse_name('The.Vanished.Empire.2008.PRIVATE.RU.DVDRip.XviD-FLS');
###say '*'x80;
#parse_name('The.Icelandic.Dream.2000.DVDRip.XviD-AEN');
###say '*'x80;
#parse_name('Help.Gone.Mad.2009.INTERNAL.RU.DVDRip.XviD-FLS');
###say '*'x80;
#parse_name('Armour.Of.God.2.1991.iNTERNAL.DVDRiP.XViD-VH');
###say '*'x80;
#parse_name('Radio.Day.2008.INTERNAL.RU.DVDRip.XviD-FLS');
###say '*'x80;
#parse_name('007.Skyfall.2012.TS.XviD-MiLKYBARKiD');
###say '*'x80;
#parse_name('Fable_-_Kiss_My_Trance_Vol_01_Af_Green.INTERNAL.DVDRip.XviD-YT');
###say '*'x80;
#parse_name('The.Forgiveness.of.Blood.2011.LIMITED.DVDRip.XviD.NFOFiX-ESPiSE');
###say '*'x80;
#parse_name('Floorplay-The_Beatr.LIMITED.DVDRip.XviD-DMT');
###say '*'x80;
#parse_name('Flucht.aus.LA.Germ01E01.DVDRiP.XviD-PyRo');
###say '*'x80;
#parse_name('Jason.Bourne.2016.BDRip.x264-SPARKS');
##say '*'x80;
#parse_name('Jason.Bourne.2016.720p.BluRay.x264-SPARKS');
##say '*'x80;
#parse_name('Jason.Bourne.2016.1080p.BluRay.x264-SPARKS');
##say '*'x80;
#parse_name('Wrong.Turn.2003.iNTERNAL.DVDRip.x264-REGRET');
##say '*'x80;
#parse_name('Late.Summer.2016.1080p.BluRay.x264-GRUNDiG');
##say '*'x80;
#parse_name('Addicted.to.Fresno.2015.1080p.BluRay.x264-SADPANDA');
##say '*'x80;
#parse_name('Nine.to.Five.2013.REMASTERED.1980.BDRip.x264-VoMiT');
##say '*'x80;
#parse_name('Addicted.to.Fresno.2015.720p.BluRay.x264-SADPANDA');
##say '*'x80;
#parse_name('Addicted.to.Fresno.2015.iNTERNAL.BDRip.x264-LiBRARiANS');
##say '*'x80;
#parse_name('A.Bronx.Tale.1993.iNTERNAL.DVDRip.x264-REGRET');
##say '*'x80;
#parse_name('Good.Will.Hunting.1997.iNTERNAL.DVDRip.x264-REGRET');
##say '*'x80;
#parse_name('Gremlins.1984.iNTERNAL.DVDRip.x264-REGRET');
##say '*'x80;
#parse_name('Morituris.2011.1080p.BluRay.x264-SADPANDA');
##say '*'x80;
#parse_name('Morituris.2011.720p.BluRay.x264-SADPANDA');
##say '*'x80;
#parse_name('Morituris.2011.BDRip.x264-VoMiT');
##say '*'x80;
#parse_name('The.Wrestler.2008.iNTERNAL.DVDRip.x264-REGRET');
##say '*'x80;
#parse_name('Volver.2006.MULTi.1080p.BluRay.x264-FiDELiO');
##say '*'x80;
#parse_name('The.American.Dreamer.1971.1080p.BluRay.x264-SADPANDA');
##say '*'x80;
#parse_name('The.American.Dreamer.1971.720p.BluRay.x264-SADPANDA');
##say '*'x80;
#parse_name('Heaven.Strewn.2011.1080p.BluRay.x264-SADPANDA');
##say '*'x80;
#parse_name('Heaven.Strewn.2011.720p.BluRay.x264-SADPANDA');
##say '*'x80;
#parse_name('Fort.Tilden.2014.1080p.BluRay.x264.x264-BRMP');
##say '*'x80;
#parse_name('Black.Magic.1949.720p.BluRay.x264-CiNEFiLE');
##say '*'x80;
#parse_name('High.Strung.2016.LiMiTED.720p.BluRay.x264-VETO');
##say '*'x80;
#parse_name('At.Cafe.6.2016.1080p.BluRay.x264-ROVERS');
##say '*'x80;
#parse_name('At.Cafe.6.2016.BDRip.x264-ROVERS');
##say '*'x80;
#parse_name('At.Cafe.6.2016.720p.BluRay.x264-ROVERS');
##say '*'x80;
#parse_name('Fort.Tilden.2014.720p.BluRay.x264.x264-BRMP');
##say '*'x80;
#parse_name('High.Strung.2016.LiMiTED.1080p.BluRay.x264-VETO');
##say '*'x80;
#parse_name('Fort.Tilden.2014.RERiP.BDRip.x264-WiDE');
##say '*'x80;
#parse_name('Fort.Tilden.2014.BDRip.x264-WiDE');
##say '*'x80;
#parse_name('The.American.Dreamer.1971.BDRip.x264-VoMiT');
##say '*'x80;
#parse_name('Heaven.Strewn.2011.BDRip.x264-VoMiT');
##say '*'x80;
#parse_name('Planet.of.the.Sharks.2016.1080p.BluRay.x264-UNVEiL');
##say '*'x80;
#parse_name('Planet.of.the.Sharks.2016.720p.BluRay.x264-UNVEiL');
##say '*'x80;
#parse_name('Planet.of.the.Sharks.2016.BDRip.x264-UNVEiL');
##say '*'x80;
#parse_name('Nowhere.Boys-The.Book.of.Shadows.2016.DVDRip.x264-WaLMaRT');
##say '*'x80;
#parse_name('Looking.The.Movie.2016.MULTi.1080p.BluRay.X264-SODAPOP');
##say '*'x80;
#parse_name('Arrowhead.2016.STV.MULTi.1080p.BluRay.x264-ZEST');
##say '*'x80;
#parse_name('Petes.Dragon.2016.MULTi.1080p.BluRay.x264-LOST');
##say '*'x80;
#parse_name('Gleason.DVDR-iGNiTiON');
##say '*'x80;
#parse_name('The.Shallows.2016.MULTi.COMPLETE.BLURAY-COJONUDO');
##say '*'x80;
#parse_name('Betsys.Wedding.1990.COMPLETE.BLURAY-TAPAS');
##say '*'x80;
#parse_name('Nowhere.Boys-The.Book.Of.Shadows.2016.COMPLETE.PAL.DVDR-WaLMaRT');
##say '*'x80;
#parse_name('Nine.Lives.2016.NTSC.MULTi.DVDR-FUTiL');
##say '*'x80;
#parse_name('Uncle.Nick.2015.COMPLETE.BLURAY-BRDC');
##say '*'x80;
#parse_name('Bastille.Day.2016.MULTi.COMPLETE.BLURAY-MHT');
##say '*'x80;
#parse_name('Alien.Arrival.2016.NTSC.MULTi.DVDR-FUTiL');
##say '*'x80;
#parse_name('Finding.Dory.2016.NTSC.MULTi.DVDR-FUTiL');
##say '*'x80;
#parse_name('Grown.Ups.2.2013.MULTiSUBS.COMPLETE.BLURAY-GERUDO');
##say '*'x80;
#parse_name('Passenger.Legs.of.Steel.2016.COMPLETE.BLURAY-13');
##say '*'x80;
#parse_name('Now.You.See.Me.2.2016.MULTi.COMPLETE.BLURAY-MHT');
##say '*'x80;
#parse_name('Hellraiser.Hellworld.2005.COMPLETE.BLURAY-BRDC');
##say '*'x80;
#parse_name('Scary.Movie.2.2001.COMPLETE.BLURAY-CiNEMATiC');
##say '*'x80;
#parse_name('Mittwoch.04.45.2015.DUAL.COMPLETE.BLURAY-iFPD');
##say '*'x80;
#parse_name('Dont.Look.Now.Were.Being.Shot.At.1966.COMPLETE.BLURAY-UNRELiABLE');
##say '*'x80;
#parse_name('The.Secret.Life.of.Pets.2016.PAL.MULTi.DVDR-FUTiL');
##say '*'x80;
#parse_name('Sweet.Charity.1969.COMPLETE.BLURAY-CiNEMATiC');
##say '*'x80;
#parse_name('Grandview.U.S.A.1984.COMPLETE.BLURAY-watchHD');
##say '*'x80;
#parse_name('McQ.1974.COMPLETE.BLURAY-watchHD');
##say '*'x80;
#parse_name('Assassination.1987.RA.COMPLETE.BLURAY-watchHD');
##say '*'x80;
#parse_name('Hotel.Rwanda.2004.MULTi.COMPLETE.BLURAY-COJONUDO');
##say '*'x80;
#parse_name('Bridge.To.Terabithia.2007.MULTi.COMPLETE.BLURAY-COJONUDO');
##say '*'x80;
#parse_name('Family.Man.2000.DUAL.COMPLETE.BLURAY-iFPD');
##say '*'x80;
#parse_name('Awol.72.2015.MULTI.COMPLETE.BLURAY-FORBiDDEN');
##say '*'x80;
#parse_name('Mercury.Plains.2016.MULTI.COMPLETE.BLURAY-FORBiDDEN');
##say '*'x80;
#parse_name('Brothers.of.War.2015.MULTI.COMPLETE.BLURAY-FORBiDDEN');
##say '*'x80;
#parse_name('Little.Savages.2016.COMPLETE.PAL.DVDR-WaLMaRT');
##say '*'x80;
#parse_name('Alienate.2016.MULTI.COMPLETE.BLURAY-FORBiDDEN');
##say '*'x80;
#parse_name('Savva.3D.2015.MULTi.COMPLETE.BLURAY-FRiENDLESS');
##say '*'x80;
#parse_name('I.Origins.2014.DUAL.COMPLETE.BLURAY-GMB');
##say '*'x80;
#parse_name('Out.1.1971.COMPLETE.BLURAY-watchHD');
##say '*'x80;
#parse_name('The.Blackcoats.Daughter.2015.DUAL.COMPLETE.BLURAY-BDA');
##say '*'x80;
#parse_name('Interiors.1978.COMPLETE.BLURAY-SUPERSIZE');
##say '*'x80;
#parse_name('Sirens.1993.COMPLETE.BLURAY-OCULAR');
##say '*'x80;
#parse_name('The.Pyramid.2014.MULTI.COMPLETE.BLURAY-FORBiDDEN');
##say '*'x80;
#parse_name('Admission.2013.MULTi.COMPLETE.BLURAY.iNTERNAL-XANOR');
##say '*'x80;
#parse_name('True.Story.2015.MULTI.COMPLETE.BLURAY-FORBiDDEN');
##say '*'x80;
#parse_name('The.Tall.Blond.Man.with.One.Black.Shoe.1972.COMPLETE.BLURAY-watchHD');
##say '*'x80;
#parse_name('The.Guard.2011.RA.COMPLETE.BLURAY-watchHD');
##say '*'x80;
#parse_name('South.Park.S20E08.1080p.HDTV.x264-CRAVERS');
##say '*'x80;
#parse_name('Police.Ten.7.S23E38.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('Police.Ten.7.S23E38.720p.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('Shortland.Street.S25E198.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('Shortland.Street.S25E198.720p.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('Home.And.Away.S29E194.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('NOVA.S44E07.Treasures.of.the.Earth-Power.720p.HDTV.x264-DHD');
##say '*'x80;
#parse_name('Home.And.Away.S29E194.720p.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('Family.Feud.NZ.S01E198.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('Family.Feud.NZ.S01E198.720p.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('American.Greed.S10E18.Diagnosis.Blood.Money.and.Chicago.Jailbreak.HDTV.x264-CRiMSON');
##say '*'x80;
#parse_name('Victorious.S03E12.The.Blonde.Squad.DIRFIX.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Victorious.S03E12.The.Blonde.Squad.DIRFIX.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Two.More.Eggs-Trauncles.Opposites.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Two.More.Eggs-Trauncles.Opposites.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('The.7D.S02E20.HDTV.x264-W4F');
##say '*'x80;
#parse_name('The.7D.S02E20.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Star.vs.the.Forces.of.Evil.S02E13.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Star.vs.the.Forces.of.Evil.S02E13.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E13.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E12.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E13.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E12.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E11.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E11.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E10.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Pawn.Stars.S13E12.Pawn.in.Space.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Miraculous-Tales.of.Ladybug.and.Cat.Noir.S01E24.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Miraculous-Tales.of.Ladybug.and.Cat.Noir.S01E24.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Life.With.Boys.S01E03.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Life.With.Boys.S01E01.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Life.With.Boys.S01E13.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Life.With.Boys.S01E10.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Life.With.Boys.S01E03.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Life.With.Boys.S01E01.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Kuu.Kuu.Harajuku.S01E11.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Kuu.Kuu.Harajuku.S01E09.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Kuu.Kuu.Harajuku.S01E08.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Kuu.Kuu.Harajuku.S01E11.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Kuu.Kuu.Harajuku.S01E10.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Police.Ten.7.S23E38.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('Shortland.Street.S25E198.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('Home.And.Away.S29E194.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('Family.Feud.NZ.S01E198.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('American.Greed.S10E18.Diagnosis.Blood.Money.and.Chicago.Jailbreak.HDTV.x264-CRiMSON');
##say '*'x80;
#parse_name('Victorious.S03E12.The.Blonde.Squad.DIRFIX.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Two.More.Eggs-Trauncles.Opposites.HDTV.x264-W4F');
##say '*'x80;
#parse_name('The.7D.S02E20.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Star.vs.the.Forces.of.Evil.S02E13.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E13.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E12.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E11.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Pawn.Stars.S13E12.Pawn.in.Space.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Miraculous-Tales.of.Ladybug.and.Cat.Noir.S01E24.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Life.With.Boys.S01E03.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Life.With.Boys.S01E01.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Kuu.Kuu.Harajuku.S01E11.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Kuu.Kuu.Harajuku.S01E09.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Kuu.Kuu.Harajuku.S01E08.HDTV.x264-W4F');
##say '*'x80;
#parse_name('ISIS-Rise.of.Terror.2016.HDTV.x264-W4F');
##say '*'x80;
#parse_name('House.of.Horrors.Kidnapped.S03E07.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Cyberwar.S01E11.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Clarence.US.S02E32.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Chicago.PD.S04E07E08.HDTV.x264-FLEET');
##say '*'x80;
#parse_name('Alaska-The.Last.Frontier.S06E05.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Below.Deck.S04E08.PROPER.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Abandoned.2016.S01E10.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Abandoned.2016.S01E09.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Youre.the.Worst.S03E13.HDTV.x264-FLEET');
##say '*'x80;
#parse_name('Queen.Sugar.S01E11.HDTV.x264-BAJSKORV');
##say '*'x80;
#parse_name('Youre.the.Worst.S03E12.HDTV.x264-FLEET');
##say '*'x80;
#parse_name('South.Park.S20E08.HDTV.x264-FLEET');
##say '*'x80;
#parse_name('David.Blaine.Beyond.Magic.2016.INTERNAL.HDTV.x264-CROOKS');
##say '*'x80;
#parse_name('Speechless.S01E07.HDTV.x264-FLEET');
##say '*'x80;
#parse_name('Blindspot.S02E09.HDTV.x264-LOL');
##say '*'x80;
#parse_name('NCAA.Football.2016.10.15.Ohio.State.Vs.Wisconsin.HDTV.x264-WaLMaRT');
##say '*'x80;
#parse_name('Johnny.Carson.1990.05.09.Tony.Randall.DSR.x264-REGRET');
##say '*'x80;
#parse_name('Johnny.Carson.1985.11.14.Robert.Blake.DSR.x264-REGRET');
##say '*'x80;
#parse_name('Johnny.Carson.1984.11.28.Howie.Mandel.iNTERNAL.DSR.x264-REGRET');
##say '*'x80;
#parse_name('Johnny.Carson.1981.11.12.Dom.DeLuise.DSR.x264-REGRET');
##say '*'x80;
#parse_name('South.Park.S20E08.1080p.HDTV.x264-CRAVERS');
##say '*'x80;
#parse_name('Police.Ten.7.S23E38.720p.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('Shortland.Street.S25E198.720p.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('NOVA.S44E07.Treasures.of.the.Earth-Power.720p.HDTV.x264-DHD');
##say '*'x80;
#parse_name('Home.And.Away.S29E194.720p.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('Family.Feud.NZ.S01E198.720p.HDTV.x264-FiHTV');
##say '*'x80;
#parse_name('Victorious.S03E12.The.Blonde.Squad.DIRFIX.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Two.More.Eggs-Trauncles.Opposites.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('The.7D.S02E20.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Star.vs.the.Forces.of.Evil.S02E13.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E13.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E12.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E11.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Regal.Academy.S01E10.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Miraculous-Tales.of.Ladybug.and.Cat.Noir.S01E24.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Life.With.Boys.S01E13.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Life.With.Boys.S01E10.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Life.With.Boys.S01E03.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Life.With.Boys.S01E01.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Kuu.Kuu.Harajuku.S01E11.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Kuu.Kuu.Harajuku.S01E10.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Kuu.Kuu.Harajuku.S01E09.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Kuu.Kuu.Harajuku.S01E08.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('House.of.Horrors.Kidnapped.S03E07.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Halloween.Wars.S07.Most.Monstrous.Scares.Special.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Dr.Dee.Alaska.Vet.S02E11.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Dr.Dee.Alaska.Vet.S02E10.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Clarence.US.S02E32.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Below.Deck.S04E09.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Alaska-The.Last.Frontier.S06E05.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Chicago.PD.S04E07E08.720p.HDTV.x264-FLEET');
##say '*'x80;
#parse_name('Below.Deck.S04E08.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Below.Deck.S04E07.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Below.Deck.S04E06.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Below.Deck.S04E05.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Abandoned.2016.S01E10.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Abandoned.2016.S01E09.720p.HDTV.x264-W4F');
##say '*'x80;
#parse_name('Youre.the.Worst.S03E13.720p.HDTV.x264-FLEET');
##say '*'x80;
#parse_name('Queen.Sugar.S01E11.720p.HDTV.x264-BAJSKORV');
##say '*'x80;
#parse_name('Queen.Sugar.S01E11.1080p.HDTV.x264-BAJSKORV');
##say '*'x80;
#parse_name('BigTitsRoundAsses.16.11.17.Daya.Knight.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('JesseLoadsMonsterFacials.16.11.17.Christina.Cinn.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('AuntJudys.16.11.17.Sexy.Jazzy.Toys.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('JesseLoadsMonsterFacials.16.11.17.Blair.Williams.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('InTheCrack.E1222.Misty.Lovelace.Desert.Oasis.3D.XXX.INTERNAL.1080p.MP4-KTR');
##say '*'x80;
#parse_name('LosConsoladores.16.11.17.Sicilia.And.Tina.Kay.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('InTheCrack.E1222.Misty.Lovelace.XXX.2160p.MP4-KTR');
##say '*'x80;
#parse_name('InTheCrack.E1222.Misty.Lovelace.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('Spizoo.16.11.17.Brittany.Shae.Blowjob.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('OralOverdose.16.11.17.Luna.Star.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('HollyRandall.16.11.17.Bridgette.B.Sensational.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('MyFriendsHotGirl.16.11.17.Jessa.Rhodes.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('IHaveAWife.16.11.17.Alyssa.Lynn.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('JulesJordan.16.11.17.Ana.Foxxx.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('DigitalDesire.16.11.17.Skye.West.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('ExploitedCollegeGirls.16.11.17.Lilly.XXX.720p.MP4-KTR');
##say '*'x80;
#parse_name('Nubiles.16.11.17.Bree.Haze.College.Cutie.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('WowGirls.16.11.17.Aislin.Natural.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('AllFineGirls.16.11.17.Izzy.Delphine.A.Blonde.In.The.Woods.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('Penthouse.International.Interracial.XXX.2014.HDTV.1080p.x264-SHDXXX');
##say '*'x80;
#parse_name('WowGirls.16.11.17.Aislin.Natural.XXX.2160p.MP4-KTR');
##say '*'x80;
#parse_name('AllFineGirls.16.11.17.Izzy.Delphine.A.Blonde.In.The.Woods.XXX.2160p.MP4-KTR');
##say '*'x80;
#parse_name('AllFineGirls.16.11.15.Bala.Free.Sample.XXX.2160p.MP4-KTR');
##say '*'x80;
#parse_name('PascalsSubSluts.16.11.17.Cassie.De.La.Rage.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('ATKGalleria.16.11.17.Lena.Anderson.Solo.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('SinfulXXX.16.11.17.Claudia.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('ATKGalleria.16.11.17.Kharlie.Stone.Masturbation.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('ATKGalleria.16.11.17.Karly.Baker.Masturbation.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('ATKGalleria.16.11.17.Jewels.Vega.Toys.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('PlayboyPlus.16.11.17.Shannon.Troy.Blonde.Beauty.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('ATKHairy.16.11.17.Izzy.J.Solo.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('ATKGirlfriends.16.11.17.Piper.Perri.XXX.2160p.MP4-KTR');
##say '*'x80;
#parse_name('ATKHairy.16.11.17.Erika.Kortni.Masturbation.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('ATKGirlfriends.16.11.17.Piper.Perri.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('Cosmid.16.11.17.Terri.Fletcher.XXX.720p.MP4-KTR');
##say '*'x80;
#parse_name('Bang.Casting.16.11.17.Aubrey.Gold.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('SimplyAnal.16.11.17.Briana.Bounce.XXX.2160p.MP4-KTR');
##say '*'x80;
#parse_name('OnlyBlowJob.16.11.17.Ella.Hughes.XXX.2160p.MP4-KTR');
##say '*'x80;
#parse_name('SimplyAnal.16.11.17.Briana.Bounce.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('NewSensations.16.11.17.Gia.Paige.XXX.1080p.MP4-KTR');
##say '*'x80;
#parse_name('Mr.Right.2015.DUAL.COMPLETE.BLURAY-GMB');
##say '*'x80;
#parse_name('Star.Trek.Beyond.2016.MULTi.COMPLETE.BLURAY-MHT');
##say '*'x80;
#parse_name('Avengers.Grimm.2015.COMPLETE.BLURAY-KEBABRULLE');
##say '*'x80;
#parse_name('Dont.Breathe.2016.COMPLETE.BLURAY-LAZERS');
##say '*'x80;
#parse_name('Mr.Right.2015.MULTi.COMPLETE.BLURAY-UNTOUCHED');
##say '*'x80;
#parse_name('The.Adderall.Diaries.2015.MULTi.COMPLETE.BLURAY-MHT');
##say '*'x80;
#parse_name('Dragon.Ball.Z.The.Tree.Of.Might.1990.Dragon.Ball.Z.Lord.Slug.1991.COMPLETE.BLURAY-BRDC');
##say '*'x80;
#parse_name('A.Bunch.Of.Amateurs.2008.COMPLETE.BLURAY-VEXHD');
##say '*'x80;
