-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- Create content table for storing generated content
create table public.content (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references auth.users(id) not null,
  type text check (type in ('lesson-plan', 'quiz', 'worksheet', 'presentation', 'assessment', 'pedagogy')) not null,
  subject text not null,
  grade text not null,
  chapter text not null,
  content text not null,
  metadata jsonb default '{}'::jsonb not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable Row Level Security (RLS)
alter table public.content enable row level security;

-- Create policies for content
create policy "Users can view their own content"
  on public.content for select
  using (auth.uid() = user_id);

create policy "Users can insert their own content"
  on public.content for insert
  with check (auth.uid() = user_id);

create policy "Users can update their own content"
  on public.content for update
  using (auth.uid() = user_id);

create policy "Users can delete their own content"
  on public.content for delete
  using (auth.uid() = user_id);

-- Create function to update updated_at timestamp
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- Create trigger for updated_at
create trigger handle_updated_at
  before update on public.content
  for each row
  execute function public.handle_updated_at();