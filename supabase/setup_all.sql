-- Leadership SaaS MVP - complete Supabase setup
create extension if not exists pgcrypto;

create table if not exists public.workspaces (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'مساحة العمل',
  created_at timestamptz not null default now()
);

create table if not exists public.funnels (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  slug text not null unique,
  title text not null,
  headline text,
  description text,
  status text not null default 'draft' check (status in ('draft','published','archived')),
  created_at timestamptz not null default now()
);

create table if not exists public.assessments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid references public.workspaces(id) on delete cascade,
  name text not null,
  version integer not null default 1,
  is_system_template boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.assessments(id) on delete cascade,
  dimension text not null check (dimension in ('commitment','learning','initiative','expectations','followup')),
  prompt text not null,
  weight numeric not null default 1,
  sort_order integer not null,
  is_required boolean not null default true
);

create table if not exists public.question_options (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.questions(id) on delete cascade,
  label text not null,
  score numeric not null check (score between 1 and 4),
  sort_order integer not null
);

create table if not exists public.funnel_assessments (
  funnel_id uuid primary key references public.funnels(id) on delete cascade,
  assessment_id uuid not null references public.assessments(id) on delete restrict
);

create table if not exists public.candidates (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  funnel_id uuid references public.funnels(id) on delete set null,
  name text not null,
  contact_channel text not null check (contact_channel in ('whatsapp','email','phone')),
  contact_value text not null,
  consent_at timestamptz not null default now(),
  stage text not null default 'new' check (stage in ('new','assessment_started','assessment_completed','review','interview_requested','interview_scheduled','follow_up','closed')),
  last_activity_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.candidates(id) on delete cascade,
  assessment_id uuid not null references public.assessments(id) on delete restrict,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.answers (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  option_id uuid not null references public.question_options(id) on delete restrict,
  raw_score numeric not null,
  unique(submission_id,question_id)
);

create table if not exists public.scores (
  submission_id uuid primary key references public.submissions(id) on delete cascade,
  total numeric not null,
  commitment numeric not null,
  learning numeric not null,
  initiative numeric not null,
  expectations numeric not null,
  followup numeric not null,
  band text not null check (band in ('high','medium','low')),
  calculated_at timestamptz not null default now()
);

create table if not exists public.candidate_notes (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.candidates(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  note text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.interview_requests (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.candidates(id) on delete cascade,
  requested_at timestamptz not null default now(),
  preferred_time timestamptz,
  status text not null default 'requested' check (status in ('requested','scheduled','completed','cancelled'))
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.workspaces(owner_id,name)
 values(new.id,coalesce(new.raw_user_meta_data->>'workspace_name','مساحة العمل'));
 return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

insert into public.workspaces(owner_id,name)
select u.id,'مساحة العمل' from auth.users u
where not exists(select 1 from public.workspaces w where w.owner_id=u.id);

alter table public.workspaces enable row level security;
alter table public.funnels enable row level security;
alter table public.assessments enable row level security;
alter table public.questions enable row level security;
alter table public.question_options enable row level security;
alter table public.funnel_assessments enable row level security;
alter table public.candidates enable row level security;
alter table public.submissions enable row level security;
alter table public.answers enable row level security;
alter table public.scores enable row level security;
alter table public.candidate_notes enable row level security;
alter table public.interview_requests enable row level security;

drop policy if exists workspace_owner on public.workspaces;
create policy workspace_owner on public.workspaces for all to authenticated
using(owner_id=auth.uid()) with check(owner_id=auth.uid());

drop policy if exists owner_funnels on public.funnels;
create policy owner_funnels on public.funnels for all to authenticated
using(exists(select 1 from public.workspaces w where w.id=workspace_id and w.owner_id=auth.uid()))
with check(exists(select 1 from public.workspaces w where w.id=workspace_id and w.owner_id=auth.uid()));

drop policy if exists owner_assessments on public.assessments;
create policy owner_assessments on public.assessments for all to authenticated
using(workspace_id is null or exists(select 1 from public.workspaces w where w.id=workspace_id and w.owner_id=auth.uid()))
with check(workspace_id is null or exists(select 1 from public.workspaces w where w.id=workspace_id and w.owner_id=auth.uid()));

drop policy if exists owner_candidates on public.candidates;
create policy owner_candidates on public.candidates for all to authenticated
using(exists(select 1 from public.workspaces w where w.id=workspace_id and w.owner_id=auth.uid()))
with check(exists(select 1 from public.workspaces w where w.id=workspace_id and w.owner_id=auth.uid()));

drop policy if exists owner_notes on public.candidate_notes;
create policy owner_notes on public.candidate_notes for all to authenticated
using(author_id=auth.uid()) with check(author_id=auth.uid());

-- Read access to assessment structure for authenticated leaders.
drop policy if exists auth_questions_read on public.questions;
create policy auth_questions_read on public.questions for select to authenticated using(true);
drop policy if exists auth_options_read on public.question_options;
create policy auth_options_read on public.question_options for select to authenticated using(true);
drop policy if exists auth_funnel_assessments_read on public.funnel_assessments;
create policy auth_funnel_assessments_read on public.funnel_assessments for select to authenticated using(true);

-- System assessment seed (safe to rerun).
do $$
declare aid uuid; qid uuid; d text; p text; i int;
begin
 select id into aid from public.assessments where is_system_template=true and name='Leader Priority Assessment' limit 1;
 if aid is null then
   insert into public.assessments(name,version,is_system_template,is_active)
   values('Leader Priority Assessment',1,true,true) returning id into aid;
   for d,p,i in
     select * from (values
       ('commitment','عندما تلتزم بهدف جديد، ما الأقرب لطريقتك؟',1),
       ('commitment','إذا وعدت بإتمام مهمة خلال أسبوع، ماذا تفعل عادة؟',2),
       ('learning','كيف تتعامل مع ملاحظة تصحح طريقة عملك؟',3),
       ('learning','إذا احتجت مهارة لا تعرفها، ماذا تفعل؟',4),
       ('initiative','عند مواجهة مشكلة غير واضحة، ماذا تفعل؟',5),
       ('initiative','إذا لم تحصل على رد سريع، ماذا تفعل؟',6),
       ('expectations','أي عبارة أقرب لتوقعك من مشروع جديد؟',7),
       ('expectations','إذا كانت النتائج أبطأ مما توقعت، ماذا تفعل؟',8),
       ('followup','كم تستطيع تخصيصه واقعيًا أسبوعيًا للتعلم والمتابعة؟',9),
       ('followup','ما موقفك من المتابعة باحترام بعد تواصل سابق؟',10)
     ) v(d,p,i)
   loop
     insert into public.questions(assessment_id,dimension,prompt,sort_order)
     values(aid,d,p,i) returning id into qid;
     insert into public.question_options(question_id,label,score,sort_order) values
       (qid,'ينطبق علي بدرجة كبيرة',4,1),(qid,'ينطبق علي غالبًا',3,2),
       (qid,'ينطبق علي قليلًا',2,3),(qid,'لا ينطبق علي غالبًا',1,4);
   end loop;
 end if;
end $$;

create or replace function public.calculate_submission_score(p_submission uuid)
returns public.scores language plpgsql security definer set search_path=public as $$
declare r public.scores; c numeric; l numeric; i numeric; e numeric; f numeric; t numeric;
begin
 select
 coalesce(avg(a.raw_score) filter(where q.dimension='commitment'),0),
 coalesce(avg(a.raw_score) filter(where q.dimension='learning'),0),
 coalesce(avg(a.raw_score) filter(where q.dimension='initiative'),0),
 coalesce(avg(a.raw_score) filter(where q.dimension='expectations'),0),
 coalesce(avg(a.raw_score) filter(where q.dimension='followup'),0)
 into c,l,i,e,f from answers a join questions q on q.id=a.question_id where a.submission_id=p_submission;
 c:=c/4*100;l:=l/4*100;i:=i/4*100;e:=e/4*100;f:=f/4*100;t:=(c+l+i+e+f)/5;
 insert into scores(submission_id,total,commitment,learning,initiative,expectations,followup,band)
 values(p_submission,t,c,l,i,e,f,case when t>=80 then 'high' when t>=60 then 'medium' else 'low' end)
 on conflict(submission_id) do update set total=excluded.total,commitment=excluded.commitment,learning=excluded.learning,
 initiative=excluded.initiative,expectations=excluded.expectations,followup=excluded.followup,band=excluded.band,calculated_at=now()
 returning * into r; return r;
end $$;

create or replace function public.get_public_funnel(p_slug text)
returns table(funnel_id uuid,workspace_id uuid,title text,headline text,description text,assessment_id uuid)
language sql stable security definer set search_path=public as $$
 select f.id,f.workspace_id,f.title,f.headline,f.description,fa.assessment_id
 from funnels f join funnel_assessments fa on fa.funnel_id=f.id
 where f.slug=p_slug and f.status='published' limit 1
$$;
grant execute on function public.get_public_funnel(text) to anon,authenticated;

create or replace function public.start_public_application(p_slug text,p_name text,p_channel text,p_contact text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare fid uuid; wid uuid; aid uuid; cid uuid; sid uuid;
begin
 if length(trim(p_name))<2 or length(trim(p_contact))<5 then raise exception 'invalid input'; end if;
 if p_channel not in ('whatsapp','email','phone') then raise exception 'invalid channel'; end if;
 select f.id,f.workspace_id,fa.assessment_id into fid,wid,aid from funnels f join funnel_assessments fa on fa.funnel_id=f.id
 where f.slug=p_slug and f.status='published' limit 1;
 if fid is null then raise exception 'funnel not found'; end if;
 insert into candidates(workspace_id,funnel_id,name,contact_channel,contact_value,stage)
 values(wid,fid,trim(p_name),p_channel,trim(p_contact),'assessment_started') returning id into cid;
 insert into submissions(candidate_id,assessment_id) values(cid,aid) returning id into sid;
 return jsonb_build_object('candidate_id',cid,'submission_id',sid);
end $$;
grant execute on function public.start_public_application(text,text,text,text) to anon,authenticated;

create or replace function public.complete_public_assessment(p_submission uuid,p_answers jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare x jsonb; qid uuid; oid uuid; sc numeric; cid uuid; r scores;
begin
 select candidate_id into cid from submissions where id=p_submission;
 if cid is null then raise exception 'submission not found'; end if;
 for x in select * from jsonb_array_elements(p_answers) loop
   qid=(x->>'question_id')::uuid; oid=(x->>'option_id')::uuid;
   select o.score into sc from question_options o join questions q on q.id=o.question_id
   join submissions s on s.assessment_id=q.assessment_id
   where o.id=oid and q.id=qid and s.id=p_submission;
   if sc is null then raise exception 'invalid answer'; end if;
   insert into answers(submission_id,question_id,option_id,raw_score) values(p_submission,qid,oid,sc)
   on conflict(submission_id,question_id) do update set option_id=excluded.option_id,raw_score=excluded.raw_score;
 end loop;
 update submissions set completed_at=now() where id=p_submission;
 update candidates set stage='assessment_completed',last_activity_at=now() where id=cid;
 r:=calculate_submission_score(p_submission);
 return jsonb_build_object('total',r.total,'commitment',r.commitment,'learning',r.learning,'initiative',r.initiative,'expectations',r.expectations,'followup',r.followup,'band',r.band);
end $$;
grant execute on function public.complete_public_assessment(uuid,jsonb) to anon,authenticated;
