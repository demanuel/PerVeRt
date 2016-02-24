create table history(
    id INTEGER primary key,
    name text not null,
    episode text default null,
    url text not null,
    release text not null,
    unique(name,episode)
);
