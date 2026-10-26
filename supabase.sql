-- Chạy toàn bộ SQL trong Supabase SQL Editor.
create table if not exists public.rcv_game_rooms (
 code text primary key check (code ~ '^[0-9]{6}$'), host_key text not null,
 questions jsonb not null, idx int not null default 0,
 phase text not null default 'waiting' check (phase in ('waiting','open','paused','result')),
 deadline timestamptz, remaining int not null default 15,
 correct_count int not null default 0, created_at timestamptz not null default now()
);
create table if not exists public.rcv_game_students (
 id uuid primary key, code text not null references public.rcv_game_rooms(code) on delete cascade,
 name text not null, number int not null, alive boolean not null default true,
 score int not null default 0, unique(code,number)
);
create unique index if not exists rcv_game_students_name_ci on public.rcv_game_students(code,lower(name));
create table if not exists public.rcv_game_answers (
 code text not null references public.rcv_game_rooms(code) on delete cascade,
 student_id uuid not null references public.rcv_game_students(id) on delete cascade,
 idx int not null, choice int not null check(choice between 0 and 3),
 primary key(student_id,idx)
);
alter table public.rcv_game_rooms enable row level security;
alter table public.rcv_game_students enable row level security;
alter table public.rcv_game_answers enable row level security;
-- Không cấp chính sách truy cập trực tiếp cho anon/authenticated.
create or replace function public.rcv_create(p_host_key text,p_questions jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare c text; i int:=0;
begin
 if length(p_host_key)<32 or jsonb_array_length(p_questions)<1 then raise exception 'Dữ liệu không hợp lệ';end if;
 loop
  c:=lpad((floor(random()*900000)+100000)::int::text,6,'0');
  begin
   insert into public.rcv_game_rooms(code,host_key,questions,remaining)
   values(c,p_host_key,p_questions,(p_questions->0->>'time')::int);
   return c;
  exception when unique_violation then
   i:=i+1; if i>30 then raise exception 'Không tạo được mã phòng';end if;
  end;
 end loop;
end $$;
create or replace function public.rcv_join(p_code text,p_name text,p_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.rcv_game_rooms%rowtype; n int;
begin
 select * into r from public.rcv_game_rooms where code=p_code for update;
 if not found then raise exception 'Không tìm thấy phòng';end if;
 if r.phase<>'waiting' then raise exception 'Phòng đã bắt đầu';end if;
 select count(*) into n from public.rcv_game_students where code=p_code;
 if n>=48 then raise exception 'Phòng đã đủ 48 học sinh';end if;
 if exists(select 1 from public.rcv_game_students where code=p_code and lower(name)=lower(p_name)) then raise exception 'Tên đã tồn tại trong phòng';end if;
 insert into public.rcv_game_students(id,code,name,number) values(p_id,p_code,p_name,n+1);
 return jsonb_build_object('id',p_id,'number',n+1);
end $$;
create or replace function public.rcv_finalize(p_code text) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.rcv_game_rooms%rowtype; ans int;
begin
 select * into r from public.rcv_game_rooms where code=p_code for update;
 if not found or r.phase<>'open' then return;end if;
 ans:=(r.questions->r.idx->>'answer')::int;
 update public.rcv_game_students s set
  score=s.score+case when a.choice=ans then 10 else 0 end,
  alive=(a.choice=ans)
 from (select st.id, an.choice from public.rcv_game_students st
 left join public.rcv_game_answers an on an.student_id=st.id and an.idx=r.idx
 where st.code=p_code and st.alive) a
 where s.id=a.id;
 update public.rcv_game_rooms set phase='result',deadline=null,remaining=0,
 correct_count=(select count(*) from public.rcv_game_answers a join public.rcv_game_students s on s.id=a.student_id
 where a.code=p_code and a.idx=r.idx and a.choice=ans and s.alive)
 where code=p_code;
end $$;
create or replace function public.rcv_state(p_code text,p_role text,p_student_id uuid,p_host_key text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.rcv_game_rooms%rowtype; q jsonb; students jsonb; answer int;
begin
 select * into r from public.rcv_game_rooms where code=p_code;
 if not found then raise exception 'Phòng không tồn tại';end if;
 if p_role='host' then
  if r.host_key is distinct from p_host_key then raise exception 'Không có quyền quản trị';end if;
 elsif p_role='student' then
  if not exists(select 1 from public.rcv_game_students where id=p_student_id and code=p_code) then raise exception 'Học sinh không thuộc phòng';end if;
 else raise exception 'Vai trò không hợp lệ';end if;
 if r.phase='open' and r.deadline<=now() then
  perform public.rcv_finalize(p_code);
  select * into r from public.rcv_game_rooms where code=p_code;
 end if;
 q:=r.questions->r.idx;
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'number',s.number,'alive',s.alive,'score',s.score,
 'answered',exists(select 1 from public.rcv_game_answers a where a.student_id=s.id and a.idx=r.idx)) order by s.number),'[]'::jsonb)
 into students from public.rcv_game_students s where s.code=p_code;
 answer:=case when r.phase='result' then (q->>'answer')::int else null end;
 return jsonb_build_object('code',r.code,'phase',r.phase,'index',r.idx,'total',jsonb_array_length(r.questions),
 'question',jsonb_build_object('text',q->>'text','options',q->'options','time',(q->>'time')::int),
 'deadline',case when r.deadline is null then null else extract(epoch from r.deadline)*1000 end,
 'remaining',r.remaining,'students',students,'answer',answer,'correctCount',r.correct_count,
 'questions',case when p_role='host' then r.questions else null end);
end $$;
create or replace function public.rcv_submit(p_code text,p_id uuid,p_choice int) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.rcv_game_rooms%rowtype;
begin
 select * into r from public.rcv_game_rooms where code=p_code for update;
 if not found or r.phase<>'open' or r.deadline<=now() then raise exception 'Đã hết giờ hoặc chưa mở câu';end if;
 if not exists(select 1 from public.rcv_game_students where code=p_code and id=p_id and alive) then raise exception 'Học sinh không được trả lời';end if;
 if p_choice not between 0 and 3 then raise exception 'Đáp án không hợp lệ';end if;
 if exists(select 1 from public.rcv_game_answers where student_id=p_id and idx=r.idx) then raise exception 'Bạn đã nộp câu này';end if;
 insert into public.rcv_game_answers(code,student_id,idx,choice) values(p_code,p_id,r.idx,p_choice);
end $$;
create or replace function public.rcv_host_action(p_code text,p_host_key text,p_action text,p_questions jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.rcv_game_rooms%rowtype; rem int;
begin
 select * into r from public.rcv_game_rooms where code=p_code for update;
 if not found or r.host_key is distinct from p_host_key then raise exception 'Không có quyền quản trị';end if;
 if r.phase='open' and r.deadline<=now() then
  perform public.rcv_finalize(p_code);
  select * into r from public.rcv_game_rooms where code=p_code;
 end if;
 case p_action
 when 'start' then
  if r.phase='waiting' then
   rem:=(r.questions->r.idx->>'time')::int;
  elsif r.phase='result' and r.idx+1<jsonb_array_length(r.questions) then
   update public.rcv_game_rooms set idx=idx+1 where code=p_code;
   rem:=(r.questions->(r.idx+1)->>'time')::int;
  else raise exception 'Không thể bắt đầu câu tiếp';end if;
  update public.rcv_game_rooms set phase='open',remaining=rem,deadline=now()+make_interval(secs=>rem),correct_count=0 where code=p_code;
 when 'pause' then
  if r.phase<>'open' then raise exception 'Câu chưa chạy';end if;
  rem:=greatest(0,ceil(extract(epoch from (r.deadline-now())))::int);
  update public.rcv_game_rooms set phase='paused',remaining=rem,deadline=null where code=p_code;
 when 'resume' then
  if r.phase<>'paused' then raise exception 'Không ở trạng thái tạm dừng';end if;
  update public.rcv_game_rooms set phase='open',deadline=now()+make_interval(secs=>r.remaining) where code=p_code;
 when 'finish' then
  if r.phase='paused' then update public.rcv_game_rooms set phase='open' where code=p_code;end if;
  perform public.rcv_finalize(p_code);
 when 'rescue' then
  if r.phase='open' then raise exception 'Hãy chốt câu trước khi cứu trợ';end if;
  update public.rcv_game_students set alive=true where code=p_code;
 when 'reset' then
  delete from public.rcv_game_answers where code=p_code;
  update public.rcv_game_students set alive=true,score=0 where code=p_code;
  update public.rcv_game_rooms set idx=0,phase='waiting',deadline=null,remaining=(questions->0->>'time')::int,correct_count=0 where code=p_code;
 when 'setQuestions' then
  if r.phase<>'waiting' then raise exception 'Chỉ sửa trước khi thi';end if;
  if p_questions is null or jsonb_typeof(p_questions)<>'array' or jsonb_array_length(p_questions) not between 1 and 100 then raise exception 'Bộ câu hỏi không hợp lệ';end if;
  update public.rcv_game_rooms set questions=p_questions,idx=0,remaining=(p_questions->0->>'time')::int where code=p_code;
 else raise exception 'Lệnh không hợp lệ';
 end case;
end $$;
-- Chỉ máy chủ sử dụng service_role mới được thực thi RPC.
revoke all on function public.rcv_create(text,jsonb) from public,anon,authenticated;
revoke all on function public.rcv_join(text,text,uuid) from public,anon,authenticated;
revoke all on function public.rcv_finalize(text) from public,anon,authenticated;
revoke all on function public.rcv_state(text,text,uuid,text) from public,anon,authenticated;
revoke all on function public.rcv_submit(text,uuid,int) from public,anon,authenticated;
revoke all on function public.rcv_host_action(text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.rcv_create(text,jsonb),public.rcv_join(text,text,uuid),public.rcv_finalize(text),public.rcv_state(text,text,uuid,text),public.rcv_submit(text,uuid,int),public.rcv_host_action(text,text,text,jsonb) to service_role;
