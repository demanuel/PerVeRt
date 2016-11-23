# PerVeRt
Simple download automation (PVR) for Usenet


## Goals
Having a simple (KISS philosophy) PVR that downloads NZBs when they appear online.

Why a fancy gui, when i just want to setup a whish list? Why a local HTTP server
when i just want something that runs periodicaly to see if my wishes are available?

**K**eep **I**t **S**imple **S**tupid

This tries to *Do one thing and do it well*

### What it will do
Download NZBs that correspond to your wishlist as soon as it appears in the indexer.

This tries to follow the most possible way the scene rules so a nzb named with "[", "]", "_" or
any other character that ain't in the official set are ignored.

*Note* When i started this i wasn't aware of [Flexget](http://www.flexget.com/). So think
about this as something similar (and way more simpler and less features) but only for usenet


### What it doesn't do
1. Show the calendar of upcoming episodes.
2. Search the usenet
3. Automatic failed download handling
4. Run pre or post processing scripts
5. Download your shows
6. Waste your machine resources
7. Notify another application
8. File Renaming



## Requirements
1. Perl 5.018 with the following modules:
 * JSON
 * XML::LibXML
 * LWP::UserAgent
 * DBI
2. Sqlite 3
3. A job scheduler (cron in linux or Task Scheduler in windows)
4. NZB indexers with RSS

## Install
1. Create a sqlite database with the script provided in the DB folder
2. Create a conf file. You can take the one in the conf/ folder as a model
3. Execute pervert periodicaly. For example using cron to run every 15 minutes:
```
*/15 * * * * perl /path/to/pervert/folder/pervert.pl -c /path/to/pervert/config/folder/pervert.cfg
```

## Configuration
The configuration file is a json file:
```JSON
{
    "feeds":[
        {
            "name": "your indexer",
            "url": "http://indezer.com/rss/"
        },
        {
            "name": "Another nzb indexer",
            "url": "http://nzb/rss"
        }
    ],
    "requests":"/path/to/requests.txt",
    "historyDatabase": "/path/to/sqlite/database/created/in/step/1/database.sqlite",
    "downloadFolder": "/path/to/save/nzbs",
    "filters":{
        "acceptLanguage":["ENGLiSH"],
        "acceptSubtitles":[],
        "acceptResolution":[],
        "acceptFormat":[],
        "acceptAudio":[],
        "acceptGroup":[],
        "acceptEpisode":[],
        "acceptSource":[],
        "acceptBackup":[],
        "acceptDate":[],
        "acceptContainer":[],
        "acceptFix":[],
        "ignoreType":[],
        "ignoreLanguage":["GERMAN","SPANiSH","FRENCH","iTALiAN"],
        "ignoreSubtitles":["NORiC","NL"],
        "ignoreResolution":[],
        "ignoreFormat":[],
        "ignoreAudio":[],
        "ignoreGroup":[],
        "ignoreEpisode":[],
        "ignoreSource":[],
        "ignoreBackup":[],
        "ignoreDate":[],
        "ignoreContainer":[],
        "ignoreFix":[],
        "ignoreType":[],

    }
}

```

### configuration
**Please be sure that the configuration file is a valid JSON file!**
Use a [online json validator](http://jsonlint.com/)

- feeds: You can add how many RSS feeds you want

- requests: path to text file with your requests

- filters: filters to apply. There are 2 kinds of filters: the "ignore" and the "accept".
The ignore ones, will make the nzb to be filtered and ignored if it matches
The accept ones, will make the nzb to not be filtered if it matches.
Example:
Wish "my.video"
```
ignoreResolution: ["720[pi]"]
```
If there's a matching result "my.video.720p", then this will be ignored and not downloaded.

However

```
acceptResolution: ["720[pi]"]
```
will make all the matches that contains "720p" to not be filtered.


*Note*: Just because the match wasn't filtered it doesn't mean that it will be downloaded.
If there's already a match with the same name in the DB, then it will not be downloaded.
To be downloaded, you need to set the field "valid" in the DB to zero.

#### requests/wish list


the requests file defined in the configurations must have something like:
```
my.series episode:s0[6-9]
my.movie.name group:group
```

The spaces are used to split between fields (fields available: language, subtitles, resolution, format, audio, group, episode, source, backup, date, container, fix, type).
The title field is the default one. Doing
```
this is my name
```

will search for a title with the word "thisismyname".


```
this is my name s03e04
```
will search for a title with the word "thisismynames03e04".

What you probably want is:
```
this.is.my.name episode:s03e04
```

or

```
this.is.my.name date:2016
```


## Database
If you want to re-download new match of NZB previously downloaded, please set the "valid"
field in the database as zero.

You can consult the download history in the sqlite database by:
```SQL
select * from history
```


