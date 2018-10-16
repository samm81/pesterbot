to access the pesterbot postgress database:

```
sudo su - postgres
psql
\c pesterbot
```

to list the tables: `\dt`

to dump the database: 

```
sudo su - postgres
pg_dump pesterbot > postgres_pesterbot_XXXX-XX-XX.dump
```

dumps live in the postgres user's home directory, which is `/var/lib/postgresql`

to restore a dump:

```
sudo su - postgres
psql
drop database pesterbot;
create database pesterbot;
\q
psql -U postgres -d pesterbot -1 -f postgres_pesterbot_XXXX-XX-XX.dump
```

to export date,message pairs for a user to csv:
```
sudo su - postgres
psql
\c pesterbot
copy (select inserted_at,timestamp, message_text from messages where sender_id = 'USER_ID_HERE' order by id) to '/tmp/export.csv' delimiter ',' csv;
```
