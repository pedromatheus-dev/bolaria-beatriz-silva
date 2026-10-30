-- Rode DEPOIS de criar os dois usuários em Authentication > Users.
-- Troque os e-mails pelos que você cadastrou.
insert into public.profiles (id, nome, papel)
select id, 'Dona da bolaria', 'admin'   from auth.users where email = 'dono@exemplo.com';

insert into public.profiles (id, nome, papel)
select id, 'Entregador',      'courier' from auth.users where email = 'entregador@exemplo.com';
