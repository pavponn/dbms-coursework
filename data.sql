insert into Countries 
  (countryId, countryName) values
  (1, 'Russia'),
  (2, 'Norway'),
  (3, 'USA'),
  (4, 'Netherlands'),
  (5, 'India'),
  (6, 'China'),
  (7, 'Great Britain');


call createPlayer('Pavel Ponomarev', 1, 'pavponn@y.ru', 'ppass');
call createPlayer('Magnus Carlsen', 2, 'magnus@karlsen.com', 'maga');
call createPlayer('Hikaru Nakamura', 3, 'hikaru@nakamura.com', 'hina');
call createPlayer('Ian Nepomniachtchi', 1, 'iannep@mail.ru', 'ya');
call createPlayer('Wesley So', 3, 'weso@goo.com', 'weso');
call createPlayer('Anish Giri', 4, 'ani@giri.nl', 'angi');
call createPlayer('Viswanathan Anand', 5, 'visw@anand.in', 'vian');
call createPlayer('Ding Liren', 6, 'dingliren@ali.cn', 'dili');

call registerClub(1, 'ppass', 'Chess Club 1');
call registerClub(1, 'ppass', 'Chess Сlub Russia', 1);
call registerClub(2, 'maga', 'Blitz Club');
call registerClub(3, 'hina', 'Rapid Club');


insert into Memberships 
  (clubId, playerId, status) values 
  (1, 1, 'Expert'),
  (1, 2, 'Expert'),
  (1, 3, 'Standard'),
  (2, 1, 'Expert'),
  (2, 4, 'Standard'),
  (2, 5, 'Standard'),
  (2, 6, 'Standard'),
  (3, 2, 'Expert'),
  (3, 4, 'Standard'),
  (3, 5, 'Expert'),
  (3, 6, 'Standard');

call changeMemberStatus(1, 'ppass', 2, 5, 'Expert');
call changeMemberStatus(1, 'ppass', 2, 1, 'Standard');

insert into Sponsors 
  (sponsorId, sponsorName) values 
  (1, 'Yandex'),
  (2, 'Chess.com'),
  (3, 'GranChess'),
  (4, 'ITMO University'),
  (5, 'Garry Kasparov');


insert into Tournaments 
(tournamentId, tournamentName, variation, timeControl, startTime, endTime, isRated)
values
(1, 'Gran chess tournament', 'Rapid', ROW('Classic', interval '25 minutes', interval '0 seconds'), 
  current_timestamp, current_timestamp + '5 days', true),
(2, 'Blitz Main Cup', 'Blitz', ROW('Fischer', interval '5 minutes', interval '2 seconds'), 
  current_timestamp + '2 days', current_timestamp + '9 days', true),
(3, 'Fun Tournament', 'Standard', ROW('Nocontrol', interval '0 minutes', interval '0 seconds'), 
  current_timestamp + '4 days', current_timestamp + '2 months', false),
(4, 'Garry Kasparov Tournament', 'Rapid', ROW('Fischer', interval '15 minutes', interval '1 seconds'),
  current_timestamp + '6 days', current_timestamp  + '2 months', true),
(5, 'Empty Tournament', 'Rapid', ROW('Fischer', interval '15 minutes', interval '2 seconds'),
  current_timestamp + '10 days', current_timestamp  + '1 year', false); 

insert into Sponsorships 
  (sponsorId, tournamentId, amount) values 
  (1, 1, 1000.0),
  (1, 2, 100.0),
  (1, 3, 1000.0),
  (1, 4, 100000.00),
  (2, 1, 10000.00),
  (2, 2, 100000.0),
  (2, 3, 9560.00),
  (3, 1, 1040.00),
  (3, 3, 1040.00),
  (3, 2, 1040.00),
  (4, 2, 1040.00),
  (4, 3, 100.00),
  (4, 4, 100000000.0),
  (5, 1, 99999.00),
  (5, 4, 200000.0);

-- Tournament 1
call registerInTournament(1, 'ppass', 1);
call registerInTournament(2, 'maga', 1);
call registerInTournament(3, 'hina', 1);
call registerInTournament(4, 'ya', 1);

insert into Games
(gameId, whiteId, blackId, tournamentId, startTime, result, timeWhite, timeBlack, movesWhite, movesBlack)
  values 
  (1, 1, 2, 1, current_timestamp, 'W', interval '24 minutes 30 seconds', interval '18 minutes 1 seconds', 21, 20),
  (2, 3, 4, 1, current_timestamp, 'D', interval '14 minutes 23 seconds', interval '20 minutes 11 seconds', 31, 31),
  (3, 2, 3, 1, current_timestamp + interval '3 hours', 'B', interval '24 minutes', interval '24 minutes 53 seconds', 41, 41),
  (4, 1, 4, 1, current_timestamp + interval '3 hours', 'D', interval '22 minutes', interval '21 minutes', 14, 13);

-- Tournament 2
call registerInTournament(5, 'weso', 2);
call registerInTournament(6, 'angi', 2);
call registerInTournament(7, 'vian', 2);
call registerInTournament(8, 'dili', 2);

insert into Games
  (gameId, whiteId, blackId, tournamentId, startTime, result, timeWhite, timeBlack, movesWhite, movesBlack)
  values 
  (5, 5, 6, 2, current_timestamp + interval '2 days', 'D', interval '5 minutes 20 seconds', interval '5 minutes 10 seconds', 25, 25),
  (6, 7, 8, 2, current_timestamp + interval '2 days', 'B', interval '6 minutes', interval '5 minutes', 43, 43),
  (7, 6, 7, 2, current_timestamp + interval '2 days 3 hours', 'W', interval '3 minutes 5 seconds', interval '3 minutes 20 seconds', 15, 14),
  (8, 5, 8, 2, current_timestamp + interval '2 days 3 hours', 'D', interval '3 minutes 5 seconds', interval '3 minutes 20 seconds', 15, 14);

-- Tournament 3
call registerInTournament(1, 'ppass', 3);
call registerInTournament(2, 'maga', 3);
call registerInTournament(3, 'hina', 3);
call registerInTournament(4, 'ya', 3);
call registerInTournament(5, 'weso', 3);
call registerInTournament(6, 'angi', 3);
call registerInTournament(7, 'vian', 3);
call registerInTournament(8, 'dili', 3);

insert into Games
  (gameId, whiteId, blackId, tournamentId, startTime, result, timeWhite, timeBlack, movesWhite, movesBlack)
  values 
  (9, 1, 2, 3, current_timestamp + interval '4 days', 'D', interval '25 minutes 20 seconds', interval '15 minutes 10 seconds', 25, 25),
  (10, 3, 4, 3, current_timestamp + interval '4 days', 'B', interval '26 minutes', interval '35 minutes', 41, 40),
  (11, 5, 6, 3, current_timestamp + interval '4 days', 'B', interval '45 minutes 5 seconds', interval '33 minutes 20 seconds', 20, 20),
  (12, 7, 8, 3, current_timestamp + interval '4 days', 'W', interval '50 minutes 5 seconds', interval '44 minutes 20 seconds', 15, 15),
  (13, 1, 4, 3, current_timestamp + interval '4 days 3 hours', 'W', interval '23 minutes 35 seconds', interval '33 minutes 20 seconds', 43, 42),
  (14, 3, 2, 3, current_timestamp + interval '4 days 3 hours', 'W', interval '23 minutes 52 seconds', interval '31 minutes 20 seconds', 31, 31),
  (15, 3, 4, 3, current_timestamp + interval '6 days', 'D', interval '10 minutes 10 seconds', interval '11 minutes 20 seconds', 23, 23);

-- Tournament 4
call registerInTournament(3, 'hina', 4);
call registerInTournament(4, 'ya', 4);
call registerInTournament(5, 'weso', 4);
call registerInTournament(6, 'angi', 4);
call registerInTournament(7, 'vian', 4);

insert into Games
  (gameId, whiteId, blackId, tournamentId, startTime, result, timeWhite, timeBlack, movesWhite, movesBlack)
  values 
    (16, 3, 4, 4, current_timestamp + interval '8 days', 'W', interval '10 minutes 10 seconds', interval '11 minutes 20 seconds', 21, 20);
