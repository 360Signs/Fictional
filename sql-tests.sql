-- Test runner only.
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
do $$
declare snapshot jsonb;
begin
  snapshot := public.arena_read();
  assert snapshot->>'revision' = '0';
  perform public.arena_apply(0, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '[
    {"bucket":"fighters","action":"add","data":{"id":"a","name":"Alpha","verse":"World"}},
    {"bucket":"fighters","action":"add","data":{"id":"b","name":"Beta","verse":"World"}},
    {"bucket":"battles","action":"add","data":{"id":"fight","winner":"a","loser":"b","result":"easy","date":"2026-11-05T12:00:00Z","voided":false}}
  ]');
  -- The same request ID can be replayed without applying twice.
  assert public.arena_apply(0, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '[]') = 1;
  snapshot := public.arena_read();
  assert jsonb_array_length(snapshot->'fighters') = 2;
  assert jsonb_array_length(snapshot->'battles') = 1;
  assert public.arena_read(1)->>'unchanged' = 'true';
  begin
    perform public.arena_apply(0, gen_random_uuid(), '[]');
    raise exception 'Expected conflict';
  exception when raise_exception then
    if sqlerrm not like 'ARENA_CONFLICT:%' then raise; end if;
  end;
  begin
    perform public.arena_apply(1, gen_random_uuid(), '[{"bucket":"fighters","action":"delete","id":"a"}]');
    raise exception 'Expected missing-combatant error';
  exception when raise_exception then
    if sqlerrm <> 'A battle references a missing combatant' then raise; end if;
  end;
  assert public.arena_read()->>'revision' = '1';
  assert jsonb_array_length(public.arena_read()->'fighters') = 2;
  begin
    perform 1 from public.arena_records;
    raise exception 'Table access must be denied';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
do $$ begin
  assert jsonb_array_length(public.arena_read()->'fighters') = 0;
  perform public.arena_apply(0, gen_random_uuid(), '[{"bucket":"fighters","action":"clear"}]');
end $$;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
do $$ begin
  assert jsonb_array_length(public.arena_read()->'fighters') = 2;
  perform public.arena_apply(1, gen_random_uuid(), '[
    {"bucket":"fighters","action":"clear"},
    {"bucket":"battles","action":"clear"},
    {"bucket":"fighters","action":"add","data":{"id":"c","name":"Gamma","verse":"World"}}
  ]');
  assert jsonb_array_length(public.arena_read()->'fighters') = 1;
  assert jsonb_array_length(public.arena_read()->'battles') = 0;
end $$;
reset role;
set role anon;
do $$ begin
  begin
    perform public.arena_read();
    raise exception 'Anonymous access must be denied';
  exception when insufficient_privilege then null;
  end;
end $$;
