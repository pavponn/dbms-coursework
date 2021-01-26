-- TournamentGames
-- Read Committed
-- В запросе только читиаем данные единожды, поэтому аномалии 
-- "фантомная запись" и "неповторяемое чтение" не проявляются.
-- Аномалии "косая вставка" нет, так как мы не пишем. Для данного запроса мы
-- не хотим иметь грязные чтения. Так партии, которые не присутствовали 
-- в базе данных  мы здесь не хотим видеть.
create or replace function tournamentGames(_tournamentId bigint)
  returns table (gameId bigint, whiteId bigint, blackId bigint, result GameResult) 
as $$
begin
  return query (
    select g.gameId, g.whiteId, g.blackId, g.result from Games g
    where tournamentId = _tournamentId
  );
end;
$$ language plpgsql;

-- PlayerClubs
-- Read Committed
-- В данном запросе мы только единожды читаем данные, поэтому аномалии "косая запись", "фантомная запись" и "неповторяемое чтение"
-- нет. Read uncommitted не подойдет, потому что мы не хотим получать клубы, в которых пользователь никогда не состоял. Это может 
-- случиться из-за грязного чтения.
create or replace function playerClubs(_playerId bigint) returns table (clubName varchar(100), status MemberStatus) 
as $$
begin
  return query (
    select Clubs.clubName, Memberships.status from
    Clubs natural join Memberships
    where playerId = _playerId
  );
end;
$$ language plpgsql;

-- TournamentParticipants
-- Read Committed
-- Рассуждения аналогичны предудыщим запросам.
create or replace function tournamentParticipants(_tournamentName varchar(100)) returns table (playerId bigint, playerName varchar(100)) 
as $$
begin
  return query (
    select p.playerId, p.playerName 
      from TournamentPlayers 
      natural join Players p
      natural join Tournaments
      where Tournaments.tournamentName = _tournamentName
  );
end;
$$ language plpgsql;


-- ТournamentsWithAllPlayers
-- Repeatable Read
-- Заметим, что нам может помешать аномалия "неповторяемое чтение". Мы два раза читаем из таблицы
-- Tournaments. Между этими чтениями может произойти изменение ключей.
-- Таким образом мы можем вернуть турниры, в которых ни на какой момент времени не участвовали все 
-- игроки. Аномалии "фантомная запись" и "косая запись" нам не мешают.
create or replace function tournamentsWithAllPlayers() returns table (tournamentName varchar(100))
as $$
begin
  return query (
    select t1.tournamentName from Tournaments t1
    where tournamentId not in (
    select tournamentId from Players, Tournaments t2
    where 
      t1.tournamentId = t2.tournamentId 
      and playerId not in (
        select playerId from TournamentPlayers
        where TournamentPlayers.tournamentId = t2.tournamentId
      )
    )
  );
end;
$$ language plpgsql;

-- MainTournamentSponsors
-- Repeatable Read
-- Мы несколько раз выбираем из таблиц Sponsorships и Tournaments.
-- Также может возникнуть проблема с изменением ключей, как в прошлом запросе. 
create or replace function mainTournamentSponsors(_tournamentName varchar(100)) returns table (sponsorId bigint, sponsorName varchar(100)) 
as $$
begin 
  return query (
    select distinct s.sponsorId, s.sponsorName
    from Sponsorships 
    natural join Sponsors s 
    natural join Tournaments
    where 
    amount = (
      select max(amount) from 
      Sponsorships inner join Tournaments 
      on Sponsorships.tournamentId = Tournaments.tournamentId
      where tournamentName = _tournamentName
    ) 
    and tournamentName = _tournamentName

  );
end;
$$ language plpgsql;

-- ClubMembers
-- Read Committed
-- Производим чтение единожды.
create or replace function clubMembers(_clubName varchar(100)) returns table (playerId bigint, playerName varchar(100), status MemberStatus)
as $$
begin
  return query (
    select distinct p.playerId, p.playerName, m.status 
    from Players p inner join
     Memberships m on p.playerId = m.playerId
     inner join Clubs c on c.clubId = m.clubId
    where clubName = _clubName
  );
end;
$$ language plpgsql;


-- ClubsWithMoreExperts
-- Read Commited
-- В запросе только читиаем данные единожды, поэтому аномалии 
-- "фантомная запись" и "неповторяемое чтение" не проявляются.
-- Аномалии "косая вставка" нет, так как мы не пишем. Для данного запроса мы
-- не хотим иметь грязные чтения, поэтому Read Uncommitted не подойдет.
create or replace function clubsWithMoreExperts() returns table (clubName varchar(100)) 
as $$
begin
  return query (
    select ClubStat.clubName from (
      select Clubs.clubId, Clubs.clubName,
        count(case when status = 'Expert' then 1 end) as experts,
        count(case when status = 'Standard' then 1 end) as standards
        from Memberships natural join Clubs
      group by Clubs.clubId, Clubs.clubName
    ) ClubStat where experts > standards
  );
end;
$$ language plpgsql;


-- PlayerScores
-- Repeatable Read
-- Читаем два раза, может возникнуть проблема с ключами как в предыдущих похожих запросах, поэтому ставим 
-- Repeatable Read.
create or replace function playerScores(_playerId bigint) returns table (tournamentName varchar(100), score decimal(10, 1)) 
as $$
begin
  return query (
  select GamesOfPlayer.tournamentName,
    0.0 + sum (
      case 
        when result = 'D' then cast(0.5 AS DECIMAL(10,1))
        when result = 'W' and whiteId = _playerId then cast(1 AS DECIMAL(10,1))
        when result = 'B' and blackId = _playerId then cast(1 AS DECIMAL(10,1))
        else 0 end
    ) from (
      select Tournaments.tournamentName, null as whiteId, null as blackId, null as result 
        from TournamentPlayers natural join Tournaments
        where playerId = _playerId
      union
      select Tournaments.tournamentName, whiteId, blackId, result 
        from Games inner join Tournaments 
        on Games.tournamentId = Tournaments.tournamentId
        where whiteId = _playerId or blackId = _playerId
    ) GamesOfPlayer
    group by GamesOfPlayer.tournamentName
  );
end;
$$ language plpgsql;


-- TournamentBudgetsView
-- Read Commited
-- Происходит единственное чтение. Поэтому аномалии "фантомная запись"
-- и "непвторяемое чтение" не проявляются. Так как мы ничего не пишем, косой записи тоже нет.
-- Бюджеты турниров скорее всего не меняются очень часто, поэтому смысла в read uncommitted нет. 
create or replace view TournamentBudgetsView as
  select tournamentId, tournamentName, SUM(amount) 
  from (
    select Tournaments.tournamentId, tournamentName, coalesce(amount, 0) as amount
      from Tournaments left join Sponsorships on Tournaments.tournamentId = Sponsorships.tournamentId
  ) TournamentsSponsors
  group by tournamentId, tournamentName;


-- Вспомогательное представление
create or replace view Variations as 
  select unnest(enum_range(null::GameVariation)) as Variation;


-- CurrentRatingsView
-- Read Uncommitted
-- Это большой запрос на чтение. Игроков много, поэтому вычисление их текущих рейтингов
-- будет занимать длительное время. Так как в этом случае момент определения текущего рейтинга
-- не определен явно, можно несколько пожертовать точностью данных. В таком случае подойдет
-- read uncommitted.
create or replace view CurrentRatingsView as
  select distinct r1.playerId, r1.variation, r1.rating
  from Ratings r1
  inner join (
    select playerId, variation, max(rtimestamp) as mts
    from Ratings
    group by playerId, variation
  ) r2 
  on r1.playerId = r2.playerId 
  and r1.variation = r2.variation 
  and r1.rtimestamp = r2.mts;


-- AllCurrentRatingsView
-- Read Uncommitted
-- Рассуждения аналогичные тем, что приведены для CurrentRatingsView.
create or replace view AllCurrentRatingsView as
  select distinct pr.playerId, pr.variation, coalesce(pr.rating, 1200) as rating from (
    select p.playerId, v.variation, lr.rating
      from Players p cross join Variations v
      left join CurrentRatingsView lr 
      on p.playerId = lr.playerId
      and v.variation = lr.variation
  ) pr;


-- MaxRatingsView
-- Read Uncommitted
-- Рассуждения аналогичные тем, что приведены для CurrentRatingsView.
create or replace view MaxRatingsView as
  select distinct r1.playerId, r1.variation, r1.rating
  from Ratings r1
  inner join (
    select playerId, variation, max(rating) as rating
    from Ratings
    group by playerId, variation
  ) r2
  on r1.playerId = r2.playerId
  and r1.variation = r2.variation
  and r1.rating = r2.rating;


-- AllMaxRatingsView
-- Read Uncommitted
-- Рассуждения аналогичные тем, что приведены для CurrentRatingsView.
create or replace view AllMaxRatingsView as
  select distinct pr.playerId, pr.variation, coalesce(pr.rating, 1200) as rating from (
  select p.playerId, v.variation, lr.rating
    from Players p cross join Variations v
    left join MaxRatingsView lr 
    on p.playerId = lr.playerId
    and v.variation = lr.variation
  ) pr;

-- ClubLeadersView
-- Read uncommitted
-- Это также большой запрос на чтение. Во время запроса
-- рейтинги игроков могут поменяться, но скорее всего они не меняются сильно.
-- К тому же явно определить на какой момент времени мы получаем лидеров клубов
-- довольно сложно. В связи с этим ставим Read Uncommitted.
create or replace view ClubLeadersView as
    select 
      BestRatings.clubId, playerId, playerName, BestRatings.variation, rating
    from (
      Players natural join 
      AllCurrentRatingsView natural join
      Memberships
    ) MembersWithRatings join
    (
      select clubId, variation, max(rating) as maxRating
      from Memberships natural join AllCurrentRatingsView
      group by Memberships.clubId, variation
    ) BestRatings
    on 
    MembersWithRatings.clubId = BestRatings.clubId and
    MembersWithRatings.rating = BestRatings.maxRating and
    MembersWithRatings.variation = BestRatings.variation;
