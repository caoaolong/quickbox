-- QuickBox：OSS 口令码共享
-- ⚠️ config 内含 AccessKey / SecretAccessKey，以 JSON 明文存放在此表中；请务必限制密钥暴露面并评估是否接受该风险后再启用。

create table if not exists public.cloud_sync_presets (
  id uuid primary key default gen_random_uuid (),
  passcode text not null unique,
  config jsonb not null,
  created_at timestamptz not null default now ()
);

alter table public.cloud_sync_presets enable row level security;

drop policy if exists "deny anon selects" on public.cloud_sync_presets;

create policy "deny anon selects" on public.cloud_sync_presets for select to anon using (false);

drop policy if exists "deny anon inserts" on public.cloud_sync_presets;

create policy "deny anon inserts" on public.cloud_sync_presets for insert to anon with check (false);

drop policy if exists "deny anon updates" on public.cloud_sync_presets;

create policy "deny anon updates" on public.cloud_sync_presets for update to anon using (false);

drop policy if exists "deny anon deletes" on public.cloud_sync_presets;

create policy "deny anon deletes" on public.cloud_sync_presets for delete to anon using (false);

create or replace function public.publish_cloud_sync_preset (p_config jsonb) returns text language plpgsql security definer
set
  search_path = public as $$
declare
  v_pass text;

  v_attempt int := 0;

  v_bucket text := trim(coalesce(p_config->>'bucket', ''));

  v_endpoint text := trim(coalesce(p_config->>'endpoint', ''));

  v_sk text := coalesce(p_config->>'secretAccessKey', '');

  v_ak text := trim(coalesce(p_config->>'accessKeyId', ''));
begin
  if length(v_endpoint) < 5
  or length(v_bucket) < 2 then
    raise exception 'INVALID_CONFIG_ENDPOINT_BUCKET';
  end if;

  if length(v_ak) < 2
  or length(v_sk) < 2 then
    raise exception 'INVALID_CONFIG_CREDENTIALS';
  end if;

  loop
    v_attempt := v_attempt + 1;

    v_pass := substr(
      replace(gen_random_uuid()::text, '-', ''),
      1,
      16
    );

    begin
      insert into public.cloud_sync_presets(passcode, config)
        values (v_pass, p_config);

      return v_pass;
    exception
      when unique_violation then
        if v_attempt >= 32 then
          raise exception 'PASSGEN_FAILED';
        end if;
    end;

  end loop;
end;

$$;

create or replace function public.lookup_cloud_sync_preset (p_passcode text) returns jsonb language plpgsql security definer
set
  search_path = public stable as $$
declare
  v jsonb;

  t text := trim(coalesce(p_passcode, ''));
begin
  if length(t) < 1 then
    return null;
  end if;

  select c.config into v
  from public.cloud_sync_presets c
  where c.passcode = t
  limit 1;

  return v;
end;

$$;

grant execute on function public.publish_cloud_sync_preset (jsonb) to anon;

grant execute on function public.publish_cloud_sync_preset (jsonb) to authenticated;

grant execute on function public.lookup_cloud_sync_preset (text) to anon;

grant execute on function public.lookup_cloud_sync_preset (text) to authenticated;

-- 创建 / 替换函数后刷新 PostgREST schema cache（避免出现 Could not find the function … in the schema cache）
notify pgrst, 'reload schema';
