create type GameVariation as enum (
  'Blitz',
  'Rapid',
  'Standard'
);

create type GameResult as enum (
  'W',
  'B',
  'D'
);

create type MemberStatus as enum (
  'Standard',
  'Expert'
);

create type TimeControlFormat as enum (
  'Nocontrol',
  'Classic',
  'Fischer'
);

create type GameTimeControl as (
  controlFormat TimeControlFormat,
  baseTime interval,
  moveTime interval
);

create table Countries (
  countryId bigint not null,
  countryName varchar(75) not null,
  constraint countryId_pk primary key (countryId),
  constraint countryName_uk unique (countryName)
);

create table Tournaments (
  tournamentId bigint not null,
  tournamentName varchar(100) not null,
  variation GameVariation not null,
  timeControl GameTimeControl not null,
  startTime timestamp not null,
  endTime timestamp not null,
  isRated boolean not null,
  constraint tournamentId_pk primary key (tournamentId),
  constraint name_tournament_uk unique (tournamentName),
  constraint check_times_tournaments check (endTime > startTime),
  constraint check_time_control check (
      variation = 'Blitz' and (timeControl).baseTime < interval '10 minutes' or
      variation = 'Rapid' and (timeControl).baseTime >= interval '10 minutes' and (timeControl).baseTime < interval '1 hour' or
      variation = 'Standard' and ((timeControl).baseTime >= interval '1 hour' or (timeControl).controlFormat = 'Nocontrol')
  ),
  constraint check_time_control_format check (
    (timeControl).controlFormat = 'Fischer' and (timeControl).moveTime > interval '0 seconds' or
    (timeControl).controlFormat = 'Classic' and (timeControl).moveTime = interval '0 seconds' or
    (timeControl).controlFormat = 'Nocontrol' and (timeControl).moveTime = interval '0 seconds' 
      and (timeControl).baseTime = interval '0 seconds'
  )
);

create table Sponsors (
  sponsorId bigint not null,
  sponsorName varchar(100) not null,
  constraint sponsorId_pk primary key (sponsorId)
);

create table Sponsorships (
  tournamentId bigint not null,
  sponsorId bigint not null,
  amount decimal(12, 2) not null,
  constraint sponsorships_pk primary key (tournamentId, sponsorId),
  constraint tournamentId_sponsorships_fk foreign key (tournamentId) references Tournaments(tournamentId)
    on delete restrict on update cascade,
  constraint sponsorId_sponsorships_fk foreign key (sponsorId) references Sponsors(sponsorId)
    on delete restrict on update cascade,
  constraint check_amount check (amount > 0)
);

create table Players (
  playerId bigint not null,
  playerName varchar(100) not null,
  countryId bigint not null,
  email varchar(75) not null,
  passHash TEXT not null,
  coachId bigint,
  constraint playerId_pk primary key (playerId),
  constraint email_uk unique (email),
  constraint countryId_player_fk foreign key (countryId) references Countries(countryId)
    on delete restrict on update cascade,
  constraint coachId_fk foreign key (coachId) references Players(playerId)
    on delete set null on update cascade,
  constraint check_self_coaching check (coachId <> playerId)
);

create table Ratings (
  playerId bigint not null,
  variation GameVariation not null,
  rtimestamp timestamp not null,
  rating int not null,
  constraint ratings_pk primary key (playerId, variation, rtimestamp),
  constraint playerId_ratings_fk foreign key (playerId) references Players(playerId)
    on delete restrict on update cascade
);

create table TournamentPlayers (
  tournamentId bigint not null,
  playerId bigint not null,
  constraint tournamentplayers_pk primary key (tournamentId, playerId),
  constraint tournamentId_tournamentplayers_fk foreign key (tournamentId) references Tournaments(tournamentId)
    on delete restrict on update cascade,
  constraint playerId_tournamentplayers_fk foreign key (playerId) references Players(playerId)
    on delete restrict on update cascade
);

create table Games (
  gameId bigint not null,
  whiteId bigint not null,
  blackId bigint not null,
  tournamentId bigint not null,
  startTime timestamp not null,
  result GameResult not null,
  timeWhite interval not null,
  timeBlack interval not null,
  movesWhite int not null,
  movesBlack int not null,
  constraint gameId_pk primary key (gameId),
  constraint white_game_fk foreign key (tournamentId, whiteId) references TournamentPlayers(tournamentId, playerId)
    on delete restrict on update cascade,
  constraint black_game_fk foreign key (tournamentId, blackId) references TournamentPlayers(tournamentId, playerId)
    on delete restrict on update cascade,
  constraint check_moves_game check (movesWhite - movesBlack <= 1 and movesWhite - movesBlack >= 0),
  constraint check_same_player check (whiteId <> blackId)
);

create table Clubs (
  clubId bigint not null,
  clubName varchar(100) not null,
  countryId bigint,
  adminId bigint not null,
  constraint clubId_pk primary key (clubId),
  constraint clubName_uk unique (clubName),
   constraint countryId_club_fk foreign key (countryId) references Countries(countryId)
   on delete set null on update cascade,
  constraint adminId_clubs_fk foreign key (adminId) references Players(playerId)
    on delete restrict on update cascade
);

create table Memberships (
  playerId bigint not null,
  clubId bigint not null,
  status MemberStatus not null,
  constraint memberships_pk primary key (playerId, clubId),
  constraint playerId_memberships_fk foreign key (playerId) references Players(playerId)
    on delete cascade on update cascade,
  constraint clubId_memberships_fk foreign key (clubId) references Clubs(clubId)
    on delete cascade on update cascade
);


-- В PostgreSQL для primary key и unique создаются 
-- упорядоченные индексы (btree) автоматически. Учтем это при
-- добавлении новых индексов.

-- Создадим hash индексы на внешние ключи таблицы Sponsorships. 
-- Зачастую нам необходимо сделать соединение с таблицами Sponsors
-- и Tournaments. Например, это делается в запросе MainTournamentSponsors.
-- У нас уже есть упорядоченный (btree) индекс на (tournamentId, sponsorId).
-- Имеет смысл построить еще один упорядоченный индекс (sponsorId, tournamentId).
-- Заметим, что в таком случае заводить отдельные индексы на tournamentId и 
-- sponsorId не имеет смысла.
create index on Sponsorships using btree(sponsorId, tournamentId);


-- Нам часто необходимо делать соединение таблицы Memberships 
-- c таблицами Clubs и Players.  Например, в запросе ClubMembers.
-- У нас уже есть упорядоченный (btree) индекс на (playerId, clubId).
-- Имеет смысл построить еще один упорядоченный индекс (clubId, playerId).
-- Благодаря такому индексу, если у нас будет только 
-- clubId мы сможем получить все playerId. 
-- Включать или не включать в индекс status -- нужно после проведения соответствующих 
-- замеров.
-- Заметим, что в таком случае заводить отдельные индексы на clubId и 
-- playerId не имеет смысла.
create index on Memberships using btree(clubId, playerId);

-- Это join-таблица, в ней (tournamentId, playerId) является 
-- ключом и для него уже существует btree индекс. Имеет смысл 
-- объявить ещё один упорядоченный индекс, но в другом порядке. 
-- Таким образом мы построим покрывающий индекс. Так сразу по одному
-- playerId мы сразу будет доставать соответствующие tournamentId. 
-- (И наоборот, но такой индекс уже есть). Это нам может помочь, например,
--  в запросе TournamentParticipants.
create index on TournamentPlayers using btree(playerId, tournamentId);

-- Зачастую нам нужно найти игры, в которых
-- принимал участие игрок. Для этого создадим два 
-- хэш индекса на внешние ключи таблицы Games.
-- Пример такого запроса: PlayerScores.
create index on Games using hash(whiteId);
create index on Games using hash(blackId);

-- В запросах, где мы ищем игры по идентификатору турнира,
-- чтобы ускорить этот процесс имеет смысл добавить хэш-индекс
-- для tournamentId из таблицы Games.
create index on Games using hash(tournamentId); 

-- Упорядоченный индекс на (startTime, endTime) в таблицу Tournaments
-- позволит ускорить запросы связанные с поиском турниров 
-- по по времени (началу и концу) их проведения.
create index on Tournaments using btree (startTime, endTime);


-- Имеет смысл создать индекс на внешний ключ adminId в таблице
-- Clubs. Запрос на поиск всех клубов, которыми управляет соответсвующий игрок.
-- Аналогично, с запросом поиска клубов по стране. Для этого нам может понадобится
-- хэш индекс на countryId.
create index on Clubs using hash (adminId);
create index on Clubs using hash (countryId);

-- Для запросов поиска игроков по заданной стране 
-- или по заданному тренеру нам нам понадобится 
-- индекс на countryId а также coachId.
create index on Players using hash (coachId);
create index on Players using hash (countryId);