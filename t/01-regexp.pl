use 5.020;
use Test::More;
use FindBin qw/$Bin/;
use lib "$Bin/../lib/";
use Thescene::Parser;
use Data::Dumper;

subtest 'Parse release date' => sub {
  my $data = parse_date('Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  is($data->[0], 2017);
  is($data->[1],'Title.of.the.Release.720p.WEB-DL.MkvCage');
  $data = parse_date('Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-QOQ');
  ok (!$data->[0]);
  is($data->[1],'Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-QOQ');
  $data = parse_date('Title.of.the.Release.S02D2.NTSC.DVDR-ToF');
  ok (!$data->[0] );
  is($data->[1],'Title.of.the.Release.S02D2.NTSC.DVDR-ToF'); 
  $data = parse_date('Group-Title.of.the.Release.2017.bdrip.x264-subs');
  is($data->[0],2017);
  is($data->[1],'Group-Title.of.the.Release.bdrip.x264-subs');
  $data = parse_date('Title.of.the.Release.2016.WEB-DL.720p.H264');
  is($data->[0],2016);
  is($data->[1],'Title.of.the.Release.WEB-DL.720p.H264');
  $data = parse_date('Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  ok(!$data->[0]);
  is($data->[1],'Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  $data = parse_date('Title.of.the.Release.2017.DVDRip.x264-Group');
  is($data->[0], 2017);
  is($data->[1],'Title.of.the.Release.DVDRip.x264-Group');
  $data = parse_date('Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');
  is($data->[0], '2014');
  is($data->[1],'Title.Of.The.Release.S01.E02.LANGUAGE.ANiME.DTS.DL.1080p.BluRay.x264-Group');  
};

subtest 'Parse release group' => sub {
  my $data = parse_release_group('Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  ok(!$data->[0]);
  is($data->[1],'Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  $data = parse_release_group('Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  is ($data->[0], 'Group');
  is($data->[1],'Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264');
  $data = parse_release_group('Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  is ($data->[0], 'Group' ); 
  is($data->[1],'Title.of.the.Release.S02D2.NTSC.DVDR');
  $data = parse_release_group('Group-Title.of.the.Release.2017.bdrip.x264-subs');
  is($data->[0], 'Group');
  is($data->[1],'Title.of.the.Release.2017.bdrip.x264-subs');
  $data = parse_release_group('Title.of.the.Release.2016.WEB-DL.720p.H264');
  ok(!$data->[0]);
  is($data->[1],'Title.of.the.Release.2016.WEB-DL.720p.H264');
  $data = parse_release_group('Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  is($data->[0], 'Group');
  is($data->[1],'Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264');
  $data = parse_release_group('Title.of.The.Release.2017.DVDRip.x264-Group');
  is($data->[0], 'Group');
  is($data->[1],'Title.of.The.Release.2017.DVDRip.x264');
  $data = parse_release_group('Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');
  is($data->[0], 'Group');
  is($data->[1],'Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264');   
};

subtest 'Parse release format' => sub {
  my $data = parse_codec('Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  ok(!$data->[0]);
  is($data->[1],'Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  $data = parse_codec('Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  is ($data->[0], 'h264');
  is($data->[1],'Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1-Group');
  $data = parse_codec('Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  ok(!$data->[0]); 
  is($data->[1],'Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  $data = parse_codec('Group-Title.of.the.Release.2017.bdrip.x264-subs');
  is($data->[0], 'x264');
  is($data->[1],'Group-Title.of.the.Release.2017.bdrip-subs');
  $data = parse_codec('Title.of.the.Release.2016.WEB-DL.720p.H264');
  is($data->[0], 'h264');
  is($data->[1],'Title.of.the.Release.2016.WEB-DL.720p');
  $data = parse_codec('Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  is($data->[0], 'x264');
  is($data->[1],'Title.of.the.Release.S01E02.German.DUBBED.WebRip-Group');
  $data = parse_codec('Title.of.The.Release.2017.DVDRip.x264-Group');
  is($data->[0], 'x264');
  is($data->[1],'Title.of.The.Release.2017.DVDRip-Group');
  $data = parse_codec('Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');
  is($data->[0], 'x264');
  is($data->[1],'Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay-Group');   
  $data = parse_codec('release.title.116.Dvdrip.Xvid-ggroup');
  is($data->[0], 'xvid');
  is($data->[1], 'release.title.116.Dvdrip-ggroup');
};


subtest 'Parse resolution' => sub {
  my $data = parse_resolution('Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  is($data->[0], '720p');
  is($data->[1],'Title.of.the.Release.2017.WEB-DL.MkvCage');
  $data = parse_resolution('Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  is ($data->[0], '1080p');
  is($data->[1],'Title.of.the.Release.S03E11.AMZN.WEB-DL.DD.5.1.H.264-Group');
  $data = parse_resolution('Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  ok(!$data->[0]); 
  is($data->[1],'Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  $data = parse_resolution('Group-Title.of.the.Release.2017.bdrip.x264-subs');
  ok(!$data->[0]);
  is($data->[1],'Group-Title.of.the.Release.2017.bdrip.x264-subs');
  $data = parse_resolution('Title.of.the.Release.2016.WEB-DL.720p.H264');
  is($data->[0], '720p');
  is($data->[1],'Title.of.the.Release.2016.WEB-DL.H264');
  $data = parse_resolution('Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  ok(!$data->[0]);
  is($data->[1],'Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  $data = parse_resolution('Title.of.The.Release.2017.DVDRip.x264-Group');
  ok(!$data->[0]);
  is($data->[1],'Title.of.The.Release.2017.DVDRip.x264-Group');
  $data = parse_resolution('Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');
  is($data->[0], '1080p');
  is($data->[1],'Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.BluRay.x264-Group');   
};

subtest 'Parse type' => sub {
  my $data = parse_type('Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  ok(!$data->[0]);
  is($data->[1],'Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  $data = parse_type('Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  ok(!$data->[0]);
  is($data->[1],'Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  $data = parse_type('Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  ok(!$data->[0]);
  is($data->[1],'Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  $data = parse_type('Group-Title.of.the.Release.2017.bdrip.x264-subs');
  ok(!$data->[0]);
  is($data->[1],'Group-Title.of.the.Release.2017.bdrip.x264-subs');
  $data = parse_type('Title.of.the.Release.2016.WEB-DL.720p.H264');
  ok(!$data->[0]);
  is($data->[1],'Title.of.the.Release.2016.WEB-DL.720p.H264');
  $data = parse_type('Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  is($data->[0], 'DUBBED');
  is($data->[1],'Title.of.the.Release.S01E02.German.WebRip.x264-Group');
  $data = parse_type('Title.of.The.Release.2017.DVDRip.x264-Group');
  ok(!$data->[0]);
  is($data->[1],'Title.of.The.Release.2017.DVDRip.x264-Group');
  $data = parse_type('Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');
  ok(!$data->[0]);
  is($data->[1],'Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');  
};

subtest 'Parse audio' => sub {
  my $data = parse_audio('Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  ok(!$data->[0]); 
  is($data->[1],'Title.of.the.Release.2017.720p.WEB-DL.MkvCage');  
  $data = parse_audio('Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  is($data->[0], 'DD5.1'); 
  is($data->[1],'Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.H.264-Group');
  $data = parse_audio('Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  ok(!$data->[0]); 
  is($data->[1],'Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  $data = parse_audio('Group-Title.of.the.Release.2017.bdrip.x264-subs');
  ok(!$data->[0]);
  is($data->[1],'Group-Title.of.the.Release.2017.bdrip.x264-subs');
  $data = parse_audio('Title.of.the.Release.2016.WEB-DL.720p.H264');
  ok(!$data->[0]); 
  is($data->[1],'Title.of.the.Release.2016.WEB-DL.720p.H264');
  $data = parse_audio('Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  ok(!$data->[0]);
  is($data->[1],'Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  $data = parse_audio('Title.of.The.Release.2017.DVDRip.x264-Group');
  ok(!$data->[0]);
  is($data->[1],'Title.of.The.Release.2017.DVDRip.x264-Group');
  $data = parse_audio('Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');
  is($data->[0], 'DTS.DL');
  is($data->[1],'Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.1080p.BluRay.x264-Group');
};

subtest 'Parse source' => sub {
  my $data = parse_source('Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  is($data->[0], 'WEB-DL'); 
  is($data->[1],'Title.of.the.Release.2017.720p.MkvCage');
  $data = parse_source('Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  is($data->[0], 'AMZN.WEB-DL'); 
  is($data->[1],'Title.of.the.Release.S03E11.1080p.DD.5.1.H.264-Group');
  $data = parse_source('Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  ($data->[0], 'DVDR');
  is($data->[1],'Title.of.the.Release.S02D2.NTSC-Group');
  $data = parse_source('Group-Title.of.the.Release.2017.bdrip.x264-subs');
  is($data->[0], 'BDRIP');
  is($data->[1],'Group-Title.of.the.Release.2017.x264-subs');
  $data = parse_source('Title.of.the.Release.2016.WEB-DL.720p.H264');
  is($data->[0], 'WEB-DL'); 
  is($data->[1],'Title.of.the.Release.2016.720p.H264');
  $data = parse_source('Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  is($data->[0], 'WEBRIP');
  is($data->[1],'Title.of.the.Release.S01E02.German.DUBBED.x264-Group');
  $data = parse_source('Title.of.The.Release.2017.DVDRip.x264-Group');
  is($data->[0], 'DVDRIP');
  is($data->[1],'Title.of.The.Release.2017.x264-Group');
  $data = parse_source('Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');
  is($data->[0], 'BLURAY');
  is($data->[1],'Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.x264-Group');
  $data=parse_source('Title.Of.The.Release.2017.NEW.720p.HD-TS.X264.HQ-GROUP');
  is($data->[0], 'HD-TS');
  is($data->[1], 'Title.Of.The.Release.2017.NEW.720p.X264.HQ-GROUP');
};

subtest 'Parse Language' => sub {
  my $data = parse_language('Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  is($data->[0], 'original'); 
  is($data->[1],'Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  $data = parse_language('Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  is($data->[0], 'original'); 
  is($data->[1],'Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  $data = parse_language('Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  is($data->[0], 'original'); 
  is($data->[1],'Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  $data = parse_language('Group-Title.of.the.Release.2017.bdrip.x264-subs');
  is($data->[0], 'original'); 
  is($data->[1],'Group-Title.of.the.Release.2017.bdrip.x264-subs');
  $data = parse_language('Title.of.the.Release.2016.WEB-DL.720p.H264');
  is($data->[0], 'original'); 
  is($data->[1],'Title.of.the.Release.2016.WEB-DL.720p.H264');
  $data = parse_language('Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  is($data->[0], 'GERMAN'); 
  is($data->[1],'Title.of.the.Release.S01E02.DUBBED.WebRip.x264-Group');
  $data = parse_language('Title.of.The.Release.2017.DVDRip.x264-Group');
  is($data->[0], 'original'); 
  is($data->[1],'Title.of.The.Release.2017.DVDRip.x264-Group');
  $data = parse_language('Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');
  is($data->[0], 'original'); 
  is($data->[1],'Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');
  $data = parse_language('Series.Title.1x08.Episode.Title.ITA-ENG.1080p.WEBMux.x264-Group');
  is($data->[0], 'ITA, ENG'); 
  is($data->[1],'Series.Title.1x08.Episode.Title.1080p.WEBMux.x264-Group');
  $data = parse_language('Series.Title.1x08.Episode.Title.ita-eng.1080p.WEBMux.x264-Group');
  is($data->[0], 'ITA, ENG'); 
  is($data->[1],'Series.Title.1x08.Episode.Title.1080p.WEBMux.x264-Group');  
  $data = parse_language('Series.Title.1x08.Episode.Title.ENG.1080p.WEBMux.x264-Group');
  is($data->[0], 'ENG'); 
  is($data->[1],'Series.Title.1x08.Episode.Title.1080p.WEBMux.x264-Group');
  $data = parse_language('Series.Title.1x08.Episode.Title.SPA.1080p.WEBMux.x264-Group');
  is($data->[0], 'SPA'); 
  is($data->[1],'Series.Title.1x08.Episode.Title.1080p.WEBMux.x264-Group');    
  $data = parse_language('Series.Title.1x08.Episode.Title.DAN.1080p.WEBMux.x264-Group');
  is($data->[0], 'DAN'); 
  is($data->[1],'Series.Title.1x08.Episode.Title.1080p.WEBMux.x264-Group');    
  $data = parse_language('Series.Title.1x08.Episode.Title.ENGLISH.1080p.WEBMux.x264-Group');
  is($data->[0], 'ENGLISH'); 
  is($data->[1],'Series.Title.1x08.Episode.Title.1080p.WEBMux.x264-Group');
  $data = parse_language('Series.Title.1x08.Episode.Title.SPAnish.1080p.WEBMux.x264-Group');
  is($data->[0], 'SPANISH'); 
  is($data->[1],'Series.Title.1x08.Episode.Title.1080p.WEBMux.x264-Group');    
  $data = parse_language('Series.Title.1x08.Episode.Title.DANish.1080p.WEBMux.x264-Group');
  is($data->[0], 'DANISH'); 
  is($data->[1],'Series.Title.1x08.Episode.Title.1080p.WEBMux.x264-Group');    
  $data = parse_language('Title.Multi.Subs.En.Audio.DD5.1.Stuff');
  is($data->[0],'EN');
  is($data->[1], 'Title.Multi.Subs.Audio.DD5.1.Stuff');
  $data = parse_language('release.title.Dk.En.Subs.Dk.Audio.DD5.1.Stuff');
  is($data->[0],'DK');
  is($data->[1], 'release.title.Dk.En.Subs.Audio.DD5.1.Stuff');
  

};

subtest 'Parse subtitles' => sub {
  my $data = parse_subtitles('Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  ok(!$data->[0]);
  is($data->[1],'Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  $data = parse_subtitles('Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  ok(!$data->[0]);
  is($data->[1], 'Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  $data = parse_subtitles('Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  ok(!$data->[0]);
  is($data->[1],'Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  $data = parse_subtitles('Group-Title.of.the.Release.2017.bdrip.x264-subs');
  ok(!$data->[0]);
  is($data->[1],'Group-Title.of.the.Release.2017.bdrip.x264-subs');
  $data = parse_subtitles('Title.of.the.Release.2016.WEB-DL.720p.H264');
  ok(!$data->[0]);
  is($data->[1], 'Title.of.the.Release.2016.WEB-DL.720p.H264');
  $data = parse_subtitles('Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  ok(!$data->[0]);
  is($data->[1], 'Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  $data = parse_subtitles('Title.of.The.Release.2017.DVDRip.x264-Group');
  ok(!$data->[0]);
  is($data->[1], 'Title.of.The.Release.2017.DVDRip.x264-Group');
  $data = parse_subtitles('Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');
  ok(!$data->[0]);
  is($data->[1], 'Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');

  $data = parse_subtitles('Title.2017.S01E01.FASTSUB.VOSTFR.720p.HDTV.x264-Group');
  is($data->[0],'VOSTFR');
  is($data->[1],'Title.2017.S01E01.FASTSUB.720p.HDTV.x264-Group');
  $data = parse_subtitles('Title.Of.The.Release.2017.DOC.SUBFRENCH.720p.WEBRip.x264-TiMELiNE');
  is($data->[0],'SUBFRENCH');
  is($data->[1],'Title.Of.The.Release.2017.DOC.720p.WEBRip.x264-TiMELiNE');

  $data = parse_subtitles('This.is.the.title.2017.DKSUBS.720p.BluRay.x264-Group');
  is($data->[0],'DKSUBS');
  is($data->[1],'This.is.the.title.2017.720p.BluRay.x264-Group');
  $data = parse_subtitles('This.is.the.title.2017.DKSUB.720p.BluRay.x264-Group');
  is($data->[0],'DKSUB');
  is($data->[1],'This.is.the.title.2017.720p.BluRay.x264-Group');
  $data = parse_subtitles('This.is.the.release.title.2017.SUBBED.INTERNAL.1080p.WEB.x264-Group');
  is($data->[0],'SUBBED');
  is($data->[1],'This.is.the.release.title.2017.INTERNAL.1080p.WEB.x264-Group');
  $data = parse_subtitles('Release.Title.2017.XViD.720p.BRRiP.DD5.1.NLSubs-Group');
  is($data->[0],'NLSubs');
  is($data->[1],'Release.Title.2017.XViD.720p.BRRiP.DD5.1-Group');
  $data = parse_subtitles('This.is.my.title.2.2017.720p.BluRay.HebSubs.x264-Group');
  is($data->[0],'HebSubs');
  is($data->[1],'This.is.my.title.2.2017.720p.BluRay.x264-Group');
  $data = parse_subtitles('Title.Multi.Subs.En.Audio.DD5.1.Stuff');
  is($data->[0],'Multi');
  is($data->[1], 'Title.En.Audio.DD5.1.Stuff');
  $data = parse_subtitles('Title.Multi.Subs.En.Audio.DD5.1.Stuff');
  is($data->[0],'Multi');
  is($data->[1], 'Title.En.Audio.DD5.1.Stuff');
  $data = parse_subtitles('release.title.Dk.En.Subs.Dk.Audio.DD5.1.Stuff');
  is($data->[0],'En, Dk');
  is($data->[1], 'release.title.Dk.Audio.DD5.1.Stuff');

};

subtest 'Parse episode' => sub {
  my $data = parse_episode('Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  ok(!$data->[0]);
  is($data->[1], 'Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  $data = parse_episode('Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  is($data->[0], 'S03E11');
  is($data->[1], 'Title.of.the.Release.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  $data = parse_episode('Title.of.the.Release.S02D2.NTSC.DVDR-Group');
  is($data->[0], 'S02D2');
  is($data->[1], 'Title.of.the.Release.NTSC.DVDR-Group');
  $data = parse_episode('Group-Title.of.the.Release.2017.bdrip.x264-subs');
  ok(!$data->[0]);
  is($data->[1], 'Group-Title.of.the.Release.2017.bdrip.x264-subs');
  $data = parse_episode('Title.of.the.Release.2016.WEB-DL.720p.H264');
  ok(!$data->[0]);
  is($data->[1], 'Title.of.the.Release.2016.WEB-DL.720p.H264');
  $data = parse_episode('Title.of.the.Release.S01E02.German.DUBBED.WebRip.x264-Group');
  is($data->[0], 'S01E02');
  is($data->[1], 'Title.of.the.Release.German.DUBBED.WebRip.x264-Group');
  $data = parse_episode('Title.of.The.Release.2017.DVDRip.x264-Group');
  ok(!$data->[0]);
  is($data->[1], 'Title.of.The.Release.2017.DVDRip.x264-Group');
  $data = parse_episode('Title.Of.The.Release.S01.E02.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');
  is($data->[0], 'S01E02');
  is($data->[1], 'Title.Of.The.Release.LANGUAGE.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');

  $data = parse_episode('title.of.the.movie.S01.SUBFRENCH.720p.WEB.H264-miGroupo');
  is($data->[0], 'S01');
  is($data->[1], 'title.of.the.movie.SUBFRENCH.720p.WEB.H264-miGroupo');
  
};

subtest 'Parse string' => sub {
  my $data = parse_string('Title.of.the.Release.2017.720p.WEB-DL.MkvCage');
  is($data->{title},'Title.of.the.Release');
  is($data->{episode}, undef);
  is($data->{date},2017);
  is($data->{source},'WEB-DL');
  is($data->{group}, undef);
  is($data->{audio},undef);
  is($data->{fix},undef);
  is($data->{codec}, undef);
  is($data->{language},'original');
  is($data->{resolution},'720p');
  is($data->{subtitles},undef);
  is($data->{type},undef);

  $data = parse_string('title.of.the.movie.S01.SUBFRENCH.720p.WEB.H264-miGroupo');
  is($data->{title},'title.of.the.movie');
  is($data->{episode}, 'S01');
  is($data->{date},undef);
  is($data->{source},'WEB');
  is($data->{group}, 'miGroupo');
  is($data->{audio},undef);
  is($data->{fix},undef);
  is($data->{codec}, 'h264');
  is($data->{language},'original');
  is($data->{resolution},'720p');
  is($data->{subtitles},'SUBFRENCH');
  is($data->{type},undef);
  
  $data = parse_string('Title.of.the.Release.S03E11.1080p.AMZN.WEB-DL.DD.5.1.H.264-Group');
  is($data->{title},'Title.of.the.Release');
  is($data->{episode}, 'S03E11');
  is($data->{date},undef);
  is($data->{source},'AMZN.WEB-DL');
  is($data->{group}, 'Group');
  is($data->{audio},'DD5.1');
  is($data->{fix},undef);
  is($data->{codec}, 'h264');
  is($data->{language},'original');
  is($data->{resolution},'1080p');
  is($data->{subtitles},undef);
  is($data->{type},undef);  
  $data = parse_string('Title.Of.The.Release.S01.E02.German.2014.ANiME.DTS.DL.1080p.BluRay.x264-Group');
  is($data->{title},'Title.Of.The.Release');
  is($data->{episode}, 'S01E02');
  is($data->{date},2014);
  is($data->{source},'BLURAY');
  is($data->{group}, 'Group');
  is($data->{audio},'DTS.DL');
  is($data->{fix},undef);
  is($data->{codec}, 'x264');
  is($data->{language},'GERMAN');
  is($data->{resolution},'1080p');
  is($data->{subtitles},undef);
  is($data->{type},undef);
  # say Dumper($data); 
  $data = parse_string('Title.of.The.Release.2017.DVDRip.x264-Group');
  is($data->{title},'Title.of.The.Release');
  is($data->{episode}, undef);
  is($data->{date},2017);
  is($data->{source},'DVDRIP');
  is($data->{group}, 'Group');
  is($data->{audio},undef);
  is($data->{fix},undef);
  is($data->{codec}, 'x264');
  is($data->{language},'original');
  is($data->{resolution},undef);
  is($data->{subtitles},undef);
  is($data->{type},undef);
  $data = parse_string('Title.of.the.Release.s01E02.German.DUBBED.WebRip.x264-Group');
  is($data->{title},'Title.of.the.Release');
  is($data->{episode}, 'S01E02');
  is($data->{date},undef);
  is($data->{source},'WEBRIP');
  is($data->{group}, 'Group');
  is($data->{audio},undef);
  is($data->{fix},undef);
  is($data->{codec}, 'x264');
  is($data->{language},'GERMAN');
  is($data->{resolution},undef);
  is($data->{subtitles},undef);
  is($data->{type},'DUBBED');  
  # say Dumper($data); 
  $data = parse_string('Group-Title.of.the.Release.2017.bdrip.x264-subs');
  # say Dumper($data);
  is($data->{title},'Title.of.the.Release');
  is($data->{episode}, undef);
  is($data->{date},2017);
  is($data->{source},'BDRIP');
  is($data->{group}, 'Group');
  is($data->{audio},undef);
  is($data->{fix},undef);
  is($data->{codec}, 'x264');
  is($data->{language},'original');
  is($data->{resolution},undef);
  is($data->{subtitles},undef);
  is($data->{type},undef); 


  $data = parse_string('Group-Title.of.the.Release.2017.bdrip.x.264-subs');
  # say Dumper($data);
  is($data->{title},'Title.of.the.Release');
  is($data->{episode}, undef);
  is($data->{date},2017);
  is($data->{source},'BDRIP');
  is($data->{group}, 'Group');
  is($data->{audio},undef);
  is($data->{fix},undef);
  is($data->{codec}, 'x264');
  is($data->{language},'original');
  is($data->{resolution},undef);
  is($data->{subtitles},undef);
  is($data->{type},undef);


  $data = parse_string('Group-Title.of.the.Release.2017.bdrip.h.264-subs');
  is($data->{title},'Title.of.the.Release');
  is($data->{episode}, undef);
  is($data->{date},2017);
  is($data->{source},'BDRIP');
  is($data->{group}, 'Group');
  is($data->{audio},undef);
  is($data->{fix},undef);
  is($data->{codec}, 'h264');
  is($data->{language},'original');
  is($data->{resolution},undef);
  is($data->{subtitles},undef);
  is($data->{type},undef);

  $data = parse_string('Group.-.Title.of.the.Release.2017.bdrip.h.264-subs');
  is($data->{title},'Title.of.the.Release');
  is($data->{episode}, undef);
  is($data->{date},2017);
  is($data->{source},'BDRIP');
  is($data->{group}, 'Group');
  is($data->{audio},undef);
  is($data->{fix},undef);
  is($data->{codec}, 'h264');
  is($data->{language},'original');
  is($data->{resolution},undef);
  is($data->{subtitles},undef);
  is($data->{type},undef);

  $data = parse_string('Title.of.the.Release.2018.720p.HC.HDRIP.X264.AC3-Group');
  is($data->{title},'Title.of.the.Release');
  is($data->{episode}, undef);
  is($data->{date},2018);
  is($data->{source},'HDRIP');
  is($data->{group}, 'Group');
  is($data->{audio},'AC3');
  is($data->{fix},undef);
  is($data->{codec}, 'x264');
  is($data->{language},'original');
  is($data->{resolution},'720p');
  is($data->{subtitles},'HC');
  is($data->{type},undef);    


};


done_testing;
