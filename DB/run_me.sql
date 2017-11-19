create table history(
    id INTEGER PRIMARY KEY,
    language TEXT DEFAULT 'ORiGiNAl',
    title TEXT NOT NULL,
    subtitles TEXT,
    resolution TEXT,
    codec TEXT,
    audio TEXT,
    'group' TEXT,
    episode TEXT,
    source TEXT,
    date TEXT,
    fix TEXT,
    type TEXT,
    search TEXT not null,
    url TEXT not null,
    at TEXT DEFAULT CURRENT_TIMESTAMP,
    valid INTEGER DEFAULT 1 check (valid=0 OR valid=1)
);
