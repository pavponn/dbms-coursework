create extension if not exists pgcrypto;

-- Вспомогательное представление
create or replace view GameMainInfoView as
  select 
   gameId,
   whiteId,
   blackId,
   Games.tournamentId,
   Games.startTime,
   Games.startTime + timeBlack + timeWhite as endTime,
   variation
  from Games inner join Tournaments on Games.tournamentId = Tournaments.tournamentId;

-- CurrentPlayerRating
-- Read Committed
-- Функция не совершает запись, поэтому аномалии "косая запись" нет.
-- Читаем единожды, поэтому аномалии "фантомная запись" и "неповторяемое чтение" нам не страшны.
-- От данной функции требуем, чтобы она вернула рейтинг, который действительно 
-- был у игрока на некоторый момент времени, поэтому read uncommited нам не подойдет.
create or replace function currentPlayerRating(_id bigint, _variation GameVariation) returns int
as $$ 
declare
  res int;
begin
  select rating into res 
  from Ratings r 
  where r.playerId = _id 
  and r.variation = _variation
  order by r.rtimestamp desc
  limit 1;
  return coalesce(res, 1200);
end;
$$ language plpgsql;


-- CalculateEloRatings
-- Функция не производит чтение/запись никаких таблиц.
create or replace function calculateEloRatings(beforeWhite int, 
                                               beforeBlack int, 
                                               result GameResult,
                                               out afterWhite int, 
                                               out afterBlack int)
as $$
declare 
  e_w double precision;
  e_b double precision;
  r_w double precision;
  r_b double precision;
  s_w double precision;
  s_b double precision;
begin
  e_w = 1 / (1 + 10 ^ (cast((beforeBlack - beforeWhite) as double precision) / 400));
  e_b = 1 / (1 + 10 ^ (cast((beforeWhite - beforeBlack) as double precision) / 400));
  if result = 'W' then
    s_w = 1;
    s_b = 0;
  elseif result = 'D' then
    s_w = 0.5;
    s_b = 0.5;
  else 
    s_w = 0;
    s_b = 1;
  end if;
  afterWhite = beforeWhite + cast(20 * (s_w - e_w) as int);
  afterBlack = beforeBlack + cast(20 * (s_b - e_b) as int);
end;
$$ language plpgsql;


-- СheckMovesTime
-- Функция не производит чтение/запись никаких таблиц.
create or replace function checkMovesTime(moves int, 
                                          timeSpent interval,
                                          timeControl GameTimeControl) returns boolean 
as $$
begin
  if (timeControl).controlFormat = 'Nocontrol' then
    return true;
  elseif (timeControl).controlFormat = 'Classic' then
    return timeSpent < (timeControl).baseTime;
  else
    return timeSpent < (timeControl).baseTime + moves * (timeControl).moveTime;
  end if;
end;
$$ language plpgsql;

-- AddGameAndRatingTrigger
-- Serializable
-- Мы считаем, что у игроков не может быть пересекающхися игр, поэтому
-- нам небходимо это проверить. К сожалению, данную проверку нельзя выполнить с помощью check
-- (в postgresql нельзя совершить подазпрос в check, как и в многих других базах данных, также
-- нет возможности создать assertion).
-- Также при подсчете рейтинга мы хотим быть уверены, что эта игра произошла после всех, которые 
-- уже были (это необходимо для того, чтобы правильно посчитать рейтинг).
-- Мы также хотим проверить, что игра действительно происходила во время прохождения турнира.
-- А также время потраченное игроками соответсвует контролю времени турнира.
-- Учитывая все это на спасает только serializable.
-- Данный уровень изоляции можно было бы уменьшить, если бы у нас была внешняя гарантия, что игры 
-- одного и того же игрока не добавляются параллельно разными операциями.
create or replace function AddGameAndRatingTrigger() returns trigger
as $$
declare
 whiteRatingNew int;
 blackRatingNew int;
 tournamentStartTime timestamp;
 tournamentEndTime timestamp;
 cf TimeControlFormat;
 bt interval;
 mt interval;
 tournamentTimeControl GameTimeControl;
 isRatedTournament boolean;
 variationGame GameVariation;
begin
  select 
  startTime, endTime, isRated, variation,
  (timeControl).controlFormat, (timeControl).baseTime, (timeControl).moveTime 
  into tournamentStartTime, tournamentEndTime, isRatedTournament, variationGame, cf, bt, mt 
  from Tournaments where tournamentId = new.tournamentId;

  tournamentTimeControl := ROW(cf, bt, mt);

  if new.startTime < tournamentStartTime then
    raise exception 'Game started before tournament';
  end if;
  if new.startTime + new.timeWhite + new.timeBlack > tournamentEndTime then
    raise exception 'Game ended after tournament ended';
  end if;

  if exists (
    select * from 
      GameMainInfoView g
    where
      (
        g.blackId = new.blackId or
        g.whiteId = new.whiteId or
        g.blackId = new.whiteId or
        g.whiteId = new.blackId
      ) and
      greatest(g.startTime, new.startTime) < least(g.endTime, new.startTime + new.timeWhite + new.timeBlack)
  ) then 
    raise exception 'Game intersects with another game of at least one of the players';
  end if;

  if not checkMovesTime(new.movesWhite, new.timeWhite, tournamentTimeControl) or 
    not checkMovesTime(new.movesWhite, new.timeWhite, tournamentTimeControl) then
      raise exception 'Impossible time spent on game or invalid number of moves';
  end if;

  if isRatedTournament then
    if exists (
      select * from 
        GameMainInfoView g
      where 
        g.endTime >= new.startTime and
        ( 
          g.blackId = new.blackId or
          g.whiteId = new.whiteId or
          g.blackId = new.whiteId or
          g.whiteId = new.blackId
        ) and g.variation = variationGame
    ) then 
      raise exception 'Game is rated and not last for one of the players';
    end if;
    select * into whiteRatingNew, blackRatingNew
    from calculateEloRatings(
      currentPlayerRating(new.whiteId, variationGame),
      currentPlayerRating(new.blackId, variationGame),
      new.result
    );
    insert into Ratings (playerId, variation, rtimestamp, rating) values
    (new.whiteId, variationGame, new.startTime + new.timeWhite + new.timeBlack, whiteRatingNew),
    (new.blackId, variationGame, new.startTime + new.timeWhite + new.timeBlack, blackRatingNew);
  end if;
  
  return new;
end;
$$ language plpgsql;


create trigger AddGameTrigger
before insert on Games
for each row execute procedure AddGameAndRatingTrigger();


-- CheckDeleteGameTrigger
-- Serializable
-- Считаем, что игру можно удалить, если она не рейтинговая или 
-- если она рейтинговая и последняя у обоих игроков (например, были ввведены неверные данные).
-- Аналогично функции AddGameAndRatingTrigger следует запускать только при уровне 
-- изоляции Serializable, иначе можем получить данные с нарушенным инвариантом.
create or replace function CheckDeleteGameTrigger() returns trigger
as $$
declare 
 isRatedTournament boolean;
 variationGame GameVariation;
 lastRatingUpdate timestamp;
begin
  select isRated, variation into isRatedTournament, variationGame
  from Tournaments where tournamentId = new.tournamentId;

  if isRatedTournament then
    select max(rtimestamp) into lastRatingUpdate from Ratings r where
    r.variation = variationGame and (
      r.playerId = old.whiteId or
      r.playerId = old.blackId
    );
    if lastRatingUpdate <> old.startTime + old.timeWhite + old.timeBlack then
      raise exception 
        'Game cannot be deleted safely as it is from rated tournament and not last game of at least one of the players';
    end if;

    delete from Ratings r 
    where 
      r.variation = variationGame and
      r.rtimestamp = old.startTime + old.timeWhite + old.timeBlack (
      r.playerId = old.whiteId or 
      r.playerId = old.blackId
    );
  end if;
  return old;
end;
$$ language plpgsql;


create trigger DeleteGameTrigger
before delete on Games
for each row execute procedure CheckDeleteGameTrigger();

-- CheckUpdateGameTrigger
-- Не производит чтение/запись никаких таблиц.
create or replace function CheckUpdateGameTrigger() returns trigger
as $$
declare
begin
  raise exception 'Update games is forbidden';
  return new;
end;
$$ language plpgsql;

create trigger UpdateGameTrigger
before update on Games
for each row execute procedure CheckUpdateGameTrigger();


-- CheckUpdateTournamentTrigger
-- Serializable
-- Есть аномалия "косая запись". Инвариант такой, что турнир нельзя поменять, 
-- если в нем сыграна игра. Пусть кто-то другой параллельно добавляет игру в турнир. 
-- Мы увидим, что в турнире не сыграны игры, обновим его. Затем кто-то добавит игру
-- но то добавление может привести к нарушению инварианта. Например, теперь в турнире
-- отдается 10 минут каждому игроку, а в добавленной игре по старому формату давалось 20 минут.
-- Из-за этого у нас будет неккоректная игра в таблице относительно турнира. Понятно,
-- что в реальном мире вряд ли кто-то будет менять правила турнира одновременно с сыгранной партией,
-- но даже на такой случай хотелось бы иметь гарантии.
create or replace function CheckUpdateTournamentTrigger() returns trigger
as $$
declare
  tournament_games int default 0;
begin
  select count(*) into tournament_games from Games 
  where tournamentId = old.tournamentId;
  if tournament_games > 0 then
    raise exception 'Update tournaments with played games is forbidden';
  end if;
  return new;
end;
$$ language plpgsql;

create trigger UpdateTournamentTrigger
before update on Games
for each row execute procedure CheckUpdateTournamentTrigger();


-- СreatePlayer
-- Read Commited
-- Так как в транзакции происходит операция вставки, нам как минимум необходим Repeatable Read.
-- Его нам хватает, так как: аномалии косой записи нет (никакой инвариант не ломается),
-- аномалия фантомной записи нам не страшна, так как она происходит только при повторном чтении, которого 
-- у нас нет. Аномалия неповторяемое чтение нам также не страшна (мы не читаем данные повторно).
create or replace procedure createPlayer(in _playerName varchar(100),
                                         in _countryId bigint,
                                         in _email varchar(75),
                                         in _pass text)
language plpgsql
as $$
declare
    pass_hash text;
    id bigint default
      (select coalesce(max(PlayerId), 0) + 1 from Players);
begin
    pass_hash := crypt(_pass, gen_salt('md5'));

    insert into Players(playerId, playerName, countryId, email, passHash)
    values (id, _playerName, _countryId, _email, pass_hash);
end;
$$;

-- CheckCredentials
-- Read Commited
-- Нам хватает Read Committed: так как у нас нет аномалий косой записи (не производится запись),
-- также транзация читает данные единожды, поэтому аномалий неповторяемое чтение и фантомная запись 
-- нам не мешаеют. Read Uncommitted нам очевидно не хватает, так как можем допустить пользователя, 
-- данные, которого еще не были закомичены (а затем откачены).
create or replace procedure checkCredentials(in _playerId bigint,
                                             in _pass text)
language plpgsql
as $$
begin
  if not exists (
    select * from Players 
    where PlayerId = _playerId 
    and crypt(_pass, passHash) = passHash
  ) then 
    raise exception 'Wrong password';
  end if;
end;
$$;

-- RegisterInTournament
-- Read Commited
-- Уровень изоляции как минимум Read Committed, так как он необходим 
-- для checkCredentials. Его нам хватает. Аномалии "косая запись"
-- нет, никакой вариант записью в таблицу TournamentPlayers не нарушается.
-- Аномалии "фантомная запись" и "неповторяемое чтение" нам также не мешают,
-- так как они проявляются только при повторном чтении, которого у нас нет.
create or replace procedure registerInTournament(in _playerId bigint,
                                                 in _pass text,
                                                 in _tournamentId bigint)
language plpgsql
as $$
begin
  call checkCredentials(_playerId, _pass);
  insert into TournamentPlayers(tournamentId, playerId)
    values (_tournamentId, _playerId);
end;
$$;


-- RegisterClub
-- Read Commited
-- Уровень изоляции как минимум Read Committed, так как он необходим 
-- для checkCredentials. Его нам хватает. Аномалии "косая запись"
-- нет, никакой вариант записью в таблицу Сlubs не нарушается.
-- Аномалии "фантомная запись" и "неповторяемое чтение" нам также не мешают,
-- они проявляются только при повторном чтении, здесь читаем максимум единожды.
create or replace procedure registerClub(in _playerId bigint,
                                         in _pass text,
                                         in _clubName text,
                                         in _countryId bigint = null)
language plpgsql
as $$
declare
 id bigint default
      (select coalesce(max(clubId), 0) + 1 from Clubs);
begin 
  call checkCredentials(_playerId, _pass);
  insert into Clubs(clubId, clubName, countryId, adminId) 
  values (id, _clubName, _countryId, _playerId);
end;
$$;

-- ChangeMemberStatus
-- Repeatable Read
-- Нам не подходит Read Committed так как, после проверки что пользователь
-- является администратором клуба, идентификаторы клубов могли быть изменены 
-- (это происходит из-за аномалии "неповторяемое чтение"), что может привести к 
-- обновлению статуса игрока в потенциально другом клубе.
-- Repeatable read нам хватает, так как мы работаем с одним клубом, новые записи 
-- никак не мешают друг другу.
create or replace procedure changeMemberStatus(in _adminId bigint,
                                               in _pass text,
                                               in _clubId bigint,
                                               in _memberId bigint,
                                               in _status MemberStatus)
language plpgsql
as $$
begin
  call checkCredentials(_adminId, _pass);
  if not exists (
    select * from Clubs 
    where adminId = _adminId
    and clubId = _clubId
  ) then 
    raise exception 'Not admin';
  end if;

  update Memberships set status = _status
  where clubId = _clubId
  and playerId = _memberId;
end;
$$;


-- MedianClubRating
-- Repeatable Read
-- Нам не хватает уровня Read Committed. После чтения из таблицы Memberships 
-- для подсчета количества членов клуба. Большая часть членов клуба могла быть удалена в рамках
-- другой транзакции. Следовательно, далее мы можем посчитать медианный
-- рейтинг игроков, состоящих в клубе, равным null. Если в клубе всегда  были члены, то это 
-- получим заведомо неверный результат. Repeatable Read нам хватает: да, могут появится новые записи,
-- в таблице Memberships из-за чего медиана может быть не совсем верна, но мы этого не требуем.
-- Аномалия косая запись нам также не мешает.
create or replace function medianClubRating(_clubId bigint, _variation GameVariation) returns int 
as $$
declare median_position int default 
    (
      select floor(count(*) / 2) 
      from Memberships
      where clubId = _clubId
    );
declare median int default 0;
begin
  select rating into median from
    AllCurrentRatingsView 
    natural join Memberships where 
    clubId = _clubId and
    variation = _variation
    order by rating
    offset median_position
    limit 1;
  
  return median;
end;
$$ language plpgsql;


-- ExpelFromClub
-- Serializable
-- Так как мы используем подсчет медианы, то нам как минимум нужен Repeatable Read.
-- Заметим, что при использовании RepeatableRead после подсчет медианы рейтинга могут быть добавлены
-- члены с более низким рейтингом. Из-за этого после выполнения процедуры в клубе у нас будут присутствовать
-- члены с рейтингом ниже, чем медианный. В случае, когда мы хотим, чтобы в клубе не было игроков с рейтингом ниже 
-- медианного рейтинга, нам подойдет только Serializable. Уровень изоляции snapshot базой данных не предоставляются, 
-- хотя мог бы быть использован: так как в данном случае медианный рейтинг вычисляется для каждого клуба в отдельности,
-- то аномалии "косая запись" нет.
create or replace procedure expelFromClub(in _clubId bigint, 
                                          in _adminId bigint, 
                                          in _pass text,
                                          in _variation GameVariation)
language plpgsql
as $$
declare
  rating_med int default 0;
begin
 call checkCredentials(_adminId, _pass);
  if not exists (
    select * from Clubs 
    where 
    clubId = _clubId and
    adminId = _adminId
  ) then 
    raise exception 'No such club';
  end if;
  rating_med := medianClubRating(_clubId, _variation);

  delete from Memberships where 
    playerId in (
      select m.playerId from Memberships m 
      natural join AllCurrentRatingsView ldr
      where m.clubId = _clubId 
      and rating < rating_med
      and variation = _variation
    )
    and clubId = _clubId;
end;
$$;

