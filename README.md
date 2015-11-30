# PeRverT
Simple download automation (PVR) for Usenet


## Goals
Having a simple (KISS philosophy) PVR that downloads NZBs when they appear online.

Why a fancy gui, when i just want to setup a whish list? Why a local HTTP server
when i just want something that runs periodicaly to see if my wishes are available?

**K**eep **I**t **S**imple **S**tupid

*Do one thing and do it well*

### What it will do
Download NZBs that correspond to your wishlist as soon as it appears in the indexer.

### What it doesn't do
1. Show the calendar of upcoming episodes.
2. Search the usenet
3. Automatic failed download handling
4. Run pre or post processing scripts
5. Manage your shows.
6. Download your shows
7. Waste your machine resources
8. Notify another application
9. File Renaming



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
    "requiredRegexp": "regular|expression",
    "ignoredRegexp": "regular|expression",
    "movieNameRegexp": "^(.*?)\\.(1080|720p|x264|webrip).+-(.*)",
    "serieIdRegexp": "(.*)\\.(s\\d{2}e\\d{2})"

}
```

### configuration
**Please be sure that the configuration file is a valid JSON file!**
Use a [online json validator](http://jsonlint.com/)

feeds: You can add how many RSS feeds you want

requests: path to text file with your requests

downloadFolder: path to where the nzbs should be saved

requiredRegexp: regular expression of terms that **every NZB candidate must have**

ignoredRegep: regular expression of terms that **every NZB candidate must NOT have**

movieNameRegexp: regular expression that will extract the name and the group from the nzb name

serieIdRegexp: regular expression that will extract the name of the serie, the season and episode


**Note:** The movieNameRegexp and serieIdRegexp will be case insensitive.


#### requests/wish list


the requests file defined in the configurations must have something like:
```
game thrones s0[6-9]
movie name group
```


This means that it will look for all the NZBs that have *game thrones* in the name, but only episodes in
season 6,7,8,9.

It will also lookup for something that will match all the words "movie", "name" and "group"


## Database
If you want to re-download a NZB, please delete it from the sqlite database.
You can consult the download history in the sqlite database.


## Algorithm
```
           yes
Ignored ----------> Next NZB
   |                    ^
   | No                 |
   |                    |
   v           No       |
Required ---------------+
   |                    ^
   | Yes                |
   |                    |
   v                    |
Extract Name            |
   |                    |
   |                    |
   v                    |
Extract Series          |
   |                    |
   |                    |
   v                    |
Exists in     Yes       |
history   --------------+
   |
   | No
   |
   v
Download movie

```