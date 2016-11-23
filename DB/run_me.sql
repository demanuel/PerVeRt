create table history(
    id INTEGER PRIMARY KEY,
    language TEXT DEFAULT 'ENGLiSH',
    title TEXT NOT NULL,
    subtitles TEXT,
    resolution TEXT,
    format TEXT,
    audio TEXT,
    "group" TEXT,
    episode TEXT,
    source TEXT,
    backup TEXT,
    date TEXT,
    container TEXT,
    fix TEXT,
    type TEXT,
    desc TEXT,
    query TEXT not null,
    url TEXT not null,
    valid INTEGER DEFAULT 1 check (valid=0 OR valid=1)
);




